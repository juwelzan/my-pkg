import 'dart:convert';

import 'package:yaml/yaml.dart';

import 'names.dart';

/// Result of [generate].
final class GenerationResult {
  /// Creates a result.
  const GenerationResult(this.code, this.warnings);

  /// The generated Dart library.
  final String code;

  /// Things that were skipped or simplified.
  final List<String> warnings;
}

/// Parses an OpenAPI document given as JSON or YAML text.
Map<String, Object?> parseSpec(String text) {
  final trimmed = text.trimLeft();
  final Object? raw = trimmed.startsWith('{')
      ? jsonDecode(text)
      : loadYaml(text);
  final plain = _plain(raw);
  if (plain is! Map<String, Object?>) {
    throw const FormatException('OpenAPI document must be an object');
  }
  final version = '${plain['openapi'] ?? ''}';
  if (!version.startsWith('3.')) {
    throw FormatException(
      'Only OpenAPI 3.x is supported (found "${plain['openapi'] ?? plain['swagger'] ?? '?'}")',
    );
  }
  return plain;
}

Object? _plain(Object? v) => switch (v) {
  YamlMap() ||
  Map() => {for (final e in (v as Map).entries) '${e.key}': _plain(e.value)},
  YamlList() || List() => [for (final e in v as List) _plain(e)],
  _ => v,
};

/// A Dart type for a schema.
final class _Type {
  const _Type(this.kind, this.name, {this.item, this.nullable = false});
  final String
  kind; // String,int,double,num,bool,DateTime,class,enum,list,map,any
  final String name; // Dart type without `?`
  final _Type? item;
  final bool nullable;

  _Type asNullable(bool n) => _Type(kind, name, item: item, nullable: n);
  String get dart => kind == 'any'
      ? 'Object?'
      : nullable
      ? '$name?'
      : name;

  String decode(String v) {
    final core = switch (kind) {
      'String' || 'bool' => '$v as $name',
      'int' => '($v as num).toInt()',
      'double' => '($v as num).toDouble()',
      'num' => '$v as num',
      'DateTime' => 'DateTime.parse($v as String)',
      'class' => '$name.fromJson($v as Map<String, dynamic>)',
      'enum' => '$name.fromJson($v as String)',
      'list' =>
        '($v as List<dynamic>).map((e) => ${item!.decode('e')}).toList()',
      'map' =>
        '($v as Map<String, dynamic>).map((k, e) => MapEntry(k, ${item!.decode('e')}))',
      _ => v,
    };
    if (!nullable || kind == 'any') return core;
    return switch (kind) {
      'String' || 'bool' || 'num' => '$v as $name?',
      'int' => '($v as num?)?.toInt()',
      'double' => '($v as num?)?.toDouble()',
      _ => '$v == null ? null : $core',
    };
  }

  String encode(String v) {
    final q = nullable ? '?' : '';
    return switch (kind) {
      'DateTime' => '$v$q.toIso8601String()',
      'class' || 'enum' => '$v$q.toJson()',
      'list' =>
        item!.isPlain
            ? v
            : '$v$q.map((e) => ${item!.asNullable(item!.nullable).encode('e')}).toList()',
      'map' =>
        item!.isPlain
            ? v
            : '$v$q.map((k, e) => MapEntry(k, ${item!.encode('e')}))',
      _ => v,
    };
  }

  bool get isPlain =>
      const {'String', 'int', 'double', 'num', 'bool', 'any'}.contains(kind) ||
      ((kind == 'list' || kind == 'map') && item!.isPlain);
}

final class _Field {
  _Field(this.json, this.dart, this.type, this.required, this.description);
  final String json;
  final String dart;
  final _Type type;
  final bool required;
  final String? description;
}

/// Generates the Dart library for [spec].
///
/// [apiName] names the endpoint holder class (default: from `info.title`).
/// [source] is mentioned in the header comment.
GenerationResult generate(
  Map<String, Object?> spec, {
  String? apiName,
  String source = 'openapi spec',
}) => _Generator(spec, apiName, source).run();

