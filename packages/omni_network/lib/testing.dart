/// Test helpers: a programmable fake backend (`OmniMock`) and a raw
/// in-memory transport (`MockTransport`). No sockets, no internet.
library;

export 'src/mock/omni_mock.dart';
export 'src/transport/mock_transport.dart' show MockTransport, MockHandler;
