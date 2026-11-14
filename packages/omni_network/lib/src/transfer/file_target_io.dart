import 'dart:io';

import 'download_target.dart';

/// Whether files can be written on this platform. Internal.
const bool fileDownloadSupported = true;

/// Writes to `<path>.part`, renamed to [path] on success. Internal.
final class FileTarget implements DownloadTarget {
  /// Creates a target for [path]; [resume] keeps an existing `.part` file.
  FileTarget(this.path, {required this.resume});

  /// Final file path.
  final String path;

  /// Whether to continue a previous partial download.
  final bool resume;

  File get _part => File('$path.part');
  IOSink? _sink;

  @override
  Future<int> existingLength() async =>
      resume && await _part.exists() ? await _part.length() : 0;

  @override
  Future<void> begin({required bool append}) async {
    await _part.parent.create(recursive: true);
    _sink = _part.openWrite(mode: append ? FileMode.append : FileMode.write);
  }

  @override
  Future<void> add(List<int> chunk) async => _sink!.add(chunk);

  @override
  Future<void> commit() async {
    await _sink?.close();
    _sink = null;
    await _part.rename(path);
  }

  @override
  Future<void> abort() async {
    // Keep the .part file so a later `resume: true` can continue.
    await _sink?.close();
    _sink = null;
  }
}