final class _Generator {
  _Generator(this.spec, this.apiName, this.source);

  final Map<String, Object?> spec;
  final String? apiName;
  final String source;
  final warnings = <String>[];
  final _classNames = <String>{};
  final _schemaClass = <String, String>{}; // component name -> Dart name
  final _models = StringBuffer();
  final _emitted = <String>{};
  final _pendingInline = <(String, Map<String, Object?>)>[];

  Map<String, Object?> get _schemas =>
      ((spec['components'] as Map?)?['schemas'] as Map<String, Object?>?) ?? {};

  Map<String, Object?> _resolve(Map<String, Object?> s) {
    final ref = s[r'$ref'];
    if (ref is! String) return s;
    const prefix = '#/components/';
    if (!ref.startsWith(prefix)) {
      throw FormatException('Only local \$refs are supported: $ref');
    }
    Object? node = spec['components'];
    for (final part in ref.substring(prefix.length).split('/')) {
      node = (node as Map?)?[part.replaceAll('~1', '/').replaceAll('~0', '~')];
    }
    if (node is! Map<String, Object?>) {
      throw FormatException('Unresolvable \$ref $ref');
    }
    return _resolve(node);
  }

  GenerationResult run() {
    for (final name in _schemas.keys) {
      _schemaClass[name] = unique(pascal(name), _classNames);
    }
    for (final e in _schemas.entries) {
      _emitSchema(_schemaClass[e.key]!, e.value! as Map<String, Object?>);
    }
    final endpoints = _endpoints();
    while (_pendingInline.isNotEmpty) {
      final (n, s) = _pendingInline.removeAt(0);
      _emitSchema(n, s);
    }
    final info = (spec['info'] as Map?) ?? {};
    final servers = (spec['servers'] as List?) ?? const [];
    final header = StringBuffer()
      ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND.')
      ..writeln('// Generated by omni_network_openapi from $source.')
      ..writeln(
        '// ${info['title'] ?? 'API'} ${info['version'] ?? ''}'.trimRight(),
      );
    if (servers.isNotEmpty) {
      header.writeln('// Server: ${(servers.first as Map)['url']}');
    }
    header
      ..writeln()
      ..writeln('// ignore_for_file: type=lint')
      ..writeln()
      ..writeln("import 'package:omni_network/omni_network.dart';")
      ..writeln();
    return GenerationResult(
      '$header$_models$endpoints'.replaceAll(RegExp(r'\n{3,}'), '\n\n'),
      warnings,
    );
  }

  // ---------------------------------------------------------------- types

  _Type _typeOf(
    Map<String, Object?> schema,
    String context, {
    bool nullable = false,
  }) {
    final ref = schema[r'$ref'];
    if (ref is String) {
      final name = ref.split('/').last;
      final cls = _schemaClass[name];
      if (cls == null) throw FormatException('Unknown schema \$ref $ref');
      final target = _resolve(schema);
      final kind = target['enum'] != null
          ? 'enum'
          : _isObject(target)
          ? 'class'
          : null;
      if (kind == null) return _typeOf(target, context, nullable: nullable);
      return _Type(kind, cls, nullable: nullable);
    }
    var type = schema['type'];
    var isNullable = nullable || schema['nullable'] == true;
    if (type is List) {
      isNullable = isNullable || type.contains('null');
      final rest = type.where((t) => t != 'null').toList();
      type = rest.length == 1 ? rest.single : null;
    }
    if (schema['allOf'] is List) {
      final cls = unique(pascal(context), _classNames);
      _pendingInline.add((cls, schema));
      return _Type('class', cls, nullable: isNullable);
    }
    if (schema['oneOf'] != null || schema['anyOf'] != null) {
      warnings.add('$context: oneOf/anyOf mapped to Object?');
      return const _Type('any', 'Object?');
    }
    if (schema['enum'] is List && type == 'string') {
      final name = unique(pascal(context), _classNames);
      _pendingInline.add((name, schema));
      return _Type('enum', name, nullable: isNullable);
    }
    switch (type) {
      case 'string':
        final f = schema['format'];
        return _Type(
          f == 'date-time' ? 'DateTime' : 'String',
          f == 'date-time' ? 'DateTime' : 'String',
          nullable: isNullable,
        );
      case 'integer':
        return _Type('int', 'int', nullable: isNullable);
      case 'number':
        return _Type('double', 'double', nullable: isNullable);
      case 'boolean':
        return _Type('bool', 'bool', nullable: isNullable);
      case 'array':
        final items = schema['items'] as Map<String, Object?>? ?? const {};
        final item = _typeOf(items, '${context}Item');
        return _Type(
          'list',
          'List<${item.dart}>',
          item: item,
          nullable: isNullable,
        );
      case 'object' || null when _isObject(schema):
        if ((schema['properties'] as Map?)?.isNotEmpty ?? false) {
          final cls = unique(pascal(context), _classNames);
          _pendingInline.add((cls, schema));
          return _Type('class', cls, nullable: isNullable);
        }
        final ap = schema['additionalProperties'];
        final item = ap is Map<String, Object?>
            ? _typeOf(ap, '${context}Value')
            : const _Type('any', 'Object?');
        return _Type(
          'map',
          'Map<String, ${item.dart}>',
          item: item,
          nullable: isNullable,
        );
      default:
        return const _Type('any', 'Object?');
    }
  }

