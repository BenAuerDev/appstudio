import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:appstudio/analytics/app_analytics.dart';
import 'package:appstudio/process/project_creator.dart';
import 'package:appstudio/session/project_settings.dart';

import '../widgetbook/fakes/project.dart';
import 'support/agent_flag.dart';
import 'support/recording_analytics.dart';
import 'support/toolchain_support.dart';

/// Tail of a pubspec written by `serverpod create` (4.0.0-beta.1).
const _serverPubspec = '''
name: testapp_server

serverpod:
  scripts:
    flutter_build:
      posix: |
        cd ../testapp_flutter
        flutter build web --base-href / --output ../testapp_server/web/app

  # Companion Flutter apps that `serverpod start` can launch (Ctrl+R), keyed
  # by a display alias.
  #
  # Admin:
  #   path: ../apps/admin_flutter
  #   device: chrome
  #   web-port: 8090
  flutter_apps:
    testapp:
      path: ../testapp_flutter
      displayName: "Testapp"
      auto_launch: true
      target: lib/driver.dart
''';

void main() {
  group('ProjectCreationException.fromCliOutput', () {
    test('an internal error names the exception, not the boilerplate', () {
      final e = ProjectCreationException.fromCliOutput(
        kSampleInternalErrorOutput,
        exitCode: 1,
      );

      // The exception and its wrapped continuation, joined back up.
      expect(
        e.message,
        'Exception: Error while parsing pubspec file: '
        '/Users/someone/lab/dart/pubspec.yaml: '
        "Instance of '_WrappedYamlException'",
      );
    });

    test('an internal error logs the exception and the top of the stack', () {
      final e = ProjectCreationException.fromCliOutput(
        kSampleInternalErrorOutput,
        exitCode: 1,
      );
      final log = e.log!.split('\n');

      expect(
        log.first,
        'Exception: Error while parsing pubspec file: '
        '/Users/someone/lab/dart/pubspec.yaml:',
      );
      expect(log[2], startsWith('#0      parsePubspec'));
      // The "Yikes" paragraph is in the copy, not in the pane.
      expect(e.log, isNot(contains('Yikes')));
      // And nothing is cut off the end.
      expect(log.last, '<asynchronous suspension>');
    });

    test('the whole output is kept for copying', () {
      final e = ProjectCreationException.fromCliOutput(
        kSampleInternalErrorOutput,
        exitCode: 1,
      );

      expect(e.output, kSampleInternalErrorOutput.trimRight());
    });

    test('a plain error that wraps is shown whole', () {
      // `Are you sure …?` is two lines of its own, the second of which wraps
      // at 80 columns: three lines in all, one message.
      const output = 'ERROR: Are you sure you want to create a project named '
          '"test"?\n'
          'Use the --force flag to force creation, or pick a name that is not '
          'reserved by\n'
          'Serverpod.\n';
      final e = ProjectCreationException.fromCliOutput(output, exitCode: 1);

      expect(
        e.message,
        'Are you sure you want to create a project named "test"? '
        'Use the --force flag to force creation, or pick a name that is not '
        'reserved by Serverpod.',
      );
      expect(e.log, output.trimRight());
    });

    test('a wrapped plain error is one message, the tail its log', () {
      final e = ProjectCreationException.fromCliOutput(
        kSamplePlainErrorOutput,
        exitCode: 1,
      );

      expect(
        e.message,
        'Could not download the required resources for Serverpod. Make sure '
        'that you are connected to the internet and that you are using the '
        'latest version of Serverpod.',
      );
      expect(e.log, startsWith('Downloading templates...'));
    });

    test('a plain error ends at the next blank or level-prefixed line', () {
      const output = 'Downloading templates...\n'
          'ERROR: Failed to download templates.\n'
          'WARNING: Something else went wrong.\n';
      final e = ProjectCreationException.fromCliOutput(output, exitCode: 1);

      expect(e.message, 'Failed to download templates.');
    });

    test('a plain error stays in the log however much follows it', () {
      final output = [
        for (var i = 0; i < 20; i++) 'step $i...',
        'ERROR: Project fine already exists.',
        // An `info` line has no prefix, so only a blank line tells it from
        // the error's own continuation. The CLI exits after an error, so
        // there is rarely anything after it at all.
        '',
        for (var i = 0; i < 20; i++) 'cleanup $i',
      ].join('\n');
      final e = ProjectCreationException.fromCliOutput(output, exitCode: 1);

      expect(e.message, 'Project fine already exists.');
      expect(e.log, startsWith('ERROR: Project fine already exists.'));
    });

    test('progress redraws are kept as last drawn, colours dropped', () {
      const output = '\x1B[33m⠋ Creating project...\r⠙ Creating project...'
          '\r✓ Creating project.\x1B[0m\n'
          '\n\n\n'
          'ERROR: Project fine already exists.\n';
      final e = ProjectCreationException.fromCliOutput(output, exitCode: 1);

      expect(
        e.output,
        '✓ Creating project.\n\nERROR: Project fine already exists.',
      );
    });

    test('output with no error line falls back to the exit code', () {
      final e = ProjectCreationException.fromCliOutput(
        [for (var i = 0; i < 30; i++) 'line $i'].join('\n'),
        exitCode: 64,
      );

      expect(e.message, 'serverpod create failed (exit code 64).');
      expect(e.log!.split('\n'), hasLength(12));
      expect(e.log, endsWith('line 29'));
      expect(e.output!.split('\n'), hasLength(30));
    });

    test('a very long error is cut, and kept whole in the output', () {
      final output = [
        'ERROR: first',
        for (var i = 0; i < 20; i++) 'more $i',
      ].join('\n');
      final e = ProjectCreationException.fromCliOutput(output, exitCode: 1);

      expect(e.message, startsWith('first more 0'));
      expect(e.message, endsWith(' …'));
      expect(e.message, isNot(contains('more 19')));
      expect(e.output, contains('more 19'));
    });

    test('carries the created path through', () {
      final e = ProjectCreationException.fromCliOutput(
        'ERROR: nope',
        exitCode: 1,
        createdPath: '/tmp/fine',
      );
      expect(e.createdPath, '/tmp/fine');
    });
  });

  group('validateProjectName', () {
    test('accepts lowercase names with digits and underscores', () {
      expect(validateProjectName('my_app2'), isNull);
      expect(validateProjectName('a'), isNull);
    });

    test('rejects names that do not start with a letter', () {
      expect(validateProjectName('1app'), contains('letter'));
      expect(validateProjectName('_app'), contains('letter'));
    });

    test('rejects uppercase and special characters', () {
      expect(validateProjectName('MyApp'), isNotNull);
      expect(validateProjectName('my-app'), isNotNull);
    });

    test('says nothing about an empty name', () {
      expect(validateProjectName(''), isNull);
    });
  });

  group('recordProjectSettings', () {
    late Directory project;

    setUp(() {
      project = Directory.systemTemp.createTempSync('appstudio_creator_test');
    });

    tearDown(() {
      if (project.existsSync()) project.deleteSync(recursive: true);
    });

    test(
      'writes down the picks, not the editors that got configured',
      () async {
        final creator = ProjectCreator(
          toolchains: await emptyToolchainController(),
        );
        await creator.recordProjectSettings(
          projectPath: project.path,
          ides: {IdeIntegration.cursor},
        );

        // `configuredIdes` would have added OpenCode here, and every project
        // ever created would carry an Open in OpenCode button because of it.
        final settings = await ProjectSettings.load(project.path);
        expect(settings.editors, {IdeIntegration.cursor});
      },
    );

    test('an unpicked built-in editor leaves nothing behind', () async {
      final creator = ProjectCreator(
        toolchains: await emptyToolchainController(),
      );
      await creator.recordProjectSettings(
        projectPath: project.path,
        ides: const {},
      );

      final settings = await ProjectSettings.load(project.path);
      expect(settings.editors, isEmpty);
    });
  });

  group('applyAgentInstructions', () {
    late Directory project;

    setUp(() {
      project = Directory.systemTemp.createTempSync('appstudio_creator_test');
    });

    tearDown(() {
      if (project.existsSync()) project.deleteSync(recursive: true);
    });

    Future<ProjectCreator> creator() async => ProjectCreator(
      toolchains: await emptyToolchainController(),
      loadAsset: (_) async => 'App Studio agent instructions',
    );

    test('removes CLAUDE.md and writes the template over AGENTS.md', () async {
      File(p.join(project.path, 'CLAUDE.md')).writeAsStringSync('old claude');
      File(p.join(project.path, 'AGENTS.md')).writeAsStringSync('generic');

      await (await creator()).applyAgentInstructions(
        project.path,
        name: 'my_app',
      );

      expect(File(p.join(project.path, 'CLAUDE.md')).existsSync(), isFalse);
      expect(
        File(p.join(project.path, 'AGENTS.md')).readAsStringSync(),
        'App Studio agent instructions',
      );
    });

    test('writes AGENTS.md even when neither file exists yet', () async {
      await (await creator()).applyAgentInstructions(
        project.path,
        name: 'my_app',
      );

      expect(File(p.join(project.path, 'CLAUDE.md')).existsSync(), isFalse);
      expect(
        File(p.join(project.path, 'AGENTS.md')).readAsStringSync(),
        'App Studio agent instructions',
      );
    });

    test('never throws when the asset cannot be read', () async {
      final creator = ProjectCreator(
        toolchains: await emptyToolchainController(),
        loadAsset: (_) async => throw Exception('no bundle'),
      );
      File(p.join(project.path, 'CLAUDE.md')).writeAsStringSync('old claude');

      await creator.applyAgentInstructions(project.path, name: 'my_app');
    });

    test('names the packages after the project', () async {
      final creator = ProjectCreator(
        toolchains: await emptyToolchainController(),
        loadAsset: (_) async =>
            'Run it in `projectname_server`; never edit `projectname_client`.',
      );

      await creator.applyAgentInstructions(project.path, name: 'my_app');

      expect(
        File(p.join(project.path, 'AGENTS.md')).readAsStringSync(),
        'Run it in `my_app_server`; never edit `my_app_client`.',
      );
    });

    // The template once shipped with the packages of the project it was
    // written in, so every new project was told about `v403_client`.
    test('the bundled template names packages only by the placeholder', () {
      final template = File(kAgentsTemplateAsset).readAsStringSync();
      final packages = RegExp(r'`(\w+)_(server|client|flutter)\b')
          .allMatches(template)
          .map((m) => m[1])
          // Serverpod's own packages: `serverpod_client`, `serverpod_flutter`.
          .where((name) => name != 'serverpod')
          .toSet();

      expect(packages, {kAgentsTemplateProjectName});
    });
  });

  group('create analytics', () {
    late Directory parent;

    setUp(() {
      parent = Directory.systemTemp.createTempSync('appstudio_creator_test');
    });

    tearDown(() {
      if (parent.existsSync()) parent.deleteSync(recursive: true);
    });

    test('a rejected name reports a validation failure', () async {
      final transport = installRecordingAnalytics(addTearDown: addTearDown);
      final creator = ProjectCreator(
        toolchains: await emptyToolchainController(),
      );
      await expectLater(
        creator.create(name: 'Bad Name', parentDirectory: parent.path),
        throwsA(isA<ProjectCreationException>()),
      );
      await appAnalytics.flush();

      expect(transport.events, ['app_studio.project_created']);
      final props = transport.propertiesOf(0);
      expect(props['success'], isFalse);
      expect(props['failure_stage'], 'validation');
      expect(props['ides'], isEmpty);
      expect(props['duration_ms'], isA<int>());
    });

    test(
      'a CLI that cannot run reports the cli stage with the picks',
      () async {
        final transport = installRecordingAnalytics(addTearDown: addTearDown);
        // The empty toolchain has no Serverpod CLI, so the run fails before a
        // process is spawned — same stage as a non-zero exit.
        final creator = ProjectCreator(
          toolchains: await emptyToolchainController(),
        );
        await expectLater(
          creator.create(
            name: 'fine',
            parentDirectory: parent.path,
            ides: {IdeIntegration.vscode, IdeIntegration.cursor},
          ),
          throwsA(isA<ProjectCreationException>()),
        );
        await appAnalytics.flush();

        final props = transport.propertiesOf(0);
        expect(props['failure_stage'], 'cli');
        expect(props['ides'], ['cursor', 'vscode']);
      },
    );

    test('nothing is sent while no sink is installed', () async {
      final creator = ProjectCreator(
        toolchains: await emptyToolchainController(),
      );
      await expectLater(
        creator.create(name: 'fine', parentDirectory: parent.path),
        throwsA(isA<ProjectCreationException>()),
      );
      // No throw and no recording: the default sink is the disabled one.
      expect(appAnalytics.enabled, isFalse);
    });
  });

  group('configuredIdes', () {
    test('configures exactly what was picked, and nothing else', () {
      // OpenCode was the only `builtIn`, and it was one because App Studio ran
      // it as its own agent. With no Agent tab there is nothing to force on a
      // project the user did not ask for.
      expect(IdeIntegration.values.where((ide) => ide.builtIn), isEmpty);
      expect(configuredIdes({IdeIntegration.cursor}), {IdeIntegration.cursor});
      expect(configuredIdes({IdeIntegration.opencode}), {
        IdeIntegration.opencode,
      });
    }, skip: skipWhenAgentOn);

    test('adds the built-in editors to whatever was picked', () {
      expect(configuredIdes({IdeIntegration.cursor}), {
        IdeIntegration.opencode,
        IdeIntegration.cursor,
      });
    }, skip: skipWhenAgentOff);

    test('picking nothing still configures the built-in agent', () {
      expect(configuredIdes(const {}), {IdeIntegration.opencode});
    }, skip: skipWhenAgentOff);

    test('picking a built-in editor changes nothing', () {
      expect(configuredIdes({IdeIntegration.opencode}), {
        IdeIntegration.opencode,
      });
    }, skip: skipWhenAgentOff);
  });

  group('patchFlutterAppForPreview', () {
    test('appends the headless web device to the app entry', () {
      final patched = patchFlutterAppForPreview(_serverPubspec)!;
      expect(
        patched,
        endsWith(
          '      target: lib/driver.dart\n'
          '      device: web-server\n',
        ),
      );
      // No port: the runner publishes whichever one Flutter picks.
      expect(patched, isNot(contains('    web-port:')));
      // Commented example values are left alone.
      expect(patched, contains('#   web-port: 8090'));
    });

    test('leaves a port the user pinned alone', () {
      final pinned = _serverPubspec.replaceFirst(
        '      target: lib/driver.dart\n',
        '      target: lib/driver.dart\n      web-port: 7000\n',
      );
      final patched = patchFlutterAppForPreview(pinned)!;
      expect(patched, contains('      web-port: 7000\n'));
      expect(patched, contains('      device: web-server\n'));
    });

    test('replaces values that are already set', () {
      final once = patchFlutterAppForPreview(_serverPubspec)!;
      final twice = patchFlutterAppForPreview(
        once.replaceFirst('device: web-server', 'device: chrome'),
      )!;
      expect(twice, once);
    });

    test('returns null when there is no flutter_apps block', () {
      expect(patchFlutterAppForPreview('name: testapp_server\n'), isNull);
    });
  });
}
