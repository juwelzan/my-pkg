import 'dart:io';

/// Whether the console shows ANSI colours: true in a desktop terminal,
/// false for app logs on a phone or simulator (they would show as
/// `\^[[38;5;12m`). Internal.
bool consoleSupportsColors() {
  try {
    return stdout.hasTerminal && stdout.supportsAnsiEscapes;
  } catch (_) {
    return false;
  }
}
