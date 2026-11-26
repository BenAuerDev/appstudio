/// Fakes for the views an open project's chrome reads: the start page's
/// recents, the New Project form, and the toolbar's buttons.
library;

import 'dart:async';

import 'package:appstudio/process/full_restart_view.dart';
import 'package:appstudio/process/new_project_view.dart';
import 'package:appstudio/process/project_creator.dart';
import 'package:appstudio/process/project_ready_view.dart';
import 'package:appstudio/session/external_editors_view.dart';
import 'package:appstudio/session/recent_projects_view.dart';
import 'package:appstudio/util/home_dir.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Under the real home directory, so the UI shortens it to `~/…` exactly as
/// it does for a real path.
String homePath(String relative) => p.join(homeDirectory() ?? '/Users/you', relative);

class FakeRecentProjects extends ChangeNotifier implements RecentProjectsView {
  FakeRecentProjects({List<String> recents = const [], this.error})
      : _recents = [...recents];

  List<String> _recents;

  @override
  List<String> get recents => List.unmodifiable(_recents);

  @override
  String? error;

  @override
  Future<void> openProjectPicker() async {}

  @override
  Future<void> openPath(String path) async {}

  @override
  Future<void> clearRecents() async {
    _recents = [];
    notifyListeners();
  }
}

/// What Serverpod CLI 4.1.2 printed when `serverpod create` ran in a folder
/// holding an unrelated project with an invalid `pubspec.yaml`. One
/// `log.error` call — the "Yikes" paragraph, the issue URL, the exception and
/// its stack — word-wrapped at 80 columns with `ERROR: ` on the first line.
///
/// Verbatim, apart from the elided paths: `test/project_creator_test.dart`
/// pins the parsing against it.
const kSampleInternalErrorOutput = '''
ERROR: Yikes! It is possible that this error is caused by an internal issue with
the Serverpod tooling. We would appreciate if you filed an issue over at Github.
Please include the stack trace below and describe any steps you did to trigger
the error.

https://github.com/serverpod/serverpod/issues

Exception: Error while parsing pubspec file: /Users/someone/lab/dart/pubspec.yaml:
Instance of '_WrappedYamlException'
#0      parsePubspec (package:serverpod_cli/src/util/pubspec_helpers.dart:16)
#1      isServerDirectory (package:serverpod_cli/src/util/directory.dart:27)
#2      findServerDirectory.<anonymous closure>
(package:serverpod_cli/src/util/directory.dart:55)
#3      Iterable.firstWhere (dart:core/iterable.dart:768)
#4      findServerDirectory (package:serverpod_cli/src/util/directory.dart:54)
#5      ServerpodCommandRunner.runCommand
(package:serverpod_cli/src/runner/serverpod_command_runner.dart:182)
#6      BetterCommandRunner.run
(package:cli_tools/src/better_command_runner/better_command_runner.dart:401)
<asynchronous suspension>
#7      _main (file:///.../serverpod_cli-4.1.2/bin/serverpod_cli.dart:121)
<asynchronous suspension>
#8      main.<anonymous closure>
(file:///.../serverpod_cli-4.1.2/bin/serverpod_cli.dart:68)
<asynchronous suspension>
#9      runZonedGuarded (dart:async/zone.dart:1902)
#10     _rootRun (dart:async/zone.dart:1525)
#11     main
(file:///.../serverpod_cli-4.1.2/bin/serverpod_cli.dart:63)
<asynchronous suspension>
''';

/// What the CLI prints when it cannot fetch its templates: a plain error,
/// wrapped at 80 columns like everything it logs.
const kSamplePlainErrorOutput = '''
Downloading templates...
ERROR: Could not download the required resources for Serverpod. Make sure that
you are connected to the internet and that you are using the latest version of
Serverpod.
''';

/// How [FakeNewProject.create] ends.
enum CreateOutcome {
  /// Walks through the CLI's status lines, then succeeds.
  succeeds,

  /// Never finishes — the progress view, held.
  hangs,

  /// `serverpod create` fails with an error of its own.
  fails,

  /// `serverpod create` crashes: an internal error, with a stack trace.
  crashes,

  /// The project reached disk but could not be configured for the preview.
  partlyCreated,
}

class FakeNewProject implements NewProjectView {
  FakeNewProject({this.outcome = CreateOutcome.succeeds});

  final CreateOutcome outcome;

  @override
  String get suggestedDirectory => homePath('Projects');

  @override
  Future<String?> pickDirectory(String current) async =>
      homePath('Projects/clients');

  @override
  Future<String> create({
    required String name,
    required String parentDirectory,
    required Set<IdeIntegration> ides,
    void Function(String status)? onStatus,
  }) async {
    final path = p.join(parentDirectory, name);
    switch (outcome) {
      case CreateOutcome.hangs:
        onStatus?.call('Resolving dependencies…');
        return Completer<String>().future;
      case CreateOutcome.fails:
        throw ProjectCreationException.fromCliOutput(
          kSamplePlainErrorOutput,
          exitCode: 1,
        );
      case CreateOutcome.crashes:
        throw ProjectCreationException.fromCliOutput(
          kSampleInternalErrorOutput,
          exitCode: 1,
        );
      case CreateOutcome.partlyCreated:
        throw ProjectCreationException(
          'The project was created, but App Studio could not configure its '
          'preview. It may open in a browser instead of the preview pane.',
          createdPath: path,
        );
      case CreateOutcome.succeeds:
        for (final status in const [
          'Creating project…',
          'Resolving dependencies…',
          'Generating code…',
          'Configuring preview…',
        ]) {
          onStatus?.call(status);
          await Future<void>.delayed(const Duration(milliseconds: 900));
        }
        return path;
    }
  }

  @override
  Future<void> rememberDirectory(String path) async {}

  @override
  void openProject(String path) {}
}

class FakeProjectReady extends ChangeNotifier implements ProjectReadyView {
  FakeProjectReady({this.projectIsReady = false});

  @override
  bool projectIsReady;
}

/// Restarts for two seconds, then is running again.
class FakeFullRestart extends ChangeNotifier implements FullRestartView {
  FakeFullRestart({this.isTransitioning = false, this.isStopped = false});

  @override
  bool isTransitioning;

  @override
  bool isStopped;

  @override
  bool get canRestart => !isTransitioning;

  @override
  Future<void> restart() async {
    isTransitioning = true;
    notifyListeners();
    await Future<void>.delayed(const Duration(seconds: 2));
    isTransitioning = false;
    isStopped = false;
    notifyListeners();
  }
}

class FakeExternalEditors extends ChangeNotifier implements ExternalEditorsView {
  FakeExternalEditors({this.editors = const [], this.canOpen = true});

  @override
  final List<ExternalEditor> editors;

  @override
  final bool canOpen;

  @override
  Future<void> open(ExternalEditor editor) async {}
}

const cursorEditor = ExternalEditor(id: 'cursor', label: 'Cursor');
const claudeEditor = ExternalEditor(id: 'claude', label: 'Claude Code');
const vscodeEditor = ExternalEditor(id: 'vscode', label: 'VS Code');
