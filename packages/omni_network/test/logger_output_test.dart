// The default log output goes through the `logger` package.
import 'dart:async';
import 'dart:convert';

import 'package:logger/logger.dart';
import 'package:omni_network/advanced.dart';
import 'package:omni_network/testing.dart';
import 'package:test/test.dart';

class Capture extends LogOutput {
  final events = <OutputEvent>[];
  @override
  void output(OutputEvent event) => events.add(event);
}

String plain(String s) => s.replaceAll(RegExp('\x1B\\[[0-9;]*m'), '');

void main() {
  late OmniMock mock;
  setUp(() {
    mock = OmniMock(basePath: '/v1')
      ..get(
        '/users/{id}',
        (_) => MockResponse.json({'id': 10, 'access_token': 'BODY-SECRET'}),
      )
      ..post('/orders', (_) => MockResponse.json({'error': 'qty'}, status: 422))
      ..get('/boom', (_) => MockResponse.json({}, status: 503))
      ..get('/down', (_) => const MockResponse.offline());
  });

  OmniNetwork client(LogSink sink) => OmniNetwork(
    baseUrl: 'https://api.test/v1',
    headers: {'Authorization': 'Bearer HEADER-SECRET'},
    transport: mock,
    enableLogging: true,
    logSink: sink,
  );

  test('levels: info 2xx, warning 4xx, error 5xx and failures', () async {
    final out = Capture();
    final api = client(
      PrettyLogSink(
        logger: Logger(
          filter: ProductionFilter(),
          printer: SimplePrinter(colors: false),
          output: out,
        ),
      ),
    );
    addTearDown(api.close);
    await api.get<void>('/users/10');
    await api.post<void>('/orders').asResult();
    await api.get<void>('/boom').asResult();
    await api.get<void>('/down').asResult();
    expect(out.events.map((e) => e.level), [
      Level.info,
      Level.warning,
      Level.error,
      Level.error,
    ]);
    final first = out.events.first.lines.join('\n');
    expect(first, contains('GET  https://api.test/v1/users/10'));
    expect(first, contains('✔ 200 OK'));
  });

  test(
    'default output: framed block with emoji; secrets stay redacted',
    () async {
      final printed = <String>[];
      await runZoned(
        () async {
          final api = OmniNetwork(
            baseUrl: 'https://api.test/v1',
            headers: {'Authorization': 'Bearer HEADER-SECRET'},
            transport: mock,
            enableLogging: true,
            logOptions: const LogOptions(headers: true, colors: false),
          );
          await api.get<void>('/users/10');
          await api.post<void>('/orders').asResult();
          await api.close();
        },
        zoneSpecification: ZoneSpecification(
          print: (_, _, _, line) => printed.add(plain(line)),
        ),
      );
      final all = printed.join('\n');
      expect(all, contains('💡 GET  https://api.test/v1/users/10'));
      expect(all, contains('⚠️ ✖ 422'));
      expect(all, contains('"access_token": "***"'));
      expect(all, isNot(contains('BODY-SECRET')));
      expect(all, isNot(contains('HEADER-SECRET')));
      expect(all, isNot(contains('#0')), reason: 'no stack trace');
    },
  );

  test('a printer keeps the classic self-framed block', () async {
    final out = <String>[];
    final api = client(PrettyLogSink(printer: out.add));
    addTearDown(api.close);
    await api.get<void>('/users/10');
    expect(plain(out.single), startsWith('┌'));
    expect(out.single, isNot(contains('💡')));
  });

  group('long responses stay readable', () {
    test('cut-off JSON is still indented, strings kept intact', () {
      final lines = PrettyLogSink.indentJsonText(
        '{"remark":"blogs","data":{"blogs":[{"id":565,"title":"a, b: {c}",'
        '"tags":[]},{"id":566,"desc":"<p style=\\"x\\">h',
      );
      expect(lines, [
        '{',
        '  "remark": "blogs",',
        '  "data": {',
        '    "blogs": [',
        '      {',
        '        "id": 565,',
        '        "title": "a, b: {c}",',
        '        "tags": []',
        '      },',
        '      {',
        '        "id": 566,',
        '        "desc": "<p style=\\"x\\">h',
      ]);
    });

    test('a big response is printed whole: indented, long lines wrapped, '
        'nothing cut', () async {
      final html =
          '<p style="font-family:Times New Roman;">🚨 ${'news ' * 200}</p>';
      final mock = OmniMock(basePath: '/v1')
        ..get(
          '/blogs',
          (_) => MockResponse.json({
            'remark': 'blogs',
            'data': {
              'blogs': [
                for (var i = 0; i < 300; i++)
                  {'id': 565 + i, 'title': '🚨 BREAKING', 'description': html},
              ],
            },
          }),
        );
      final out = <String>[];
      final api = OmniNetwork(
        baseUrl: 'https://api.test/v1',
        transport: mock,
        enableLogging: true,
        logSink: PrettyLogSink(
          options: const LogOptions(colors: false),
          printer: out.add,
        ),
      );
      addTearDown(api.close);
      await api.get<void>('/blogs');
      final lines = out.single
          .split('\n')
          .map((l) => l.replaceFirst('│ ', ''))
          .toList();
      expect(lines, contains('{'));
      expect(lines, contains('  "remark": "blogs",'));
      expect(lines, contains('        "id": 565,'));
      expect(lines, contains('        "id": 864,'), reason: 'last item');
      expect(out.single, isNot(contains('more line')));
      expect(out.single, isNot(contains('truncated')));
      for (final l in lines) {
        expect(l.runes.length, lessThanOrEqualTo(160), reason: l);
        expect(utf8.encode(l).length, lessThan(700), reason: 'phone log');
      }
      // Joining the continuation rows gives back every description whole.
      final joined = lines.join('\n').replaceAll(RegExp(r'\n *↪ '), '');
      expect(
        RegExp(
          RegExp.escape('"description": ${jsonEncode(html)}'),
        ).allMatches(joined),
        hasLength(300),
      );
    });

    test('Bengali text is wrapped by bytes too, never split mid-letter', () {
      final sink = PrettyLogSink(options: const LogOptions(colors: false));
      final text = jsonEncode({'বার্তা': 'আমার সোনার বাংলা ' * 40});
      final rec = NetworkLogRecord(
        kind: NetworkLogKind.response,
        requestId: 1,
        method: 'GET',
        url: 'https://api.test/x',
        message: '',
        statusCode: 200,
        body: text,
      );
      final rows = sink.message(null, rec).split('\n');
      expect(rows.length, greaterThan(4));
      for (final r in rows) {
        expect(utf8.encode(r).length, lessThan(700));
      }
      final joined = rows.join('\n').replaceAll(RegExp(r'\n *↪ '), '');
      expect(joined, contains('আমার সোনার বাংলা ' * 40));
    });

    test('maxLines still cuts when you ask for it', () {
      final sink = PrettyLogSink(
        options: const LogOptions(colors: false, maxLines: 3),
      );
      final rec = NetworkLogRecord(
        kind: NetworkLogKind.response,
        requestId: 1,
        method: 'GET',
        url: 'https://api.test/x',
        message: '',
        statusCode: 200,
        body: jsonEncode([1, 2, 3, 4, 5]),
      );
      expect(sink.message(null, rec), endsWith('… 4 more lines'));
    });
  });

  group('formats', () {
    test('durations', () {
      String f(int ms) =>
          PrettyLogSink.formatDuration(Duration(milliseconds: ms));
      expect(f(0), '0 ms');
      expect(f(84), '84 ms');
      expect(f(999), '999 ms');
      expect(f(1240), '1.24 s');
      expect(f(59990), '59.99 s');
      expect(f(125000), '2 min 05 s');
      expect(PrettyLogSink.formatDuration(null), '0 ms');
    });

    test('date and time', () {
      expect(
        PrettyLogSink.formatDateTime(DateTime(2026, 1, 7, 9, 5, 3, 7)),
        '2026-01-07 09:05:03.007',
      );
    });

    test('JSON spans: keys, strings, numbers, literals, punctuation', () {
      final spans = PrettyLogSink.jsonSpans(
        '  "a\\"b": "x, y: {z}", "n": -1.5e3, "t": true, "z": null,',
      );
      expect(
        spans.map((s) => s.$1).join(),
        '  "a\\"b": "x, y: {z}", "n": -1.5e3, "t": true, "z": null,',
      );
      String? colorOf(String text) =>
          spans.firstWhere((s) => s.$1.contains(text)).$2;
      expect(colorOf('"a'), '38;5;81');
      expect(colorOf('"x, y'), '38;5;186');
      expect(colorOf('-1.5e3'), '38;5;141');
      expect(colorOf('true'), '38;5;205');
      expect(colorOf('null'), '38;5;205');
    });

    test('logger output: date-time line, green success, red failure', () async {
      final out = Capture();
      final mock = OmniMock()
        ..get('/ok', (_) => MockResponse.json({'id': 1}))
        ..get('/bad', (_) => MockResponse.json({'e': 1}, status: 404));
      final api = OmniNetwork(
        baseUrl: 'https://api.test',
        transport: mock,
        enableLogging: true,
        logOptions: const LogOptions(colors: true),
      );
      // Route the default logger's lines into [out].
      addTearDown(api.close);
      final printed = <String>[];
      await runZoned(
        () async {
          await api.get<void>('/ok');
          await api.get<void>('/bad').asResult();
        },
        zoneSpecification: ZoneSpecification(
          print: (_, _, _, line) => printed.add(line),
        ),
      );
      expect(out.events, isEmpty);
      final all = printed.join('\n');
      expect(
        plain(all),
        contains(RegExp(r'│ \d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d{3}\n')),
      );
      final ok = printed.firstWhere((l) => l.contains('✔ 200'));
      final bad = printed.firstWhere((l) => l.contains('✖ 404'));
      expect(ok, startsWith('\x1B[38;5;40m'), reason: 'green line');
      expect(bad, startsWith('\x1B[38;5;196m'), reason: 'red line');
      expect(plain(all), contains('· 0 ms'));
    });
  });
}
