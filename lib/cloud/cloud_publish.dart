import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:xterm/xterm.dart';
import 'package:yaml/yaml.dart';

import '../process/dev_session_cleanup.dart';
import '../process/tool_command.dart';
import '../runner/runner_discovery.dart';
import '../session/project_session.dart';
import '../toolchain/tool_status.dart';
import '../toolchain/toolchain_controller.dart';
import 'pty_process.dart';

/// What Publish to Cloud runs: `serverpod cloud launch`, in the server
/// package.
///
/// One command for both cases. Given a project with no `scloud.yaml` it walks
/// the user through creating a Serverpod Cloud project and deploys it; given
/// one, it redeploys. It is the CLI's own entry point, through the `serverpod`
/// CLI rather than `scloud` directly: that installs `scloud` when it is
/// missing and reruns it after a self-update (exit codes 69 and 75), which
/// App Studio would otherwise have to reproduce.
///
/// No `--project-dir`: the working directory is the server package, which is
/// where `launch` looks first and where it keeps `scloud.yaml`. A path argument
/// is also the one thing a Windows batch launcher could refuse.
const kCloudLaunchArguments = ['cloud', 'launch'];

/// How the command is shown above its output, as a terminal would echo it.
const kCloudLaunchDisplayCommand = 'serverpod cloud launch';

/// Where a publish run stands.
enum CloudPublishPhase {
  /// The CLI is running — or being looked up and started.
  running,

  /// Cancel was confirmed; waiting for the CLI to go.
  cancelling,

  /// The CLI exited 0. `launch` waits for the rollout by default (`--await`),
  /// so the project is deployed, not just uploaded.
  succeeded,

  /// The CLI exited non-zero, or could not be started at all.
  failed,

  /// The user cancelled it.
  cancelled;

  bool get isActive => this == running || this == cancelling;
}

/// Why a publish could not even start — no server package, no Serverpod CLI.
/// The message is shown as is.
class CloudPublishUnavailable implements Exception {
  const CloudPublishUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The program a run starts, resolved when the run starts.
class CloudPublishCommand {
  const CloudPublishCommand({
    required this.executable,
    required this.arguments,
    required this.serverDirectory,
    required this.environment,
  });

  final String executable;
  final List<String> arguments;

  /// The server package: the working directory, and where `scloud.yaml` is.
  final String serverDirectory;

  final Map<String, String> environment;
}

/// A deployed project's addresses on Serverpod Cloud.
///
/// Built from the project id in `scloud.yaml` rather than read from the
/// output: the file is the CLI's own record of which project this is, while
/// the output's wording is free to change. The host scheme is the one the CLI
/// itself prints (`HostConstants.tenantDomain`).
class CloudProjectLinks {
  const CloudProjectLinks(this.projectId);

  final String projectId;

  static const tenantDomain = 'serverpod.space';

  Uri get web => Uri.https('$projectId.$tenantDomain', '/');
  Uri get api => Uri.https('$projectId.api.$tenantDomain', '/');
  Uri get insights => Uri.https('$projectId.insights.$tenantDomain', '/');
}

/// The file names `scloud` looks for in a server package, in its order.
const _scloudConfigNames = ['scloud.yaml', 'scloud.yml', 'scloud.json'];

/// The Serverpod Cloud project id recorded in [serverDirectory], or null when
/// there is no config, or no id in it.
///
/// `scloud.json` is read by the same parser: YAML is a superset of JSON.
Future<String?> readCloudProjectId(String serverDirectory) async {
  for (final name in _scloudConfigNames) {
    final file = File(p.join(serverDirectory, name));
    if (!await file.exists()) continue;
    try {
      final doc = loadYaml(await file.readAsString());
      if (doc is! Map) return null;
      final project = doc['project'];
      if (project is! Map) return null;
      final id = project['projectId'];
      return id is String && id.isNotEmpty ? id : null;
    } on Exception {
      return null;
    }
  }
  return null;
}

/// One publish, as the dialog sees it. [CloudPublishRun] is the real one;
/// Widgetbook and the tests draw the dialog from fakes.
abstract interface class CloudPublishView implements Listenable {
  CloudPublishPhase get phase;

  /// What the CLI prints, and where the user types. Replaced by [retry].
  Terminal get terminal;

  /// The CLI's exit code, once it has exited. Null when it never started.
  int? get exitCode;

  /// Why the run failed *outside* the CLI — it could not be found or started.
  /// When the CLI itself fails, the reason is in [terminal] and this is null.
  String? get failureMessage;

  /// Where the project lives, after a success that recorded a project id.
  CloudProjectLinks? get links;

  /// Starts again after a failure or a cancel.
  void retry();

