import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shad/shad.dart';

import '../process/full_restart_view.dart';
import '../runner/server_status.dart';
import '../theme/app_theme.dart';
import '../widgets/first_that_fits.dart';
import 'server_status_indicator.dart';

/// The toolbar's status, with a way out beside it while the server is down:
/// **View Logs**, which opens the server log, and **Try Again**, a Full
/// Restart.
///
/// A stopped server is almost always a failed one — Full Restart replaced the
/// only control that stopped it on purpose — and the two things a user wants
/// then are why, and another go. Both already existed (Logs → Show Logs, the
/// Full Restart icon), but neither says so next to the red square.
///
/// The buttons fold to icons when the status area is too narrow for their
/// labels, so they fit in the [StudioToolbar.minStatusWidth] the toolbar keeps
/// for the status in every state. The stopped messages are all short, which
/// is what leaves room for them.
class ServerStatusBar extends StatelessWidget {
  const ServerStatusBar({
    super.key,
    required this.status,
    required this.process,
    required this.onViewLogs,
  });

  final ServerStatusView status;
  final FullRestartView process;
  final VoidCallback onViewLogs;

  @override
  Widget build(BuildContext context) {
    final indicator = ServerStatusIndicator(status: status);

    return ListenableBuilder(
      listenable: Listenable.merge([status, process]),
      builder: (context, _) {
        final stopped = status.serverStatus.kind == ServerStatusKind.stopped &&
            !process.isTransitioning;
        final onTryAgain =
            process.canRestart ? () => unawaited(process.restart()) : null;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Always the same slot, so the indicator keeps its state when the
            // actions come and go. Flexible while alone, so a long busy
            // message ellipsizes; sized to itself beside the actions, which
            // take whatever is left — the stopped messages are all short.
            Flexible(flex: stopped ? 0 : 1, child: indicator),
            if (stopped) ...[
              const SizedBox(width: 12),
              Flexible(
                child: FirstThatFits(
                  children: [
                    _RecoveryActions(
                      onViewLogs: onViewLogs,
                      onTryAgain: onTryAgain,
                      compact: false,
                    ),
                    _RecoveryActions(
                      onViewLogs: onViewLogs,
                      onTryAgain: onTryAgain,
                      compact: true,
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _RecoveryActions extends StatelessWidget {
  const _RecoveryActions({
    required this.onViewLogs,
    required this.onTryAgain,
    required this.compact,
  });

  final VoidCallback onViewLogs;
  final VoidCallback? onTryAgain;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _action(
          label: 'View Logs',
          icon: LucideIcons.scrollText,
          primary: false,
          onPressed: onViewLogs,
        ),
        const SizedBox(width: 8),
        _action(
          label: 'Try Again',
          icon: LucideIcons.rotateCcw,
          primary: true,
          onPressed: onTryAgain,
        ),
      ],
    );
  }

  Widget _action({
    required String label,
    required IconData icon,
    required bool primary,
    required VoidCallback? onPressed,
  }) {
    final enabled = onPressed != null;
    if (compact) {
      // Icon-only, so the tooltip carries the name.
      final button = primary
          ? ShadIconButton(
              semanticLabel: label,
              enabled: enabled,
              onPressed: onPressed,
              width: kToolbarIconButtonSize,
              height: kToolbarIconButtonSize,
              icon: Icon(icon, size: 16),
            )
          : ShadIconButton.outline(
              semanticLabel: label,
              enabled: enabled,
              onPressed: onPressed,
              width: kToolbarIconButtonSize,
              height: kToolbarIconButtonSize,
              icon: Icon(icon, size: 16),
            );
      return ShadTooltip(
        builder: (context) => Text(label),
        child: ShadGestureDetector(child: button),
      );
    }
    final text = Text(label);
    return primary
        ? ShadButton(
            size: ShadButtonSize.sm,
            enabled: enabled,
            onPressed: onPressed,
            child: text,
          )
        : ShadButton.outline(
            size: ShadButtonSize.sm,
            enabled: enabled,
            onPressed: onPressed,
            child: text,
          );
  }
}
