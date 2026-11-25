import 'package:appstudio/cloud/cloud_publish.dart';
import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

/// A publish in a fixed state, with a sample transcript in its terminal.
///
/// The transcripts are illustrations, not captures: nothing in App Studio
/// reads the CLI's output, so its exact wording does not matter here either.
class FakeCloudPublishRun extends ChangeNotifier implements CloudPublishView {
  FakeCloudPublishRun({
    this.phase = CloudPublishPhase.running,
    this.exitCode,
    this.failureMessage,
    this.links,
    String? transcript,
  }) : terminal = Terminal(maxLines: 1000)
         ..write(transcript ?? _transcriptFor(phase));

  /// Waiting on the CLI's first question.
  FakeCloudPublishRun.running() : this();

  FakeCloudPublishRun.succeeded({String projectId = 'my-app'})
    : this(
        phase: CloudPublishPhase.succeeded,
        exitCode: 0,
        links: CloudProjectLinks(projectId),
      );

  FakeCloudPublishRun.failed()
    : this(phase: CloudPublishPhase.failed, exitCode: 1);

  /// The CLI was never started — here, no Serverpod CLI on the Mac.
  FakeCloudPublishRun.couldNotStart()
    : this(
        phase: CloudPublishPhase.failed,
        failureMessage: 'The Serverpod CLI is not installed.',
        transcript: '\x1b[2m\$ $kCloudLaunchDisplayCommand\x1b[0m\r\n',
      );

  FakeCloudPublishRun.cancelled()
    : this(phase: CloudPublishPhase.cancelled, exitCode: -2);

  @override
  CloudPublishPhase phase;

  @override
  Terminal terminal;

  @override
  int? exitCode;

  @override
  String? failureMessage;

  @override
  CloudProjectLinks? links;

  int retries = 0;
  int cancels = 0;

  @override
  void retry() {
    retries++;
    terminal = Terminal(maxLines: 1000)
      ..write(_transcriptFor(CloudPublishPhase.running));
    phase = CloudPublishPhase.running;
    exitCode = null;
    failureMessage = null;
    notifyListeners();
  }

  @override
  Future<void> cancel() async {
    cancels++;
    phase = CloudPublishPhase.cancelled;
    notifyListeners();
  }

  /// Moves the fake on, as the CLI would.
  void finish(CloudPublishPhase next, {int? code, CloudProjectLinks? links}) {
    phase = next;
    exitCode = code;
    this.links = links;
    notifyListeners();
  }
}

/// Hands out one [FakeCloudPublishRun] — a fresh running one by default.
class FakeCloudPublisher implements CloudPublisher {
  FakeCloudPublisher([this.run]);

  FakeCloudPublishRun? run;
  int starts = 0;

  @override
  CloudPublishView start() {
    starts++;
    return run ??= FakeCloudPublishRun.running();
  }
}

const _dim = '\x1b[2m';
const _bold = '\x1b[1m';
const _green = '\x1b[32m';
const _red = '\x1b[31m';
const _cyan = '\x1b[36m';
const _reset = '\x1b[0m';

String _transcriptFor(CloudPublishPhase phase) {
  final head = StringBuffer()
    ..write('$_dim\$ $kCloudLaunchDisplayCommand$_reset\r\n')
    ..write('Launching new Serverpod Cloud project.\r\n\r\n')
    ..write('$_green✓$_reset Found project directory: .\r\n');
  switch (phase) {
    case CloudPublishPhase.running:
    case CloudPublishPhase.cancelling:
      head.write(
        '$_cyan?$_reset ${_bold}Enter a new project id$_reset '
        '$_dim(my-app)$_reset › ',
      );
    case CloudPublishPhase.cancelled:
      head.write(
        '$_cyan?$_reset ${_bold}Enter a new project id$_reset '
        '$_dim(my-app)$_reset › ^C\r\n',
      );
    case CloudPublishPhase.failed:
      head
        ..write('$_green✓$_reset Project my-app created.\r\n')
        ..write('$_green✓$_reset Wrote scloud.yaml\r\n')
        ..write('  Uploading project files…\r\n')
        ..write('$_red✗ Failed to upload the project.$_reset\r\n')
        ..write(
          '${_red}Error: The connection to Serverpod Cloud timed out.'
          '$_reset\r\n',
        );
    case CloudPublishPhase.succeeded:
      head.write('$_green✓$_reset Deployed my-app.\r\n');
  }
  return head.toString();
}