  bool _isObject(Map<String, Object?> s) =>
      s['type'] == 'object' ||
      s['properties'] != null ||
      s['allOf'] != null ||
      (s['type'] == null && s['additionalProperties'] != null);

  // --------------------------------------------------------------- models

  void _emitSchema(String name, Map<String, Object?> schema) {
    if (!_emitted.add(name)) return;
    final s = _resolve(schema);
    if (s['enum'] is List) {
      _emitEnum(name, s);
    } else if (s['allOf'] is List ||
        (s['properties'] as Map?)?.isNotEmpty == true) {
      _emitClass(name, s);
    } else {
      final t = _typeOf({...s, 'description': null}, name);
      _models
        ..write(doc(s['description'] as String?, ''))
        ..writeln('typedef $name = ${t.dart};')
        ..writeln();
    }
  }

  void _emitEnum(String name, Map<String, Object?> s) {
    final values = (s['enum']! as List).map((e) => '$e').toList();
    final taken = <String>{};
    _models
      ..write(doc(s['description'] as String?, ''))
      ..writeln('enum $name {');
    for (var i = 0; i < values.length; i++) {
      final id = unique(camel(values[i]), taken);
      _models.writeln(
        '  $id(${lit(values[i])})${i == values.length - 1 ? ';' : ','}',
      );
    }
    _models
      ..writeln()
      ..writeln('  const $name(this.value);')
      ..writeln()
      ..writeln('  /// Wire value.')
      ..writeln('  final String value;')
      ..writeln()
      ..writeln(
        '  /// Parses a wire value; throws [FormatException] for unknown ones.',
      )
      ..writeln('  static $name fromJson(String value) => values.firstWhere(')
      ..writeln('        (e) => e.value == value,')
      ..writeln(
        "        orElse: () => throw FormatException('Unknown $name: \$value'),",
      )
      ..writeln('      );')
      ..writeln()
      ..writeln('  /// Wire value.')
      ..writeln('  String toJson() => value;')
      ..writeln('}')
      ..writeln();
  }

  void _collect(
    Map<String, Object?> s,
    Map<String, Map<String, Object?>> props,
    Set<String> required,
  ) {
    final r = _resolve(s);
    for (final part in (r['allOf'] as List?) ?? const []) {
      _collect(part as Map<String, Object?>, props, required);
    }
    for (final e
        in ((r['properties'] as Map<String, Object?>?) ?? {}).entries) {
      props[e.key] = e.value! as Map<String, Object?>;
    }
    required.addAll(((r['required'] as List?) ?? const []).cast<String>());
  }

