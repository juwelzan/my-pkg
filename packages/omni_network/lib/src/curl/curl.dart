import 'dart:convert';

import 'package:meta/meta.dart';

import '../core/omni_request.dart';
import '../log/redactor.dart';
import '../transport/transport.dart';

String _quote(String s) => "'${s.replaceAll("'", r"'\''")}'";

/// Renders a resolved [request] as a `curl` command.
///
/// With [redact] (default) secrets are masked with [redactor] rules:
/// credential headers, secret query values and JSON/form body keys. Binary
/// and streamed bodies are never inlined. Internal; use
/// `OmniNetwork.toCurl`.
String curlFor(
  TransportRequest request, {
  bool redact = true,
  Redactor redactor = const Redactor(),
}) {
  final parts = <String>['curl'];
  if (request.method != HttpMethod.get) {
    parts.add(
      request.method == HttpMethod.head
          ? '--head'
          : '-X ${request.method.verb}',
    );
  }
  parts.add(
    _quote(redact ? redactor.uri(request.uri) : request.uri.toString()),
  );
  final headers = redact ? redactor.headers(request.headers) : request.headers;
  for (final e in headers.entries) {
    if (e.key == 'content-length') continue;
    parts.add('-H ${_quote('${e.key}: ${e.value}')}');
  }
  final type = request.headers['content-type'] ?? '';
  if (request.bodyStream != null) {
    parts.add(
      "# body: ${request.contentLength ?? '?'} bytes ($type) not included",
    );
  } else if (request.body case final body? when body.isNotEmpty) {
    final textual =
        type.contains('json') ||
        type.contains('x-www-form-urlencoded') ||
        type.startsWith('text/');
    if (!textual) {
      parts.add('# body: ${body.length} bytes ($type) not included');
    } else {
      final text = redact
          ? redactor.body(body, type, maxChars: 1 << 30) ?? ''
          : utf8.decode(body, allowMalformed: true);
      parts.add('--data-raw ${_quote(text)}');
    }
  }
  return parts.join(' \\\n  ');
}

/// Result of [parseCurl].
@immutable
final class CurlImport {
  /// Creates a result.
  const CurlImport(this.request, this.warnings);

  /// The request (absolute URL in `path`).
  final OmniRequest request;

  /// Options that were recognised but ignored, or unsupported.
  final List<String> warnings;
}

/// Splits a shell command line (single/double quotes, backslash escapes,
/// line continuations). Internal.
List<String> shellSplit(String input) {
  final out = <String>[];
  final cur = StringBuffer();
  var inToken = false;
  String? quote;
  for (var i = 0; i < input.length; i++) {
    final c = input[i];
    if (quote == "'") {
      if (c == "'") {
        quote = null;
      } else {
        cur.write(c);
      }
      continue;
    }
    if (quote == '"') {
      if (c == '"') {
        quote = null;
      } else if (c == r'\' &&
          i + 1 < input.length &&
          r'"\$`'.contains(input[i + 1])) {
        cur.write(input[++i]);
      } else {
        cur.write(c);
      }
      continue;
    }
    if (c == r'\' && i + 1 < input.length) {
      final n = input[++i];
      if (n == '\n' || n == '\r') {
        if (n == '\r' && i + 1 < input.length && input[i + 1] == '\n') i++;
        continue;
      }
      cur.write(n);
      inToken = true;
      continue;
    }
    if (c == "'" || c == '"') {
      quote = c;
      inToken = true;
      continue;
    }
    if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
      if (inToken) {
        out.add('$cur');
        cur.clear();
        inToken = false;
      }
      continue;
    }
    cur.write(c);
    inToken = true;
  }
  if (quote != null) {
    throw const FormatException('Unterminated quote in curl command');
  }
  if (inToken) out.add('$cur');
  return out;
}

