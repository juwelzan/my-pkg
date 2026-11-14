import 'dart:async';
import 'dart:typed_data';

/// Where a download's body goes. Internal.
abstract interface class DownloadTarget {
  /// Bytes already present (for `Range` resume); 0 when not resuming.
  Future<int> existingLength();

  /// Called once headers arrive with a 2xx status. [append] is true for a
  /// `206 Partial Content` reply to a resume request.
  Future<void> begin({required bool append});

  /// Writes one chunk.
  Future<void> add(List<int> chunk);

  /// Finishes successfully.
  Future<void> commit();

  /// Abandons the download (error, cancel, timeout).
  Future<void> abort();
}

/// Collects the body in memory. Internal.
final class BytesTarget implements DownloadTarget {
  final BytesBuilder _b = BytesBuilder(copy: false);

  /// The collected bytes (after [commit]).
  Uint8List bytes = Uint8List(0);

  @override
  Future<int> existingLength() async => 0;
  @override
  Future<void> begin({required bool append}) async {}
  @override
  Future<void> add(List<int> chunk) async => _b.add(chunk);
  @override
  Future<void> commit() async => bytes = _b.takeBytes();
  @override
  Future<void> abort() async => _b.clear();
}