  void _emitClass(String name, Map<String, Object?> s) {
    final props = <String, Map<String, Object?>>{};
    final required = <String>{};
    _collect(s, props, required);
    final taken = <String>{};
    final fields = [
      for (final e in props.entries)
        () {
          final isReq = required.contains(e.key);
          final t = _typeOf(e.value, '$name ${e.key}');
          final type = t.asNullable(t.nullable || !isReq);
          return _Field(
            e.key,
            unique(camel(e.key), taken),
            type,
            isReq,
            _resolve(e.value)['description'] as String? ??
                e.value['description'] as String?,
          );
        }(),
    ];
    final b = _models
      ..write(doc(s['description'] as String?, ''))
      ..writeln('final class $name {')
      ..writeln('  /// Creates a [$name].')
      ..write('  const $name(');
    if (fields.isEmpty) {
      b.writeln(');');
    } else {
      b.writeln('{');
      for (final f in fields) {
        b.writeln('    ${f.type.nullable ? '' : 'required '}this.${f.dart},');
      }
      b.writeln('  });');
    }
    b
      ..writeln()
      ..writeln('  /// Decodes a JSON object.')
      ..writeln(
        '  factory $name.fromJson(Map<String, dynamic> json) => $name(',
      );
    for (final f in fields) {
      b.writeln('        ${f.dart}: ${f.type.decode('json[${lit(f.json)}]')},');
    }
    b.writeln('      );');
    for (final f in fields) {
      b
        ..writeln()
        ..write(doc(f.description ?? f.json, '  '))
        ..writeln('  final ${f.type.dart} ${f.dart};');
    }
    b
      ..writeln()
      ..writeln(
        '  /// Encodes to a JSON object (null optional fields omitted).',
      )
      ..writeln('  Map<String, dynamic> toJson() => {');
    for (final f in fields) {
      final enc = f.type.encode(f.dart);
      b.writeln(
        f.type.nullable
            ? '        if (${f.dart} != null) ${lit(f.json)}: $enc,'
            : '        ${lit(f.json)}: $enc,',
      );
    }
    b
      ..writeln('      };')
      ..writeln('}')
      ..writeln();
  }

  // ------------------------------------------------------------ endpoints

