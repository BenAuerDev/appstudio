import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:appstudio/cloud/cloud_publish.dart';
import 'package:appstudio/cloud/pty_process.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:xterm/xterm.dart';

import '../support/fake_runner.dart';

/// A CLI in a PTY, scripted by the test.
class FakePty implements PtyProcess {
  FakePty({this.exitOnInterrupt = true});

  /// Whether Ctrl-C ends it. A CLI that ignores it is ended by [kill].
  final bool exitOnInterrupt;

  final _output = StreamController<Uint8List>();
  final _done = Completer<int>();
  final written = <String>[];
  final sizes = <(int, int)>[];
  int interrupts = 0;
  int kills = 0;
  bool closed = false;

  @override
  int get pid => FakeRunner.fakePid(7);

  @override
  Stream<Uint8List> get output => _output.stream;

  @override
  Future<int> get done => _done.future;

  void print(List<int> bytes) => _output.add(Uint8List.fromList(bytes));

  void exit(int code) {
    if (_done.isCompleted) return;
    unawaited(_output.close());
    _done.complete(code);
  }

  @override
  void write(Uint8List data) => written.add(utf8.decode(data));

  @override
  void resize({required int columns, required int rows}) =>
      sizes.add((columns, rows));

  @override
  void interrupt() {
    interrupts++;
    if (exitOnInterrupt) exit(-2);
  }

  @override
  void kill() {
    kills++;
    exit(-9);
  }

  @override
  Future<void> close() async {
    closed = true;
    exit(-9);
  }
}

