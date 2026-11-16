// The default log output goes through the `logger` package.
import 'dart:async';

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
}
