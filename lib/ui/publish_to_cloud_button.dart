import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shad/shad.dart';

import '../cloud/cloud_publish.dart';
import '../theme/app_theme.dart';
import '../util/open_url.dart';
import '../widgets/app_dialog.dart';
import '../widgets/dialog_body.dart';
import 'terminal/interactive_terminal_view.dart';

/// Toolbar button for publishing the open project to Serverpod Cloud.
///
/// Runs `serverpod cloud launch` in [PublishToCloudDialog]. Outline with a
/// label, at the same height as the icon buttons beside it so the toolbar's
/// right-hand cluster sits on one line.
class PublishToCloudButton extends StatelessWidget {
  const PublishToCloudButton({
    super.key,
    required this.publisher,
    this.compact = false,
  });

  final CloudPublisher publisher;

  /// Icon only, with the label in a tooltip — for a narrow window.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    void open() => unawaited(showPublishToCloudDialog(context, publisher));
    if (compact) {
      return ShadTooltip(
        builder: (context) => const Text('Publish to Cloud'),
        child: ShadIconButton.outline(
          semanticLabel: 'Publish to Cloud',
          width: kToolbarIconButtonSize,
          height: kToolbarIconButtonSize,
          onPressed: open,
          icon: const Icon(LucideIcons.cloudUpload, size: 16),
        ),
      );
    }
    return ShadButton.outline(
      height: kToolbarIconButtonSize,
      size: ShadButtonSize.sm,
      onPressed: open,
      leading: const Icon(LucideIcons.cloudUpload, size: 16),
      child: const Text('Publish to Cloud'),
    );
  }
}

/// Starts a publish and raises [PublishToCloudDialog] over it.
///
/// Not dismissible from the barrier: a stray click must not throw away a
/// deploy half done, and once it is done the dialog has its own buttons.
Future<void> showPublishToCloudDialog(
  BuildContext context,
  CloudPublisher publisher,
) {
  final run = publisher.start();
  return showAppDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => PublishToCloudDialog(run: run),
  );
}

/// The dialog's width. Wide enough that the terminal fits 80 columns of the
/// mono font with room to spare: the CLI lays its prompts out for that.
const _kDialogConstraints = BoxConstraints(maxWidth: 760);

/// The terminal's height — about 24 lines.
const _kTerminalHeight = 380.0;

/// `serverpod cloud launch`, running in a terminal the user answers, then a
/// "Done" panel or the error.
///
/// - **Running:** the live terminal and a Cancel button, which asks first.
///   Escape goes to the CLI while the terminal has focus; anything that would
///   pop the dialog instead asks to cancel ([PopScope]).
/// - **Succeeded:** the terminal is hidden for the project's addresses.
/// - **Failed or cancelled:** the terminal stays, under a banner — the CLI's
///   own error is in it, and nothing here tries to pick it out of the text.
///   Try again starts a fresh run.
class PublishToCloudDialog extends StatefulWidget {
  const PublishToCloudDialog({super.key, required this.run});

  final CloudPublishView run;

  @override
  State<PublishToCloudDialog> createState() => _PublishToCloudDialogState();
}

class _PublishToCloudDialogState extends State<PublishToCloudDialog> {
  final _terminalFocus = FocusNode(debugLabel: 'Publish to Cloud terminal');
  bool _confirming = false;

  CloudPublishView get run => widget.run;

  @override
  void dispose() {
    _terminalFocus.dispose();
    super.dispose();
  }

  Future<void> _confirmCancel() async {
    if (_confirming || run.phase != CloudPublishPhase.running) return;
    _confirming = true;
    final stop = await showAppDialog<bool>(
      context: context,
      builder: (context) => const CancelPublishDialog(),
    );
    _confirming = false;
    // It may have finished while the question was up.
    if (stop ?? false) {
      unawaited(run.cancel());
    } else if (mounted) {
      _terminalFocus.requestFocus();
    }
  }

