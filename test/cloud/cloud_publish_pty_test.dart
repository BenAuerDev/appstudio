@Tags(['process'])
library;

import 'dart:io';

import 'package:appstudio/cloud/cloud_publish.dart';
import 'package:appstudio/cloud/pty_process.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

/// [CloudPublishRun] against a real pseudo-terminal (`flutter_pty2`), with a
/// shell script standing in for the CLI: a prompt answered through the
/// terminal, the exit code, and a cancel that has to reach a child process.
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('cloud_publish_pty');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  CloudPublishRun scripted(String script) {
    final run = CloudPublishRun(
      resolveCommand: () async => CloudPublishCommand(
        executable: '/bin/sh',
        arguments: ['-c', script],
        serverDirectory: dir.path,
        environment: {'PATH': '/usr/bin:/bin', 'TERM': 'xterm-256color'},
      ),
      startPty: startFlutterPty,
      interruptGrace: const Duration(seconds: 2),
    );
    addTearDown(run.dispose);
    return run;
  }

  Future<void> waitForScreen(CloudPublishRun run, String text) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!run.terminal.buffer.getText().contains(text)) {
      if (DateTime.now().isAfter(deadline)) {
        fail('"$text" never appeared:\n${run.terminal.buffer.getText()}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  test(
    'a prompt is answered through the terminal, and the exit code kept',
    () async {
      final run = scripted(
        'printf "Project id? "; read id; echo "got [\$id]"; exit 3',
      );
      run.start();
      await waitForScreen(run, 'Project id?');

      run.terminal.textInput('my-app');
      run.terminal.keyInput(TerminalKey.enter);
      await run.finished;

      expect(run.terminal.buffer.getText(), contains('got [my-app]'));
      expect(run.exitCode, 3);
      expect(run.phase, CloudPublishPhase.failed);
    },
  );

  test('runs in the server package and succeeds on exit 0', () async {
    final run = scripted('pwd -P; exit 0');
    run.start();
    await run.finished;

    expect(
      run.terminal.buffer.getText(),
      contains(dir.resolveSymbolicLinksSync()),
    );
    expect(run.phase, CloudPublishPhase.succeeded);
  });

  test('cancel stops the program and the child it started', () async {
    final pidFile = File('${dir.path}/child.pid');
    // A child that would outlive its parent if only the parent were signalled.
    final run = scripted(
      'sleep 60 & echo \$! > "${pidFile.path}"; echo ready; wait',
    );
    run.start();
    await waitForScreen(run, 'ready');
    final childPid = int.parse((await pidFile.readAsString()).trim());

    await run.cancel().timeout(const Duration(seconds: 10));

    expect(run.phase, CloudPublishPhase.cancelled);
    // `kill -0` fails once the child is gone.
    final probe = await Process.run('kill', ['-0', '$childPid']);
    expect(probe.exitCode, isNot(0), reason: 'the child survived the cancel');
  });
}