/// Parses a `curl` command (as copied from browser dev tools or API docs)
/// into an [OmniRequest].
///
/// Supported: URL, `-X/--request`, `-H/--header`, `-d/--data/--data-raw/
/// --data-binary/--data-ascii/--data-urlencode` (repeated values joined
/// with `&`), `--json`, `-u/--user` (→ Basic auth header), `-G/--get`,
/// `-I/--head`, `--url`, `-A/--user-agent`, `-e/--referer`, `-b/--cookie`.
/// Ignored with a warning: `-k`, `-L`, `-s`, `-v`, `--compressed`, `-o`, …
/// Unsupported (warning, skipped): `-F` and `@file` data.
///
/// Throws [FormatException] for input without a URL or with bad quoting.
CurlImport parseCurl(String command) {
  final args = shellSplit(command.trim());
  if (args.isNotEmpty && args.first == 'curl') args.removeAt(0);
  final warnings = <String>[];
  String? url;
  String? method;
  final headers = <String, String>{};
  final data = <String>[];
  var get = false;
  var json = false;

  String take(int i, String flag) {
    if (i + 1 >= args.length) throw FormatException('Missing value for $flag');
    return args[i + 1];
  }

  const ignored = {
    '-k',
    '--insecure',
    '-L',
    '--location',
    '-s',
    '--silent',
    '-S',
    '--show-error',
    '-v',
    '--verbose',
    '--compressed',
    '-i',
    '--include',
    '-f',
    '--fail',
    '-N',
    '--no-buffer',
  };
  const ignoredWithValue = {
    '-o',
    '--output',
    '-m',
    '--max-time',
    '--connect-timeout',
    '-w',
    '--write-out',
    '--retry',
  };

  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    String? inline(String long) =>
        a.startsWith('$long=') ? a.substring(long.length + 1) : null;
    switch (a) {
      case '-X' || '--request':
        method = take(i++, a).toUpperCase();
      case '-H' || '--header':
        final h = take(i++, a);
        final c = h.indexOf(':');
        if (c <= 0) {
          warnings.add('Ignored malformed header "$h"');
        } else {
          headers[h.substring(0, c).trim()] = h.substring(c + 1).trim();
        }
      case '-d' ||
          '--data' ||
          '--data-raw' ||
          '--data-binary' ||
          '--data-ascii':
        final v = take(i++, a);
        if (v.startsWith('@') && a != '--data-raw') {
          warnings.add('File data "$v" is not supported; skipped');
        } else {
          data.add(v);
        }
      case '--data-urlencode':
        final v = take(i++, a);
        final eq = v.indexOf('=');
        data.add(
          eq < 0
              ? Uri.encodeQueryComponent(v)
              : '${v.substring(0, eq)}=${Uri.encodeQueryComponent(v.substring(eq + 1))}',
        );
      case '--json':
        data.add(take(i++, a));
        json = true;
      case '-u' || '--user':
        headers['Authorization'] =
            'Basic ${base64Encode(utf8.encode(take(i++, a)))}';
      case '-A' || '--user-agent':
        headers['User-Agent'] = take(i++, a);
      case '-e' || '--referer':
        headers['Referer'] = take(i++, a);
      case '-b' || '--cookie':
        headers['Cookie'] = take(i++, a);
      case '-G' || '--get':
        get = true;
      case '-I' || '--head':
        method = 'HEAD';
      case '--url':
        url = take(i++, a);
      case '-F' || '--form':
        warnings.add(
          'Multipart -F "${take(i++, a)}" is not supported; skipped',
        );
      default:
        if (inline('--request') case final v?) {
          method = v.toUpperCase();
        } else if (inline('--url') case final v?) {
          url = v;
        } else if (ignored.contains(a)) {
          warnings.add('Ignored option $a');
        } else if (ignoredWithValue.contains(a)) {
          warnings.add('Ignored option $a ${take(i++, a)}');
        } else if (a.startsWith('-')) {
          warnings.add('Unknown option $a ignored');
        } else if (url == null) {
          url = a;
        } else {
          warnings.add('Extra argument "$a" ignored');
        }
    }
  }
  if (url == null) throw const FormatException('No URL in curl command');
  var uri = Uri.parse(url.contains('://') ? url : 'http://$url');
  if (json) {
    headers.putIfAbsent('Content-Type', () => 'application/json');
    headers.putIfAbsent('Accept', () => 'application/json');
  }
  String? bodyText = data.isEmpty ? null : data.join(json ? '' : '&');
  if (get && bodyText != null) {
    uri = uri.replace(
      query: [if (uri.query.isNotEmpty) uri.query, bodyText].join('&'),
    );
    bodyText = null;
  }
  if (bodyText != null &&
      !headers.keys.any((k) => k.toLowerCase() == 'content-type')) {
    headers['Content-Type'] = 'application/x-www-form-urlencoded';
  }
  final verb = method ?? (bodyText != null ? 'POST' : 'GET');
  final m = HttpMethod.values.where((x) => x.verb == verb).firstOrNull;
  if (m == null) throw FormatException('Unsupported method $verb');

  Object? body = bodyText;
  final type = headers.entries
      .where((e) => e.key.toLowerCase() == 'content-type')
      .map((e) => e.value.toLowerCase())
      .firstOrNull;
  if (bodyText != null && (type?.contains('json') ?? false)) {
    try {
      body = jsonDecode(bodyText);
    } on FormatException {
      warnings.add('Body is not valid JSON; kept as text');
    }
  }
  return CurlImport(
    OmniRequest(
      m,
      uri.replace(query: '').toString().replaceFirst(RegExp(r'\?$'), ''),
      query: {
        for (final e in uri.queryParametersAll.entries)
          e.key: e.value.length == 1 ? e.value.single : e.value,
      },
      headers: headers,
      body: body,
    ),
    warnings,
  );
}