void main() {
  late Directory serverDir;

  setUp(() async {
    serverDir = await Directory.systemTemp.createTemp('cloud_publish');
  });

  tearDown(() async {
    if (await serverDir.exists()) await serverDir.delete(recursive: true);
  });

  CloudPublishCommand command() => CloudPublishCommand(
    executable: '/fake/serverpod',
    arguments: kCloudLaunchArguments,
    serverDirectory: serverDir.path,
    environment: const {'PATH': '/fake'},
  );

  /// A run whose CLI is [pty]; [started] completes with the arguments it was
  /// started with.
  (CloudPublishRun, Completer<Map<String, Object>>) runWith(
    FakePty pty, {
    Future<CloudPublishCommand> Function()? resolve,
    Duration interruptGrace = const Duration(milliseconds: 50),
  }) {
    final started = Completer<Map<String, Object>>();
    final run = CloudPublishRun(
      resolveCommand: resolve ?? () async => command(),
      startPty:
          ({
            required executable,
            required arguments,
            required workingDirectory,
            required environment,
            required columns,
            required rows,
          }) async {
            started.complete({
              'executable': executable,
              'arguments': arguments,
              'workingDirectory': workingDirectory,
              'environment': environment,
            });
            return pty;
          },
      interruptGrace: interruptGrace,
    );
    addTearDown(run.dispose);
    return (run, started);
  }

  String screen(CloudPublishRun run) => run.terminal.buffer.getText();

  test('runs `serverpod cloud launch` in the server package', () async {
    final pty = FakePty();
    final (run, started) = runWith(pty);
    run.start();

    final args = await started.future;
    expect(args['executable'], '/fake/serverpod');
    expect(args['arguments'], ['cloud', 'launch']);
    expect(args['workingDirectory'], serverDir.path);
    expect(args['environment'], {'PATH': '/fake'});
    expect(run.phase, CloudPublishPhase.running);
    pty.exit(0);
    await run.finished;
  });

  test(
    'exit 0 succeeds, with links from the project id in scloud.yaml',
    () async {
      await File(
        p.join(serverDir.path, 'scloud.yaml'),
      ).writeAsString('project:\n  projectId: "my-app"\n');
      final pty = FakePty();
      final (run, started) = runWith(pty);
      run.start();
      await started.future;

      pty.exit(0);
      await run.finished;

      expect(run.phase, CloudPublishPhase.succeeded);
      expect(run.exitCode, 0);
      expect(run.links?.projectId, 'my-app');
      expect(run.links?.web.toString(), 'https://my-app.serverpod.space/');
      expect(run.links?.api.toString(), 'https://my-app.api.serverpod.space/');
      expect(pty.closed, isTrue);
    },
  );

  test('exit 0 with no project id still succeeds, without links', () async {
    final pty = FakePty();
    final (run, started) = runWith(pty);
    run.start();
    await started.future;
    pty.exit(0);
    await run.finished;

    expect(run.phase, CloudPublishPhase.succeeded);
    expect(run.links, isNull);
  });

  test('a non-zero exit fails, with the CLI output left on screen', () async {
    final pty = FakePty();
    final (run, started) = runWith(pty);
    run.start();
    await started.future;

    pty.print(utf8.encode('Error: no can do\r\n'));
    await pumpEventQueue();
    pty.exit(1);
    await run.finished;

    expect(run.phase, CloudPublishPhase.failed);
    expect(run.exitCode, 1);
    expect(run.failureMessage, isNull);
    expect(screen(run), contains('Error: no can do'));
  });

  test('a CLI that cannot be found fails before anything is started', () async {
    final pty = FakePty();
    final (run, started) = runWith(
      pty,
      resolve: () async =>
          throw const CloudPublishUnavailable('No Serverpod CLI.'),
    );
    run.start();
    await run.finished;

    expect(started.isCompleted, isFalse);
    expect(run.phase, CloudPublishPhase.failed);
    expect(run.failureMessage, 'No Serverpod CLI.');
    expect(run.exitCode, isNull);
  });

  test('output is decoded across chunk boundaries', () async {
    final pty = FakePty();
    final (run, started) = runWith(pty);
    run.start();
    await started.future;

    final bytes = utf8.encode('✓ Deployed\r\n');
    pty.print(bytes.sublist(0, 1));
    pty.print(bytes.sublist(1));
    await pumpEventQueue();

    expect(screen(run), contains('✓ Deployed'));
    expect(screen(run), isNot(contains('�')));
    pty.exit(0);
    await run.finished;
  });

  test(
    'what the user types reaches the CLI, and a resize reaches the PTY',
    () async {
      final pty = FakePty();
      final (run, started) = runWith(pty);
      run.start();
      await started.future;
      await pumpEventQueue();

      run.terminal.textInput('my-app');
      run.terminal.keyInput(TerminalKey.enter);
      run.terminal.resize(100, 30);

      expect(pty.written.join(), 'my-app\r');
      expect(pty.sizes.last, (100, 30));
      pty.exit(0);
      await run.finished;
    },
  );

  test(
    'cancel interrupts, and reads as cancelled whatever the exit code',
    () async {
      final pty = FakePty();
      final (run, started) = runWith(pty);
      run.start();
      await started.future;
      await pumpEventQueue();

      final cancelled = run.cancel();
      expect(run.phase, CloudPublishPhase.cancelling);
      await cancelled;

      expect(pty.interrupts, 1);
      expect(pty.kills, 0);
      expect(run.phase, CloudPublishPhase.cancelled);
    },
  );

  test('a CLI that ignores Ctrl-C is ended after the grace period', () async {
    final pty = FakePty(exitOnInterrupt: false);
    final (run, started) = runWith(pty);
    run.start();
    await started.future;
    await pumpEventQueue();

    await run.cancel();

    expect(pty.interrupts, 1);
    expect(pty.kills, 1);
    expect(run.phase, CloudPublishPhase.cancelled);
  });

  test('a cancel before the CLI starts never starts it', () async {
    final resolving = Completer<CloudPublishCommand>();
    final pty = FakePty();
    final (run, started) = runWith(pty, resolve: () => resolving.future);
    run.start();

    final cancelled = run.cancel();
    resolving.complete(command());
    await cancelled;

    expect(started.isCompleted, isFalse);
    expect(run.phase, CloudPublishPhase.cancelled);
  });

  test('stop ends the CLI at once, without asking', () async {
    final pty = FakePty(exitOnInterrupt: false);
    final (run, started) = runWith(
      pty,
      interruptGrace: const Duration(hours: 1),
    );
    run.start();
    await started.future;
    await pumpEventQueue();

    await run.stop();

    expect(pty.interrupts, 0);
    expect(pty.kills, 1);
    expect(run.phase, CloudPublishPhase.cancelled);
  });

  test('retry starts again on a fresh terminal', () async {
    var attempt = 0;
    final ptys = [FakePty(), FakePty()];
    final run = CloudPublishRun(
      resolveCommand: () async => command(),
      startPty:
          ({
            required executable,
            required arguments,
            required workingDirectory,
            required environment,
            required columns,
            required rows,
          }) async => ptys[attempt++],
    );
    addTearDown(run.dispose);

    run.start();
    await pumpEventQueue();
    ptys[0].print(utf8.encode('first attempt\r\n'));
    await pumpEventQueue();
    ptys[0].exit(1);
    await run.finished;
    final firstTerminal = run.terminal;

    run.retry();
    expect(run.phase, CloudPublishPhase.running);
    expect(run.exitCode, isNull);
    expect(run.terminal, isNot(same(firstTerminal)));
    expect(screen(run), isNot(contains('first attempt')));

    await pumpEventQueue();
    ptys[1].exit(0);
    await run.finished;
    expect(attempt, 2);
    expect(run.phase, CloudPublishPhase.succeeded);
  });

  group('readCloudProjectId', () {
    test('reads scloud.yaml', () async {
      await File(
        p.join(serverDir.path, 'scloud.yaml'),
      ).writeAsString('project:\n  projectId: abc-def\n');
      expect(await readCloudProjectId(serverDir.path), 'abc-def');
    });

    test('reads scloud.json', () async {
      await File(
        p.join(serverDir.path, 'scloud.json'),
      ).writeAsString('{"project": {"projectId": "from-json"}}');
      expect(await readCloudProjectId(serverDir.path), 'from-json');
    });

    test('is null with no file, no id or a file that does not parse', () async {
      expect(await readCloudProjectId(serverDir.path), isNull);
      final file = File(p.join(serverDir.path, 'scloud.yaml'));
      await file.writeAsString('project: {}\n');
      expect(await readCloudProjectId(serverDir.path), isNull);
      await file.writeAsString('project: [unclosed\n');
      expect(await readCloudProjectId(serverDir.path), isNull);
    });
  });
}
