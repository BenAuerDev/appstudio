import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_pty2/flutter_pty2.dart';

import '../platform/host.dart';

/// A program running in a pseudo-terminal, as [CloudPublishRun] drives it.
///
/// Narrow on purpose: it is what the run needs and nothing else, so a test
/// can stand a scripted fake in for the real thing ([FlutterPtyProcess]).
abstract interface class PtyProcess {
  int get pid;

  /// Everything the program writes. A PTY does not separate stdout from
  /// stderr.
  Stream<Uint8List> get output;

  /// The exit code once the program has exited *and* its output has been
  /// delivered, so the last lines are on screen before anyone reacts to it.
  /// Negative for a death by signal, as `Process.exitCode` reports one.
  Future<int> get done;

  void write(Uint8List data);

  void resize({required int columns, required int rows});

  /// Asks the program to stop, as Ctrl-C at a terminal would. On Windows
  /// there are no signals to ask with, so this ends it (see [kill]).
  void interrupt();

  /// Ends the program and everything it started, without asking.
  void kill();

  /// Releases the terminal. Idempotent; ends the program if it is running.
  Future<void> close();
}

/// Starts a program in a pseudo-terminal of [columns]×[rows].
///
/// [environment] *replaces* the parent's: callers pass
/// `Toolchain.processEnvironment()`, which already starts from it.
typedef PtyStarter =
    Future<PtyProcess> Function({
      required String executable,
      required List<String> arguments,
      required String workingDirectory,
      required Map<String, String> environment,
      required int columns,
      required int rows,
    });

/// [PtyStarter] backed by `flutter_pty2`.
///
/// Chosen over `kyroon_pty` (what the old server log used) for Windows: that
/// one builds the ConPTY command line by concatenating bytes — no quoting and
/// no UTF-8 decoding, so a user folder with a space or a non-ASCII letter
/// breaks the path — and never calls `ClosePseudoConsole`, which leaves a
/// `conhost` behind per run. `flutter_pty2` quotes, converts, closes, and runs
/// the child in a Job Object with `KILL_ON_JOB_CLOSE`, so [kill] — and our
/// own death — takes `scloud` down with the `serverpod` that started it.
Future<PtyProcess> startFlutterPty({
  required String executable,
  required List<String> arguments,
  required String workingDirectory,
  required Map<String, String> environment,
  required int columns,
  required int rows,
}) async {
  final session = await Pty.spawn(
    PtySpawnOptions(
      executable: executable,
      arguments: arguments,
      workingDirectory: workingDirectory,
      environment: PtyEnvironment.replace(environment),
      size: PtySize(columns: columns, rows: rows),
    ),
  );
  return FlutterPtyProcess(session);
}

class FlutterPtyProcess implements PtyProcess {
  FlutterPtyProcess(this._session);

  final PtySession _session;

  @override
  int get pid => _session.pid;

  @override
  Stream<Uint8List> get output => _session.output;

  @override
  late final Future<int> done = _session.done.then(
    (exit) => switch (exit) {
      PtyExitCode(:final code) => code,
      PtySignalExit(:final signal) => -signal,
    },
  );

  @override
  void write(Uint8List data) {
    // `tryWrite` rather than awaiting `write`: keystrokes are tiny and the
    // queue holds a megabyte, so backpressure means the program has stopped
    // reading — there is nobody to deliver to, and nothing to wait for.
    try {
      _session.input.tryWrite(data);
    } on PtyException {
      // Closed under us: the program has exited.
    }
  }

  @override
  void resize({required int columns, required int rows}) {
    if (columns <= 0 || rows <= 0) return;
    try {
      _session.resize(PtySize(columns: columns, rows: rows));
    } on PtyException {
      // Exited.
    }
  }

  @override
  void interrupt() {
    if (currentHost.isWindows) {
      kill();
      return;
    }
    try {
      // To the foreground process group, which is `serverpod` *and* the
      // `scloud` it started — a signal rather than a `0x03` byte, because the
      // CLI's prompts put the terminal in raw mode, where Ctrl-C is just a key.
      _session.sendSignal(PosixSignal.int_);
    } on PtyException {
      // Exited.
    }
  }

  @override
  void kill() {
    try {
      _session.kill();
    } on PtyException {
      // Exited.
    }
  }

  @override
  Future<void> close() => _session.close();
}
