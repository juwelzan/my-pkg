import 'dart:io';

import 'package:omni_network_openapi/omni_network_openapi.dart';
import 'package:test/test.dart';

void main() {
  test('petstore.yaml matches the golden file', () {
    final spec = parseSpec(
      File('test/fixtures/petstore.yaml').readAsStringSync(),
    );
    final result = generate(spec, source: 'petstore.yaml');
    expect(result.code, File('test/golden/petstore.g.dart').readAsStringSync());
    expect(result.warnings, [
      'Pet variant: oneOf/anyOf mapped to Object?',
      'postPetsPetIdPhoto: multipart body; use api.upload',
    ]);
  });

  test('JSON input and custom API name', () {
    final spec = parseSpec('''
{"openapi": "3.1.0", "info": {"title": "t", "version": "1"},
 "paths": {"/ping": {"get": {"responses": {"204": {"description": "ok"}}}}},
 "components": {"schemas": {"Maybe": {"type": ["string", "null"]}}}}''');
    final code = generate(spec, apiName: 'Ping').code;
    expect(code, contains('abstract final class Ping {'));
    expect(
      code,
      contains(
        "static final getPing = Endpoint.get<void>('/ping', name: 'getPing');",
      ),
    );
    expect(code, contains('typedef Maybe = String?;'));
  });

  test('rejects Swagger 2 and non-local refs', () {
    expect(() => parseSpec('swagger: "2.0"\ninfo: {}'), throwsFormatException);
    final spec = parseSpec('''
openapi: 3.0.0
info: {title: x, version: "1"}
paths:
  /a:
    get:
      responses:
        "200":
          description: ok
          content:
            application/json:
              schema: {\$ref: "other.yaml#/X"}
''');
    expect(() => generate(spec), throwsFormatException);
  });

  test('CLI writes the file and reports usage errors', () async {
    final dir = await Directory.systemTemp.createTemp('omni_openapi_');
    addTearDown(() => dir.delete(recursive: true));
    final out = '${dir.path}/api.g.dart';
    final ok = await Process.run('dart', [
      'run', 'bin/omni_network_openapi.dart', //
      '-i', 'test/fixtures/petstore.yaml', '-o', out, '--no-format',
    ]);
    expect(ok.exitCode, 0, reason: '${ok.stderr}');
    expect(
      File(out).readAsStringSync(),
      File('test/golden/petstore.g.dart').readAsStringSync(),
    );
    expect('${ok.stderr}', contains('warning: Pet variant'));

    final bad = await Process.run('dart', [
      'run',
      'bin/omni_network_openapi.dart',
    ]);
    expect(bad.exitCode, 64);
    final missing = await Process.run('dart', [
      'run',
      'bin/omni_network_openapi.dart',
      '-i',
      'nope.yaml',
      '-o',
      out,
    ]);
    expect(missing.exitCode, 66);
  });
}