  /// Asks the CLI to stop, ends it if it does not, and completes once it is
  /// gone. The dialog confirms with the user first.
  Future<void> cancel();
}

/// What the toolbar's Publish to Cloud button needs: a way to start one.
abstract interface class CloudPublisher {
  /// Starts a publish, or returns the one already running.
  CloudPublishView start();
}

/// A run of [kCloudLaunchArguments] in a pseudo-terminal.
///
/// **The exit code is the whole contract.** Nothing here reads the output:
/// the CLI's prompts, wording and layout can all change without this noticing.
/// A PTY rather than pipes because `launch` is interactive-only — it refuses
/// to run without a terminal, and its prompts read single keys in raw mode.
class CloudPublishRun extends ChangeNotifier implements CloudPublishView {
  CloudPublishRun({
    required this._resolveCommand,
    required this._startPty,
    this.interruptGrace = const Duration(seconds: 3),
    this.displayCommand = kCloudLaunchDisplayCommand,
  });

  final Future<CloudPublishCommand> Function() _resolveCommand;
  final PtyStarter _startPty;

  /// How long a cancelled CLI gets to act on Ctrl-C before it is ended.
  final Duration interruptGrace;

  final String displayCommand;

  CloudPublishPhase _phase = CloudPublishPhase.running;
  Terminal _terminal = _newTerminal();
  int? _exitCode;
  String? _failureMessage;
  CloudProjectLinks? _links;

  PtyProcess? _pty;
  StreamSubscription<Uint8List>? _output;
  Timer? _killTimer;

  /// Set by [cancel] and [stop]. Read when the CLI exits: whatever its code,
  /// a run the user stopped reads as cancelled.
  bool _stopRequested = false;

  /// Bumped by every start, so a superseded start that is still awaiting
  /// cannot publish its process into a newer run.
  int _generation = 0;
  Completer<void> _finished = Completer<void>();
  bool _disposed = false;

  @override
  CloudPublishPhase get phase => _phase;

  @override
  Terminal get terminal => _terminal;

  @override
  int? get exitCode => _exitCode;

  @override
  String? get failureMessage => _failureMessage;

  @override
  CloudProjectLinks? get links => _links;

  /// Completes when the current attempt has ended, however it ended.
  Future<void> get finished => _finished.future;

  static Terminal _newTerminal() => Terminal(maxLines: 10000);

  /// Starts the first attempt. Separate from the constructor so the dialog
  /// can lay the terminal out first, and the CLI starts at its real size.
  void start() => unawaited(_run());

  @override
  void retry() {
    if (_phase.isActive || _disposed) return;
    _terminal = _newTerminal();
    _phase = CloudPublishPhase.running;
    _exitCode = null;
    _failureMessage = null;
    _links = null;
    notifyListeners();
    unawaited(_run());
  }

  Future<void> _run() async {
    final generation = ++_generation;
    _stopRequested = false;
    if (_finished.isCompleted) _finished = Completer<void>();
    final terminal = _terminal;

    terminal.write('\x1b[2m\$ $displayCommand\x1b[0m\r\n');

    PtyProcess? pty;
    try {
      final command = await _resolveCommand();
      if (_superseded(generation)) return;
      if (_stopRequested) {
        _end(CloudPublishPhase.cancelled);
        return;
      }

      pty = await _startPty(
        executable: command.executable,
        arguments: command.arguments,
        workingDirectory: command.serverDirectory,
        environment: command.environment,
        columns: terminal.viewWidth,
        rows: terminal.viewHeight,
      );
      if (_superseded(generation)) {
        pty.kill();
        unawaited(pty.close());
        return;
      }
      _pty = pty;
      if (_stopRequested) pty.kill();
      await registerDevSessionPid(DevProcessKind.cloudPublish, pty.pid);

      // Chunked, so a multi-byte character split across two reads still
      // decodes.
      final decoded = const Utf8Decoder(
        allowMalformed: true,
      ).startChunkedConversion(_TerminalSink(terminal));
      _output = pty.output.listen(decoded.add);
      terminal.onOutput = (data) => _pty?.write(utf8.encode(data));
      terminal.onResize = (width, height, _, _) =>
          _pty?.resize(columns: width, rows: height);

      final code = await pty.done;
      decoded.close();
      _exitCode = code;
      await _release(pty);
      if (_superseded(generation)) return;

      if (_stopRequested) {
        _end(CloudPublishPhase.cancelled);
      } else if (code == 0) {
        final id = await readCloudProjectId(command.serverDirectory);
        _links = id == null ? null : CloudProjectLinks(id);
        _end(CloudPublishPhase.succeeded);
      } else {
        _end(CloudPublishPhase.failed);
      }
    } on CloudPublishUnavailable catch (e) {
      if (pty != null) await _release(pty);
      if (_superseded(generation)) return;
      _failureMessage = e.message;
      _end(CloudPublishPhase.failed);
    } catch (e) {
      // A PTY that would not start, a directory that went away. Not the
      // CLI's failure, so there is nothing of it in the terminal to read.
      if (pty != null) await _release(pty);
      if (_superseded(generation)) return;
      _failureMessage = 'Could not start $displayCommand: $e';
      _end(CloudPublishPhase.failed);
    }
  }

