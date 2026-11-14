import 'dart:io';

/// Whether the terminal shows ANSI colours. Internal.
bool terminalSupportsColors() {
  try {
    return stdout.hasTerminal && stdout.supportsAnsiEscapes;
  } catch (_) {
    return false;
  }
}
