import 'dart:io';

/// Whether log lines can carry ANSI colours. Internal.
///
/// * Android: yes. Logcat keeps the codes, and `flutter run` and IDEs show
///   them as colours.
/// * iOS: no. Its log turns the escape character into `\^[` text.
/// * Elsewhere: when stdout is a terminal that supports them.
bool terminalSupportsColors() {
  try {
    if (Platform.isAndroid) return true;
    if (Platform.isIOS) return false;
    return stdout.hasTerminal && stdout.supportsAnsiEscapes;
  } catch (_) {
    return false;
  }
}