  bool _superseded(int generation) => _disposed || generation != _generation;

  Future<void> _release(PtyProcess pty) async {
    _killTimer?.cancel();
    _killTimer = null;
    await _output?.cancel();
    _output = null;
    _terminal.onOutput = null;
    _terminal.onResize = null;
    if (identical(_pty, pty)) _pty = null;
    await clearDevSessionPid(DevProcessKind.cloudPublish);
    await pty.close();
  }

  void _end(CloudPublishPhase phase) {
    _phase = phase;
    if (!_finished.isCompleted) _finished.complete();
    notifyListeners();
  }

  @override
  Future<void> cancel() {
    if (!_phase.isActive) return Future.value();
    if (_phase == CloudPublishPhase.running) {
      _stopRequested = true;
      _phase = CloudPublishPhase.cancelling;
      notifyListeners();
      final pty = _pty;
      if (pty != null) {
        pty.interrupt();
        _killTimer = Timer(interruptGrace, pty.kill);
      }
    }
    return finished;
  }

  /// Ends the run at once, for a quit, an update or a project switch: no
  /// Ctrl-C and no grace, since nobody is left to watch it wind down.
  Future<void> stop() {
    if (!_phase.isActive) return Future.value();
    _stopRequested = true;
    _pty?.kill();
    return finished;
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _killTimer?.cancel();
    final pty = _pty;
    if (pty != null) {
      pty.kill();
      unawaited(_release(pty));
    }
    if (!_finished.isCompleted) _finished.complete();
    super.dispose();
  }
}

class _TerminalSink implements Sink<String> {
  _TerminalSink(this._terminal);

  final Terminal _terminal;

  @override
  void add(String data) => _terminal.write(data);

  @override
  void close() {}
}

/// Owns the publish runs for the open project.
///
/// There is at most one: [start] hands back the run in flight rather than a
/// second CLI working on the same `scloud.yaml`. A project switch or close
/// stops it, and so does `teardownSession` — the CLI is our child, and a quit
/// must not leave it deploying with nobody watching.
class CloudPublishController implements CloudPublisher {
  CloudPublishController({
    required this.toolchains,
    required this.session,
    this._startPty = startFlutterPty,
  }) {
    _projectPath = session.projectPath;
    session.addListener(_onSessionChanged);
  }

  final ToolchainController toolchains;
  final ProjectSession session;
  final PtyStarter _startPty;

  CloudPublishRun? _current;
  String? _projectPath;

  @override
  CloudPublishView start() {
    final current = _current;
    if (current != null && current.phase.isActive) return current;
    current?.dispose();
    final run = CloudPublishRun(
      resolveCommand: _resolveCommand,
      startPty: _startPty,
    );
    _current = run;
    // The terminal has not been laid out yet, so the CLI starts at 80×24 and
    // is resized (SIGWINCH) on the dialog's first frame — before the slowest
    // part of resolving it, the server package search, is even done.
    run.start();
    return run;
  }

  /// Ends a run in flight. Awaited by `teardownSession`.
  Future<void> stop() async => _current?.stop();

  Future<CloudPublishCommand> _resolveCommand() async {
    final root = session.projectPath;
    if (root == null) {
      throw const CloudPublishUnavailable('Open a project first.');
    }

    final String? serverDir;
    try {
      serverDir = await findServerDirectory(root);
    } on RunnerDiscoveryException catch (e) {
      throw CloudPublishUnavailable(e.message);
    }
    if (serverDir == null) {
      throw CloudPublishUnavailable(
        'No Serverpod server package was found in $root.',
      );
    }

    // Read now, not captured: the user may have installed the CLI since.
    final toolchain = toolchains.current;
    final serverpod = toolchain.serverpodExecutable;
    if (serverpod == null) {
      throw CloudPublishUnavailable(
        toolchain.unavailableReason(ToolId.serverpodCli) ??
            'The Serverpod CLI is not installed.',
      );
    }
    final command = resolveToolCommand(serverpod, kCloudLaunchArguments);
    return CloudPublishCommand(
      executable: command.executable,
      arguments: command.arguments,
      serverDirectory: serverDir,
      environment: toolchain.processEnvironment(),
    );
  }

  void _onSessionChanged() {
    final path = session.projectPath;
    if (path == _projectPath) return;
    _projectPath = path;
    unawaited(stop());
  }

  void dispose() {
    session.removeListener(_onSessionChanged);
    _current?.dispose();
    _current = null;
  }
}