  void _retry() {
    run.retry();
    _terminalFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: run,
      builder: (context, _) {
        final phase = run.phase;
        return PopScope(
          canPop: !phase.isActive,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) unawaited(_confirmCancel());
          },
          child: ShadDialog.alert(
            constraints: _kDialogConstraints,
            title: Text(
              phase == CloudPublishPhase.succeeded
                  ? 'Published to Serverpod Cloud'
                  : 'Publish to Serverpod Cloud',
            ),
            description: _description(phase),
            actions: _actions(context, phase),
            child: DialogBody(
              child: phase == CloudPublishPhase.succeeded
                  ? PublishDonePanel(links: run.links)
                  : _terminalWithBanner(phase),
            ),
          ),
        );
      },
    );
  }

  Widget _description(CloudPublishPhase phase) => switch (phase) {
    CloudPublishPhase.running || CloudPublishPhase.cancelling => _withCommand(
      'This runs ',
      ' for your project. The first time, it sets up a Serverpod Cloud '
          'project; after that, it deploys your latest code. Answer its '
          'questions in the terminal below.',
    ),
    CloudPublishPhase.succeeded => const Text(
      'Your project is deployed and running on Serverpod Cloud.',
    ),
    CloudPublishPhase.failed => const Text('Publishing did not finish.'),
    CloudPublishPhase.cancelled => const Text('Publishing was cancelled.'),
  };

  /// [before], the command in the mono font, then [after] — the way the
  /// command reads in the user's own terminal.
  Widget _withCommand(String before, String after) => Text.rich(
    TextSpan(
      children: [
        TextSpan(text: before),
        TextSpan(
          text: kCloudLaunchDisplayCommand,
          style: TextStyle(fontFamily: kMonoFont),
        ),
        TextSpan(text: after),
      ],
    ),
  );

  Widget _terminalWithBanner(CloudPublishPhase phase) {
    final theme = ShadTheme.of(context);
    final banner = switch (phase) {
      CloudPublishPhase.failed => ShadAlert.destructive(
        icon: const Icon(LucideIcons.circleAlert),
        title: const Text('Publishing failed'),
        description: switch (run.failureMessage) {
          final message? => Text(message),
          null => _withCommand(
            '',
            ' stopped with exit code ${run.exitCode}. The output below '
                'says why.',
          ),
        },
      ),
      CloudPublishPhase.cancelled => ShadAlert(
        icon: const Icon(LucideIcons.circleSlash),
        title: const Text('Publishing cancelled'),
        description: const Text(
          'Anything already set up on Serverpod Cloud stays there. Try '
          'again to pick up where it stopped.',
        ),
      ),
      _ => null,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (banner != null) ...[banner, const SizedBox(height: 12)],
        SizedBox(
          height: _kTerminalHeight,
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.border),
              borderRadius: theme.radii.md,
            ),
            child: ClipRRect(
              borderRadius: theme.radii.md,
              child: InteractiveTerminalView(
                // Keyed on the terminal: Try again brings a new one, and the
                // view must not keep the old one's scroll and selection.
                key: ObjectKey(run.terminal),
                terminal: run.terminal,
                focusNode: _terminalFocus,
                readOnly: !phase.isActive,
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _actions(BuildContext context, CloudPublishPhase phase) {
    void close() => Navigator.of(context).pop();
    return switch (phase) {
      CloudPublishPhase.running => [
        ShadButton.outline(
          onPressed: () => unawaited(_confirmCancel()),
          child: const Text('Cancel'),
        ),
      ],
      CloudPublishPhase.cancelling => [
        ShadButton.outline(
          enabled: false,
          leading: const ShadSpinner(size: 14),
          child: const Text('Stopping…'),
        ),
      ],
      CloudPublishPhase.succeeded => [
        ShadButton(onPressed: close, child: const Text('Done')),
      ],
      CloudPublishPhase.failed || CloudPublishPhase.cancelled => [
        ShadButton.outline(onPressed: close, child: const Text('Close')),
        ShadButton(onPressed: _retry, child: const Text('Try again')),
      ],
    };
  }
}

/// Where the project is now, after a publish that succeeded.
///
/// [links] is null when no `scloud.yaml` with a project id was found after
/// the run. The CLI writes one on every launch, so that is a CLI that changed
/// how it records the project — the deploy still worked, so this still says
/// so, just without addresses.
class PublishDonePanel extends StatelessWidget {
  const PublishDonePanel({super.key, required this.links});

  final CloudProjectLinks? links;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final scheme = theme.colorScheme;
    final links = this.links;

    return ShadCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.circleCheck, size: 20, color: scheme.success),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  links == null ? 'Done' : 'Done — ${links.projectId}',
                  style: theme.textTheme.large,
                ),
                if (links != null) ...[
                  const SizedBox(height: 8),
                  _LinkRow(label: 'Web', url: links.web),
                  _LinkRow(label: 'API', url: links.api),
                  _LinkRow(label: 'Insights', url: links.insights),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.label, required this.url});

  final String label;
  final Uri url;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Row(
      children: [
        SizedBox(width: 72, child: Text(label, style: theme.textTheme.muted)),
        Flexible(
          child: ShadButton.link(
            padding: EdgeInsets.zero,
            height: 28,
            onPressed: () => unawaited(openUrl(url)),
            trailing: const Icon(LucideIcons.arrowUpRight, size: 14),
            child: Text(url.toString(), overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
    );
  }
}

/// Asks before stopping a publish half done.
class CancelPublishDialog extends StatelessWidget {
  const CancelPublishDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return ShadDialog.alert(
      title: const Text('Stop publishing?'),
      description: const Text(
        'The command is stopped where it is. Anything it has already set up '
        'on Serverpod Cloud stays there, and running it again picks up from '
        'that.',
      ),
      actions: [
        ShadButton.outline(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Keep going'),
        ),
        ShadButton.destructive(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Stop'),
        ),
      ],
      child: const DialogBody(),
    );
  }
}
