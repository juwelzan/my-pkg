/// No isolates here (e.g. the Web): runs [f] inline. Internal.
Future<T> runOffThread<T>(T Function() f) => Future.sync(f);
