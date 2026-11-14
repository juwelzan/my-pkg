@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:omni_network/advanced.dart';
import 'package:test/test.dart';

/// Real DioTransport + files against a loopback server (no internet).
void main() {
  final data = Uint8List.fromList(List.generate(200000, (i) => i % 253));
  late HttpServer server;
  late OmniNetwork api;
  late Directory dir;
  final ranges = <String?>[];
  var honourRange = true;
  late List<int> uploaded;
  String? uploadType;
  int? uploadLength;

  setUp(() async {
    ranges.clear();
    honourRange = true;
    dir = await Directory.systemTemp.createTemp('omni_net_');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final res = req.response;
      if (req.uri.path == '/upload') {
        uploadType = req.headers.contentType?.mimeType;
        uploadLength = req.headers.contentLength;
        uploaded = (await req.toList()).expand((c) => c).toList();
        res.headers.contentType = ContentType.json;
        res.write('{"received":${uploaded.length}}');
        await res.close();
        return;
      }
      await req.drain<void>();
      final range = req.headers.value('range');
      ranges.add(range);
      var start = 0;
      if (range != null && honourRange) {
        start = int.parse(range.substring(6, range.length - 1));
        res.statusCode = 206;
      }
      res.contentLength = data.length - start;
      // Stream in chunks so cancellation can happen mid-way.
      for (var i = start; i < data.length; i += 20000) {
        res.add(
          data.sublist(i, i + 20000 > data.length ? data.length : i + 20000),
        );
        await res.flush();
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await res.close().catchError((_) {});
    });
    api = OmniNetwork(baseUrl: 'http://127.0.0.1:${server.port}');
  });

  tearDown(() async {
    await api.close();
    await server.close(force: true);
    await dir.delete(recursive: true);
  });

  test('multipart upload over Dio', () async {
    final progress = <int>[];
    final res = await api.upload<Map<String, dynamic>>(
      '/upload',
      fields: {'k': 'v'},
      files: [UploadFile.fromBytes('f', data, filename: 'd.bin')],
      onProgress: (s, _) => progress.add(s),
    );
    expect(uploadType, 'multipart/form-data');
    expect(uploadLength, uploaded.length);
    expect(res['received'], uploaded.length);
    expect(progress.last, uploaded.length);
    // The file bytes are inside the body unchanged.
    final s = String.fromCharCodes(uploaded);
    expect(s, contains('name="k"\r\n\r\nv\r\n'));
    expect(s, contains(String.fromCharCodes(data.sublist(0, 1000))));
  });

  test('downloadToFile writes the file, no .part left', () async {
    final path = '${dir.path}/out/d.bin';
    int? total;
    await api.downloadToFile('/d', path, onProgress: (_, t) => total = t);
    expect(await File(path).readAsBytes(), data);
    expect(File('$path.part').existsSync(), isFalse);
    expect(total, data.length);
  });

  test('cancel keeps .part; resume continues with Range/206', () async {
    final path = '${dir.path}/d.bin';
    final token = OmniCancelToken();
    await expectLater(
      api.downloadToFile(
        '/d',
        path,
        cancelToken: token,
        onProgress: (r, _) {
          if (r >= 60000) token.cancel();
        },
      ),
      throwsA(isA<CancelledFailure>()),
    );
    final partial = await File('$path.part').length();
    expect(partial, greaterThan(0));
    expect(File(path).existsSync(), isFalse);

    int? last;
    final res = await api.downloadToFile(
      '/d',
      path,
      resume: true,
      onProgress: (r, t) {
        last = r;
        expect(t, data.length);
      },
    );
    expect(res.statusCode, 206);
    expect(ranges.last, 'bytes=$partial-');
    expect(last, data.length);
    expect(await File(path).readAsBytes(), data);
  });

  test('resume against a server ignoring Range starts over (200)', () async {
    final path = '${dir.path}/d.bin';
    await File('$path.part').writeAsBytes([9, 9, 9]);
    honourRange = false;
    final res = await api.downloadToFile('/d', path, resume: true);
    expect(res.statusCode, 200);
    expect(await File(path).readAsBytes(), data);
  });

  test('without resume an old .part is overwritten, no Range sent', () async {
    final path = '${dir.path}/d.bin';
    await File('$path.part').writeAsBytes([9, 9, 9]);
    await api.downloadToFile('/d', path);
    expect(ranges.single, isNull);
    expect(await File(path).readAsBytes(), data);
  });

  test('supportsFileDownload is true on the VM', () {
    expect(OmniNetwork.supportsFileDownload, isTrue);
  });
}
