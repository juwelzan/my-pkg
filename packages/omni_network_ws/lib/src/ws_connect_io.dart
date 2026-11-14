import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// IO: headers (e.g. `Authorization`) are sent on the handshake. Internal.
WebSocketChannel platformConnect(
  Uri uri,
  Iterable<String>? protocols,
  Map<String, String> headers,
) => IOWebSocketChannel.connect(uri, protocols: protocols, headers: headers);

/// Whether handshake headers are supported. Internal.
const bool handshakeHeadersSupported = true;
