import 'dart:io';

import 'package:appstudio/toolchain/install_record.dart';
import 'package:appstudio/toolchain/tool_probe.dart';
import 'package:appstudio/toolchain/tool_status.dart';
import 'package:appstudio/toolchain/toolchain.dart';
import 'package:appstudio/toolchain/toolchain_controller.dart';
import 'package:appstudio/toolchain/toolchain_installer.dart';
import 'package:appstudio/toolchain/toolchain_paths.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../widgetbook/fakes/tools.dart';
import '../support/toolchain_support.dart';

/// An installer whose first step fails the way a command does.
class _FailingInstaller extends ToolchainInstaller {
  _FailingInstaller({required super.paths});

  @override
  Future<RecordedInstall> installCommandLineTools({
    required ProgressSink onProgress,
    required CancelToken cancel,
  }) async {
    throw ToolInstallException.fromOutput(
      'Serverpod could not be installed.',
      kSampleDartInstallFailure,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ToolInstallException.fromOutput', () {
    test('shows from the first error, and keeps all of it', () {
      final e = sampleInstallFailure;

      // A tail would have opened on the package list and ended on "Failed to
      // build": the compiler's own error is what says why.
      expect(e.detail!.split('\n').take(2), [
        'Building package executable...',
        'Compiling bin/serverpod_cli.dart...',
      ]);
      expect(e.detail, contains("Error: Can't have modifier 'final' here."));
      expect(e.detail, isNot(contains('+ analyzer')));
      expect(e.output, startsWith('Resolving dependencies...'));
      expect(e.output, endsWith('Failed to build serverpod_cli:serverpod_cli.'));
    });

    test('a command that printed nothing carries no detail', () {
      final e = ToolInstallException.fromOutput('It failed.', '\n  \n');
      expect(e.detail, isNull);
      expect(e.output, isNull);
    });
  });

  group('a failed install step', () {
    late Directory tmp;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tmp = await Directory.systemTemp.createTemp('install_failure');
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('hands its output to the UI with its message', () async {
      final paths = ToolchainPaths.forHome(tmp.path);
      final manifest = await loadTestManifest();
      final spec = manifest[ToolId.commandLineTools]!;
      final controller = ToolchainController(
        initial: Toolchain(
          ToolchainInventory(
            manifest: manifest,
            tools: {
              ToolId.commandLineTools: ToolStatus(
                spec: spec,
                candidates: const [],
                action: ToolAction.install,
              ),
            },
          ),
        ),
        manifest: manifest,
        paths: paths,
        installer: _FailingInstaller(paths: paths),
        probeSandbox: ProbeSandbox.empty,
      );

      await controller.installMissing();

      expect(controller.installError, 'Serverpod could not be installed.');
      expect(controller.installErrorLog, sampleInstallFailure.detail);
      expect(controller.installErrorOutput, sampleInstallFailure.output);
    });
  });
}
