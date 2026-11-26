import 'dart:math' as math;

/// An ANSI escape sequence: colour, cursor movement.
final ansiEscapePattern = RegExp(r'\x1B\[[0-9;]*[A-Za-z]');

/// A line that reports an error the way compilers, `git` and the Dart and
/// Serverpod tools do: `Error:`, `error:`, `ERROR:`, `fatal:`.
final _errorLine = RegExp(r'\b(?:error|fatal)\b:', caseSensitive: false);

/// A command's [output] as the lines a terminal would have shown: colour
/// codes dropped, and a line the command redrew with `\r` (a progress step,
/// a download counter) kept as it was last drawn rather than once per frame.
/// Trailing whitespace is trimmed, runs of blank lines fold into one, and
/// blank lines at either end are dropped.
List<String> commandOutputLines(String output) {
  final plain = output
      .replaceAll(ansiEscapePattern, '')
      .replaceAll('\r\n', '\n');
  final lines = <String>[];
  for (final raw in plain.split('\n')) {
    final drawn = raw.split('\r').lastWhere(
          (segment) => segment.trim().isNotEmpty,
          orElse: () => '',
        );
    final line = drawn.trimRight();
    if (line.isEmpty && (lines.isEmpty || lines.last.isEmpty)) continue;
    lines.add(line);
  }
  while (lines.isNotEmpty && lines.last.isEmpty) {
    lines.removeLast();
  }
  return lines;
}

/// The part of a failed command's [lines] worth showing under its message.
///
/// The first error line and everything after it, with [context] lines before
/// it: a compiler or `git` names the real problem first, and the lines after
/// it are consequences — so the last few lines, which is what a tail shows,
/// are usually "Failed to build" and nothing more. With no error line, the
/// last [tailLines].
///
/// It is for display only. Keep the whole output beside it for copying.
String failureExcerpt(
  List<String> lines, {
  int tailLines = 20,
  int context = 2,
}) {
  final first = lines.indexWhere(_errorLine.hasMatch);
  final start = first < 0
      ? math.max(0, lines.length - tailLines)
      : math.max(0, first - context);
  return lines.sublist(start).join('\n');
}
