import 'dart:isolate';

/// Runs [f] on a short-lived isolate. Internal.
Future<T> runOffThread<T>(T Function() f) => Isolate.run(f);
