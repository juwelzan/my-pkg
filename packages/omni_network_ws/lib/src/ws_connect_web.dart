import 'package:web_socket_channel/web_socket_channel.dart';

/// Web: browsers cannot set handshake headers. Internal.
WebSocketChannel platformConnect(
  Uri uri,
  Iterable<String>? protocols,
  Map<String, String> headers,
) {
  if (headers.isNotEmpty) {
    throw UnsupportedError(
      'Browsers cannot send WebSocket handshake headers; use a protocol '
      'or a short-lived ticket instead',
    );
  }
  return WebSocketChannel.connect(uri, protocols: protocols);
}

/// Whether handshake headers are supported. Internal.
const bool handshakeHeadersSupported = false;
