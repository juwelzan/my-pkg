/// OmniNetwork: independent, typed, safe-by-default HTTP networking.
///
/// Pure Dart: no Flutter, router or state-management dependency.
library;

export 'src/core/cancel_signal.dart' show CancelSignal;
export 'src/core/decoding.dart' show JsonDecoder;
export 'src/core/omni_network.dart' show OmniNetwork;
export 'src/core/omni_network_exception.dart';
export 'src/core/omni_request.dart' show OmniRequest, HttpMethod;
export 'src/core/omni_response.dart' show OmniRawResponse, OmniResponse;
export 'src/core/response_adapter.dart';
export 'src/core/result.dart';
export 'src/transport/dio_transport.dart' show DioTransport;
export 'src/transport/mock_transport.dart' show MockTransport, MockHandler;
export 'src/transport/transport.dart' show Transport, TransportRequest;
