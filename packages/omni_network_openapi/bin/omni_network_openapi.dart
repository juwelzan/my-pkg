import 'dart:io';

import 'package:omni_network_openapi/omni_network_openapi.dart';

const _usage = '''
Generates OmniNetwork models and endpoints from an OpenAPI 3 spec.

Usage: dart run omni_network_openapi --input <spec.yaml|json> --output <file.dart>
                                    [--name <ApiClass>] [--no-format]
''';

Future<void> main(List<String> args) async {
  String? input;
  String? output;
  String? name;
  var format = true;
  for (var i = 0; i < args.length; i++) {
    String next() => i + 1 < args.length ? args[++i] : '';
    switch (args[i]) {
      case '-i' || '--input':
        input = next();
      case '-o' || '--output':
        output = next();
      case '-n' || '--name':
        name = next();
      case '--no-format':
        format = false;
      case '-h' || '--help':
        stdout.write(_usage);
        return;
      default:
        stderr.writeln('Unknown argument ${args[i]}\n\n$_usage');
        exitCode = 64;
        return;
    }
  }
  if (input == null || input.isEmpty || output == null || output.isEmpty) {
    stderr.write(_usage);
    exitCode = 64;
    return;
  }
  try {
    final spec = parseSpec(await File(input).readAsString());
    final result = generate(
      spec,
      apiName: name,
      source: input.split(Platform.pathSeparator).last,
    );
    await File(output).create(recursive: true);
    await File(output).writeAsString(result.code);
    for (final w in result.warnings) {
      stderr.writeln('warning: $w');
    }
    if (format) {
      // Best effort: keep the raw output if `dart format` is unavailable.
      try {
        await Process.run(Platform.resolvedExecutable, ['format', output]);
      } on ProcessException {
        stderr.writeln('note: dart format not available; output unformatted');
      }
    }
    stdout.writeln('Wrote $output');
  } on FormatException catch (e) {
    stderr.writeln('error: ${e.message}');
    exitCode = 65;
  } on FileSystemException catch (e) {
    stderr.writeln('error: ${e.message} (${e.path})');
    exitCode = 66;
  }
}
