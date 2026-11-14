/// Dart reserved words and built-in identifiers that cannot be names.
const _reserved = {
  'abstract',
  'as',
  'assert',
  'async',
  'await',
  'base',
  'break',
  'case',
  'catch',
  'class',
  'const',
  'continue',
  'covariant',
  'default',
  'deferred',
  'do',
  'dynamic',
  'else',
  'enum',
  'export',
  'extends',
  'extension',
  'external',
  'factory',
  'false',
  'final',
  'finally',
  'for',
  'Function',
  'get',
  'hide',
  'if',
  'implements',
  'import',
  'in',
  'interface',
  'is',
  'late',
  'library',
  'mixin',
  'new',
  'null',
  'of',
  'on',
  'operator',
  'part',
  'required',
  'rethrow',
  'return',
  'sealed',
  'set',
  'show',
  'static',
  'super',
  'switch',
  'sync',
  'this',
  'throw',
  'true',
  'try',
  'type',
  'typedef',
  'var',
  'void',
  'when',
  'while',
  'with',
  'yield',
  'values',
  'hashCode',
  'runtimeType',
  'toString',
  'noSuchMethod',
  'value',
};

List<String> _words(String s) {
  final spaced = s
      .replaceAllMapped(RegExp('([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .replaceAllMapped(
        RegExp('([A-Z]+)([A-Z][a-z])'),
        (m) => '${m[1]} ${m[2]}',
      );
  return spaced
      .split(RegExp('[^A-Za-z0-9]+'))
      .where((w) => w.isNotEmpty)
      .toList();
}

String _cap(String w) =>
    w.isEmpty ? w : w[0].toUpperCase() + w.substring(1).toLowerCase();

/// `pet_status` / `pet-status` / `PetStatus` → `PetStatus`.
String pascal(String s) {
  final w = _words(s);
  var out = w.map(_cap).join();
  if (out.isEmpty) out = 'Unnamed';
  if (RegExp('^[0-9]').hasMatch(out)) out = 'N$out';
  return out;
}

/// `pet_status` → `petStatus`; reserved words get a `$` suffix.
String camel(String s) {
  final p = pascal(s);
  var out = p[0].toLowerCase() + p.substring(1);
  if (RegExp('^[0-9]').hasMatch(out)) out = 'n$out';
  if (_reserved.contains(out)) out = '$out\$';
  return out;
}

/// Makes [name] unique within [taken] by appending a number.
String unique(String name, Set<String> taken) {
  var n = name;
  for (var i = 2; taken.contains(n); i++) {
    n = '$name$i';
  }
  taken.add(n);
  return n;
}

/// A Dart single-quoted string literal for [s].
String lit(String s) =>
    "'${s.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll(r'$', r'\$').replaceAll('\n', r'\n')}'";

/// A `///` doc comment block for [text], indented by [indent].
String doc(String? text, String indent) {
  if (text == null || text.trim().isEmpty) return '';
  return '${text.trim().split('\n').map((l) => '$indent/// ${l.trimRight()}'.trimRight()).join('\n')}\n';
}
