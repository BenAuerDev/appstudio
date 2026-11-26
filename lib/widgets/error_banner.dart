import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shad/shad.dart';

import '../theme/app_theme.dart';

/// Destructive-tinted failure box with an optional scrollable log.
///
/// The text is selectable — message and log together, as one selection — and
/// a banner with a log carries a copy button that puts the whole failure on
/// the clipboard, so it can be pasted into an issue.
///
/// Selection is a [SelectionArea], as in the server log: it answers ⌘C and ⌘A
/// while it holds focus and lets every other key through, so the form around
/// it keeps Tab, Enter and the menu bar's shortcuts.
class ErrorBanner extends StatefulWidget {
  const ErrorBanner({
    super.key,
    required this.message,
    this.log,
    this.fullLog,
  });

  final String message;

  /// Command output shown in a capped, scrollable monospace pane.
  final String? log;

  /// Everything the command printed, when [log] is only the part of it that
  /// explains the failure. The copy button takes this over [log].
  final String? fullLog;

  /// The tallest the log pane gets before it scrolls: about ten lines, which
  /// is an exception and the top of its stack, and keeps the banner from
  /// pushing the form below it out of the window.
  static const logMaxHeight = 150.0;

  @override
  State<ErrorBanner> createState() => _ErrorBannerState();
}

class _ErrorBannerState extends State<ErrorBanner> {
  bool _copied = false;

  String? get _copyLog {
    final full = widget.fullLog;
    if (full != null && full.isNotEmpty) return full;
    final log = widget.log;
    return log != null && log.isNotEmpty ? log : null;
  }

  /// The message, then the output in a fence. Markdown, because it is going
  /// into an issue: unfenced, GitHub turns every `#12` frame of a stack trace
  /// into a link to issue 12.
  String get _copyText {
    final log = _copyLog;
    if (log == null) return widget.message;
    return '${widget.message}\n\n```\n$log\n```';
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _copyText));
    if (mounted) setState(() => _copied = true);
  }

  @override
  void didUpdateWidget(ErrorBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message != widget.message ||
        oldWidget.fullLog != widget.fullLog ||
        oldWidget.log != widget.log) {
      _copied = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final scheme = theme.colorScheme;
    final log = widget.log;
    final hasLog = log != null && log.isNotEmpty;

    // `muted`, not `small`: failure messages wrap, and `small` is the label
    // role (`leading-none`), which sets them solid.
    final messageStyle = theme.textTheme.muted.copyWith(
      color: scheme.destructive,
    );
    // The icon sits in a box one text line tall, so it is centred on the first
    // line. Top-aligned on its own, it rode above the text by the line's
    // leading.
    final lineHeight =
        (messageStyle.fontSize ?? 14) * (messageStyle.height ?? 1.2);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: scheme.destructive.withValues(alpha: 0.08),
        borderRadius: theme.radii.md,
        border: Border.all(color: scheme.destructive.withValues(alpha: 0.35)),
      ),
      child: SelectionArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: lineHeight,
                  child: Center(
                    child: Icon(
                      LucideIcons.circleAlert,
                      size: 14,
                      color: scheme.destructive,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(widget.message, style: messageStyle)),
                if (hasLog) ...[
                  const SizedBox(width: 8),
                  // Out of the selection: a drag across the banner should not
                  // pick up the button, and ⌘A should not paint it.
                  SelectionContainer.disabled(
                    child: ShadTooltip(
                      builder: (context) => Text(
                        _copied ? 'Copied' : 'Copy error and output',
                      ),
                      child: ShadIconButton.ghost(
                        semanticLabel: 'Copy error and output',
                        width: lineHeight,
                        height: lineHeight,
                        padding: EdgeInsets.zero,
                        iconSize: 14,
                        icon: Icon(
                          _copied ? LucideIcons.check : LucideIcons.copy,
                        ),
                        onPressed: _copy,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (hasLog) ...[
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: ErrorBanner.logMaxHeight,
                ),
                child: SingleChildScrollView(
                  child: SizedBox(
                    width: double.infinity,
                    child: Text(
                      log,
                      style: theme.textTheme.muted.copyWith(
                        fontFamily: kMonoFont,
                        fontSize: 10.5,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
