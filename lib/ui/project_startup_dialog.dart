import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shad/shad.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../process/project_ready_view.dart';
import '../theme/app_theme.dart';
import '../util/open_url.dart';
import '../util/prompt_generator.dart';
import '../widgets/app_dialog.dart';
import '../widgets/dialog_body.dart';

/// Set once the user ticks "Don't show this again".
const _kDismissedKey = 'project.startup_notice_dismissed';

/// Explains the first-start wait, unless the user has turned the notice off.
///
/// Opening a project auto-starts the server, and that compiles the whole stack
/// before anything reaches the preview pane. Without this, the first minute or
/// two looks like the app has hung.
///
/// The preference is only written when the box is ticked, so dismissing the
/// dialog normally leaves it showing next time.
Future<void> maybeShowProjectStartupNotice(
  BuildContext context, {
  required ProjectReadyView process,
}) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_kDismissedKey) ?? false) return;
  if (!context.mounted) return;

  final dismissForever = await showAppDialog<bool>(
    context: context,
    // The button is the only way out, so a stray click on the barrier cannot
    // throw away a ticked "don't show this again".
    barrierDismissible: false,
    builder: (context) => ProjectStartupDialog(process: process),
  );

  if (dismissForever ?? false) {
    await prefs.setBool(_kDismissedKey, true);
  }
}

/// Sets expectations for the first build after a project is opened.
///
/// Pops `true` when the user asked not to see it again; persisting that is the
/// caller's job, which keeps this widget free of `dart:io` and easy to show in
/// Widgetbook.
class ProjectStartupDialog extends StatefulWidget {
  const ProjectStartupDialog({
    super.key,
    required this.process,
    this.openLink = openUrl,
  });

  final ProjectReadyView process;

  /// Opens the Prompt Generator in the user's browser. Injectable so a test
  /// can press the button without a browser opening.
  final Future<void> Function(Uri url) openLink;

  @override
  State<ProjectStartupDialog> createState() => _ProjectStartupDialogState();
}

class _ProjectStartupDialogState extends State<ProjectStartupDialog> {
  bool _dontShowAgain = false;

  @override
  void initState() {
    super.initState();
    widget.process.addListener(_onProcessChanged);
  }

  @override
  void dispose() {
    widget.process.removeListener(_onProcessChanged);
    super.dispose();
  }

  /// Closes on its own once the project is up — this notice is about the wait,
  /// and the wait is over. The "your project has started" notice takes it from
  /// here; the caller shows that one after this future completes, so the two
  /// cannot end up stacked.
  void _onProcessChanged() {
    if (!widget.process.projectIsReady) return;
    if (!mounted) return;
    // Only while this route is still the top one. Popping a route that has
    // already been removed takes `home` with it and empties the navigator.
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
    Navigator.of(context).pop(_dontShowAgain);
  }

  @override
  Widget build(BuildContext context) {
    // The alert variant, not the primary one: its theme carries no
    // `closeIconData`, so there is no X in the corner — which is right for a
    // notice you acknowledge rather than dismiss. The copy goes in
    // `description` so it picks up shad's body role (`style.body` over
    // `textTheme.muted`) instead of a label style.
    return ShadDialog.alert(
      title: const Text('Starting your project'),
      description: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Text(
            'App Studio is building your server and app and starting them '
            'up. The first run takes a minute or two.',
          ),
          Text(
            'While you wait, write down what you want to build. The Prompt '
            'Generator turns it into a prompt for your AI editor.',
          ),
        ],
      ),
      // The row defaults to `min`/`end`, which would park the checkbox next to
      // the button; `max` is what lets `spaceBetween` push them apart.
      actionsMainAxisSize: MainAxisSize.max,
      actionsMainAxisAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        // Flexible, as in the started notice: with two buttons beside it the
        // row can run out of room, and the checkbox is the part that can wrap.
        Flexible(
          child: ShadCheckbox(
            value: _dontShowAgain,
            onChanged: (v) => setState(() => _dontShowAgain = v),
            label: Text("Don't show this again", style: kWeightMedium),
          ),
        ),
        // The two buttons travel together: three children under
        // `spaceBetween` would strand the first one mid-row.
        Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            // Opens the browser and leaves the notice up: the wait it describes
            // is not over, and it still closes itself when the project starts.
            ShadButton.outline(
              onPressed: () => unawaited(widget.openLink(kPromptGeneratorUrl)),
              trailing: const Icon(LucideIcons.arrowUpRight, size: 16),
              child: const Text('Prompt Generator'),
            ),
            ShadButton(
              onPressed: () => Navigator.of(context).pop(_dontShowAgain),
              child: const Text('Dismiss'),
            ),
          ],
        ),
      ],
      child: const DialogBody(),
    );
  }
}