  String _endpoints() {
    final title = '${(spec['info'] as Map?)?['title'] ?? 'Api'}';
    final cls = unique(apiName ?? '${pascal(title)}Api', _classNames);
    final b = StringBuffer()
      ..writeln('/// Endpoints of ${title.trim()}.')
      ..writeln('abstract final class $cls {');
    final names = <String>[];
    final taken = <String>{'registry'};
    final paths = (spec['paths'] as Map<String, Object?>?) ?? {};
    const methods = ['get', 'post', 'put', 'patch', 'delete', 'head'];
    for (final pe in paths.entries) {
      final item = pe.value! as Map<String, Object?>;
      final shared = (item['parameters'] as List?) ?? const [];
      for (final m in methods) {
        final op = item[m] as Map<String, Object?>?;
        if (op == null) continue;
        if (m == 'head') {
          warnings.add('HEAD ${pe.key}: not generated (use api.head)');
          continue;
        }
        final opId = op['operationId'] as String?;
        final id = unique(camel(opId ?? '$m ${pe.key}'), taken);
        names.add(id);
        // Path params: rename to valid identifiers.
        var template = pe.key;
        final params = [
          ...shared.map((p) => _resolve(p as Map<String, Object?>)),
          ...((op['parameters'] as List?) ?? const []).map(
            (p) => _resolve(p as Map<String, Object?>),
          ),
        ];
        final notes = <String>[];
        for (final p in params) {
          final pname = '${p['name']}';
          final where = p['in'];
          if (where == 'path') {
            final safe = camel(pname).replaceAll(r'$', '');
            template = template.replaceAll('{$pname}', '{$safe}');
            notes.add('Path `$safe`${safe != pname ? ' (`$pname`)' : ''}.');
          } else if (where == 'query') {
            notes.add(
              'Query `$pname`${p['required'] == true ? ' (required)' : ''}.',
            );
          } else {
            notes.add(
              '${'$where'[0].toUpperCase()}${'$where'.substring(1)} parameter `$pname`: pass via `headers`.',
            );
            if (where == 'cookie') {
              warnings.add('$id: cookie parameter $pname not generated');
            }
          }
        }
        final body = op['requestBody'] as Map<String, Object?>?;
        if (body != null) {
          final content =
              (_resolve(body)['content'] as Map<String, Object?>?) ?? {};
          final jsonType = content.keys
              .where((k) => k.contains('json'))
              .firstOrNull;
          if (jsonType != null) {
            final schema =
                (content[jsonType]! as Map)['schema'] as Map<String, Object?>?;
            if (schema != null) {
              notes.add(
                'Body: `${_typeOf(schema, '$id Body').dart}` as JSON (`body: x.toJson()`).',
              );
            }
          } else if (content.isNotEmpty) {
            notes.add('Body: ${content.keys.join(', ')}.');
            if (content.keys.any((k) => k.startsWith('multipart/'))) {
              warnings.add('$id: multipart body; use api.upload');
            }
          }
        }
        final (type, decoder, list) = _responseOf(op, id);
        final verb = m == 'get' && list ? 'getList' : m;
        final tags = ((op['tags'] as List?) ?? const []).cast<String>();
        final args = <String>[
          lit(template),
          if (decoder != null) 'decoder: $decoder',
          'name: ${lit(opId ?? id)}',
          if ((op['summary'] ?? op['description']) case final String d)
            'description: ${lit(d.trim().split('\n').first)}',
          if (tags.isNotEmpty) 'tags: {${tags.map(lit).join(', ')}}',
        ];
        final typeArg = verb == 'getList' ? decoder!.split('.').first : type;
        b
          ..writeln()
          ..write(
            doc(
              [
                if (op['summary'] case final String s) s,
                if (op['description'] case final String d) d,
                ...notes,
                if (op['deprecated'] == true) 'Deprecated by the API.',
              ].join('\n\n'),
              '  ',
            ),
          );
        if (op['deprecated'] == true) {
          b.writeln("  @Deprecated('Deprecated by the API')");
        }
        b.writeln(
          '  static final $id = Endpoint.$verb<$typeArg>(${args.join(', ')});',
        );
      }
    }
    b
      ..writeln()
      ..writeln('  /// Every endpoint above.')
      ..writeln(
        '  static final registry = EndpointRegistry([${names.join(', ')}]);',
      )
      ..writeln('}');
    return '$b';
  }

  /// (Dart type, decoder expression, isListOfObjects)
  (String, String?, bool) _responseOf(Map<String, Object?> op, String id) {
    final responses = (op['responses'] as Map<String, Object?>?) ?? {};
    final codes = responses.keys.where((c) => c.startsWith('2')).toList()
      ..sort();
    if (codes.isEmpty) return ('void', null, false);
    final res = _resolve(responses[codes.first]! as Map<String, Object?>);
    final content = (res['content'] as Map<String, Object?>?) ?? {};
    final jsonType = content.keys.where((k) => k.contains('json')).firstOrNull;
    if (jsonType == null) {
      if (content.keys.any((k) => k.startsWith('text/'))) {
        return ('String', null, false);
      }
      return (content.isEmpty ? 'void' : 'Object?', null, false);
    }
    final schema =
        (content[jsonType]! as Map)['schema'] as Map<String, Object?>?;
    if (schema == null) return ('Object?', null, false);
    final t = _typeOf(schema, '$id Response');
    if (t.kind == 'class') return (t.name, '${t.name}.fromJson', false);
    if (t.kind == 'list' && t.item!.kind == 'class' && !t.item!.nullable) {
      return ('List<${t.item!.name}>', '${t.item!.name}.fromJson', true);
    }
    if (const {'String', 'bool', 'num'}.contains(t.kind)) {
      return (t.name, null, false);
    }
    if (t.kind == 'int' || t.kind == 'double') return ('num', null, false);
    if (t.kind == 'map') return ('Map<String, dynamic>', null, false);
    if (t.kind == 'list') return ('List<dynamic>', null, false);
    return ('Object?', null, false);
  }
}
