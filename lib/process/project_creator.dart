import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import '../analytics/app_analytics.dart';
import '../runner/runner_protocol.dart' show kHeadlessWebDevice;
import '../session/project_settings.dart';
import '../toolchain/tool_status.dart';
import '../toolchain/toolchain_controller.dart';
import '../util/command_output.dart';
import 'ide_integration.dart';
import 'tool_command.dart';

// `IdeIntegration` moved out to keep it clear of `dart:io`, which
// `ProjectSettings` needs it to be. Re-exported so the New Project dialog and
// its tests still reach it through the creator, where it reads naturally.
export 'ide_integration.dart';

/// Agent instructions tuned for App Studio, written into every new project as
/// its `AGENTS.md`.
///
/// It names the project's packages as `projectname_server` and so on — the
/// placeholder Serverpod's own templates use — and [kAgentsTemplateProjectName]
/// is replaced with the project's name when it is written.
const kAgentsTemplateAsset = 'assets/AGENTS_template.md';

/// The placeholder for the project's name in [kAgentsTemplateAsset].
const kAgentsTemplateProjectName = 'projectname';

/// Serverpod project names map to Dart package names (`<name>_server`), so the
/// CLI only accepts lowercase letters, digits and underscores.
final _projectNameFormat = RegExp(r'^[a-z][a-z0-9_]*$');

/// Returns an error message when [name] is not a usable project name.
String? validateProjectName(String name) {
  if (name.isEmpty) return null;
  if (!_projectNameFormat.hasMatch(name)) {
    return name.startsWith(RegExp(r'[0-9_]'))
        ? 'Start the name with a letter.'
        : 'Use lowercase letters, numbers, and underscores only.';
  }
  return null;
}

/// Failure while running `serverpod create` or preparing the project.
class ProjectCreationException implements Exception {
  ProjectCreationException(
    this.message, {
    this.log,
    this.output,
    this.createdPath,
  });

  /// Reads what a failed `serverpod create` printed.
  ///
  /// The CLI logs through `cli_tools`' `StdOutLogger`: with no terminal it
  /// prefixes an error with `ERROR: ` — once, on its first line — and wraps
  /// the whole message at 80 columns, never inside a word. Two shapes reach
  /// us:
  ///
  /// - **A plain error**, `ERROR: Project x already exists.`, possibly
  ///   wrapped over several lines. The [message] is the whole of it, joined
  ///   back into one paragraph; the [log] is the end of the output, which is
  ///   what led up to it.
  /// - **An internal error** — an uncaught exception, which the CLI prints as
  ///   its "Yikes! … please file an issue" paragraph, the issue URL, then the
  ///   exception and its stack trace, all in one `log.error` call. The
  ///   paragraph that matters is the one directly above the first stack
  ///   frame, so that is the [message], and the [log] starts there: the
  ///   exception and the top of the stack, which is where it was thrown. The
  ///   bottom of the stack is `main` and says nothing.
  ///
  /// Either way [output] carries all of it, for a bug report.
  factory ProjectCreationException.fromCliOutput(
    String output, {
    required int exitCode,
    String? createdPath,
  }) {
    final lines = commandOutputLines(output);
    final fallback = 'serverpod create failed (exit code $exitCode).';
    final full = lines.join('\n');

    final errorAt = lines.indexWhere((l) => l.startsWith('ERROR:'));
    if (errorAt < 0) {
      return ProjectCreationException(
        fallback,
        log: _tail(lines, from: lines.length),
        output: full,
        createdPath: createdPath,
      );
    }

    final frameAt = lines.indexWhere(_isStackFrame, errorAt);
    if (frameAt > errorAt) {
      // The exception is the paragraph directly above the stack. It can be
      // the `ERROR:` line itself, for an error logged with a stack trace but
      // no "Yikes" preamble.
      var start = frameAt;
      while (start > errorAt && lines[start - 1].trim().isNotEmpty) {
        start--;
      }
      final paragraph = _paragraph(lines.sublist(start, frameAt));
      if (paragraph.isNotEmpty) {
        return ProjectCreationException(
          paragraph,
          log: lines.sublist(start).join('\n'),
          output: full,
          createdPath: createdPath,
        );
      }
    }

    // A plain error: everything up to the next blank line, the next
    // level-prefixed line, or a stack trace.
    var end = errorAt + 1;
    while (end < lines.length &&
        lines[end].trim().isNotEmpty &&
        !_levelPrefix.hasMatch(lines[end]) &&
        !_isStackFrame(lines[end])) {
      end++;
    }
    final paragraph = _paragraph(lines.sublist(errorAt, end));
    return ProjectCreationException(
      paragraph.isEmpty ? fallback : paragraph,
      log: _tail(lines, from: errorAt),
      output: full,
      createdPath: createdPath,
    );
  }

  final String message;

  /// The part of the CLI output worth showing under [message], when the
  /// failure came from `serverpod create`.
  final String? log;

  /// Everything the CLI printed, for copying into a bug report. [log] is cut
  /// to what explains the failure; this is not.
  final String? output;

  /// Set when the project exists on disk despite the failure — it can still
  /// be opened.
  final String? createdPath;

  @override
  String toString() => message;
}

/// The longest [ProjectCreationException.message] taken from the CLI's
/// output, in lines as it printed them. Past that it is cut with an ellipsis;
/// the whole of it is still in the log, and copied with it.
const _kMaxMessageLines = 8;

/// The fewest lines of output the log shows for a plain error.
const _kLogTailLines = 12;

final _levelPrefix = RegExp(r'^(ERROR|WARNING|DEBUG): ');

final _stackFrame = RegExp(r'^#\d+\s');

bool _isStackFrame(String line) => _stackFrame.hasMatch(line);

/// The last [_kLogTailLines] lines of [lines], reaching back to [from] if
/// that is earlier, so the error is never cut off the top.
String _tail(List<String> lines, {required int from}) {
  final start = math.min(math.max(0, lines.length - _kLogTailLines), from);
  return lines.sublist(start).join('\n');
}

/// [lines] unwrapped into one paragraph, without the level prefix. The CLI
/// wraps at spaces only, so joining with a space puts the text back as it was
/// logged.
String _paragraph(List<String> lines) {
  final cut = lines.length > _kMaxMessageLines;
  final text = lines
      .take(_kMaxMessageLines)
      .map((l) => l.replaceFirst(_levelPrefix, '').trim())
      .where((l) => l.isNotEmpty)
      .join(' ');
  return cut ? '$text …' : text;
}

/// Creates Serverpod projects with the bundled CLI and configures them for the
/// App Studio preview pane.
class ProjectCreator {
  ProjectCreator({
    required this.toolchains,
    Future<String> Function(String key)? loadAsset,
  }) : loadAsset = loadAsset ?? rootBundle.loadString;

  final ToolchainController toolchains;

  /// Reads a bundled asset. Injected (normally `rootBundle.loadString`) so a
  /// test can supply the `AGENTS.md` template without a Flutter asset bundle.
  final Future<String> Function(String key) loadAsset;

  /// Runs `serverpod create` inside [parentDirectory] and returns the path of
  /// the new project. [onStatus] receives CLI progress lines.
  ///
  /// Reports `app_studio.project_created` either way. The stage a failure
  /// came from is the one property worth having there: "the CLI failed" and
  /// "the CLI succeeded and our pubspec patch did not" are different bugs.
  Future<String> create({
    required String name,
    required String parentDirectory,
    Set<IdeIntegration> ides = const {},
    void Function(String status)? onStatus,
  }) async {
    final started = DateTime.now();
    var stage = 'validation';
    void report({required bool success}) => appAnalytics.projectCreated(
      ides: [for (final ide in ides) ide.name]..sort(),
      success: success,
      duration: DateTime.now().difference(started),
      failureStage: success ? null : stage,
    );

    try {
      final path = await _create(
        name: name,
        parentDirectory: parentDirectory,
        ides: ides,
        onStatus: onStatus,
        onStage: (next) => stage = next,
      );
      report(success: true);
      return path;
    } catch (_) {
      report(success: false);
      rethrow;
    }
  }

  Future<String> _create({
    required String name,
    required String parentDirectory,
    required Set<IdeIntegration> ides,
    required void Function(String stage) onStage,
    void Function(String status)? onStatus,
  }) async {
    final nameError = validateProjectName(name);
    if (name.isEmpty || nameError != null) {
      throw ProjectCreationException(nameError ?? 'Enter a project name.');
    }

    final parent = p.normalize(parentDirectory);
    if (!await Directory(parent).exists()) {
      throw ProjectCreationException('Location no longer exists:\n$parent');
    }

    final projectPath = p.join(parent, name);
    if (await Directory(projectPath).exists() ||
        await File(projectPath).exists()) {
      throw ProjectCreationException(
        '“$name” already exists in ${p.basename(parent)}.',
      );
    }

    onStage('cli');
    final log = StringBuffer();
    final code = await _runCreate(
      name: name,
      workingDirectory: parent,
      ides: ides,
      log: log,
      onStatus: onStatus,
    );

    if (code != 0) {
      throw ProjectCreationException.fromCliOutput(
        log.toString(),
        exitCode: code,
        createdPath: await Directory(projectPath).exists() ? projectPath : null,
      );
    }

    onStage('configure_preview');
    onStatus?.call('Configuring preview…');
    await _configureFlutterAppForPreview(projectPath: projectPath, name: name);
    await recordProjectSettings(projectPath: projectPath, ides: ides);
    await applyAgentInstructions(projectPath, name: name);
    return projectPath;
  }

  /// Drops the project's root `CLAUDE.md` and writes an App Studio–tuned
  /// `AGENTS.md` over whatever the CLI left there, with the packages named
  /// after [name].
  ///
  /// `serverpod create` writes a generic `AGENTS.md` (and, for the Claude IDE,
  /// a `CLAUDE.md` that points at it). App Studio's own instructions tell the
  /// agent to drive the server through App Studio rather than the command line,
  /// so the generic pair is replaced with one file.
  ///
  /// Never fails the creation: the project is complete and usable with the
  /// CLI's own instructions, and losing a finished project to an unwritable
  /// dotfile — or a missing asset — would be a far worse trade.
  @visibleForTesting
  Future<void> applyAgentInstructions(
    String projectPath, {
    required String name,
  }) async {
    try {
      final claude = File(p.join(projectPath, 'CLAUDE.md'));
      if (await claude.exists()) await claude.delete();

      final template = await loadAsset(kAgentsTemplateAsset);
      await File(
        p.join(projectPath, 'AGENTS.md'),
      ).writeAsString(template.replaceAll(kAgentsTemplateProjectName, name));
    } catch (_) {
      // Ignored — see above.
    }
  }

  /// Writes `.appstudio/settings.json` so the toolbar knows which editors this
  /// project was set up for.
  ///
  /// Records [ides] as picked, *not* `configuredIdes(ides)`. The built-in
  /// entries go out as `--ide` flags whether or not they were asked for, and
  /// writing them down here would put an Open in OpenCode button on every
  /// project anyone ever created.
  ///
  /// Never fails the creation: the project is complete and usable without it,
  /// and `ProjectSettings.load` falls back to the config files the CLI just
  /// wrote. Losing a finished project to an unwritable dotfile would be a far
  /// worse trade.
  @visibleForTesting
  Future<void> recordProjectSettings({
    required String projectPath,
    required Set<IdeIntegration> ides,
  }) async {
    try {
      await ProjectSettings(editors: ides).save(projectPath);
    } on FileSystemException {
      // Ignored — see above.
    }
  }

  Future<int> _runCreate({
    required String name,
    required String workingDirectory,
    required Set<IdeIntegration> ides,
    required StringBuffer log,
    void Function(String status)? onStatus,
  }) async {
    final toolchain = toolchains.current;
    final serverpod = toolchain.serverpodExecutable;
    if (serverpod == null) {
      throw ProjectCreationException(
        toolchain.unavailableReason(ToolId.serverpodCli) ??
            'Serverpod is not installed.',
      );
    }

    final Process process;
    try {
      final command = resolveToolCommand(serverpod, [
        'create',
        name,
        for (final ide in configuredIdes(ides)) ...['--ide', ide.option],
        '--no-interactive',
      ]);
      process = await Process.start(
        command.executable,
        command.arguments,
        workingDirectory: workingDirectory,
        environment: toolchain.processEnvironment(),
      );
    } catch (e) {
      throw ProjectCreationException(
        'Could not run Serverpod:\n$serverpod',
        log: '$e',
      );
    }

    void consume(String chunk) {
      log.write(chunk);
      final status = _lastStatusLine(chunk);
      if (status != null) onStatus?.call(status);
    }

    final stdoutSub = process.stdout.transform(utf8.decoder).listen(consume);
    final stderrSub = process.stderr.transform(utf8.decoder).listen(consume);
    final code = await process.exitCode;
    await stdoutSub.cancel();
    await stderrSub.cancel();
    return code;
  }

  /// The runner must launch the companion Flutter app headless, as a plain
  /// web server: its default device also opens the system browser. The port is
  /// left to Flutter — the runner publishes the URL, and the preview loads
  /// whatever it says.
  Future<void> _configureFlutterAppForPreview({
    required String projectPath,
    required String name,
  }) async {
    final pubspec = File(p.join(projectPath, '${name}_server', 'pubspec.yaml'));
    if (!await pubspec.exists()) {
      throw ProjectCreationException(
        'Project created, but ${name}_server/pubspec.yaml was not found. '
        'The app may open in a browser as well as in the preview.',
        createdPath: projectPath,
      );
    }

    final patched = patchFlutterAppForPreview(await pubspec.readAsString());
    if (patched == null) {
      throw ProjectCreationException(
        'Project created, but the flutter_apps section of '
        '${name}_server/pubspec.yaml could not be updated. Set '
        '“device: $kHeadlessWebDevice” on the app manually.',
        createdPath: projectPath,
      );
    }
    await pubspec.writeAsString(patched);
  }
}

/// Last step line in [chunk] — the CLI redraws steps with `\r` and ends each
/// one with an ellipsis (`Running serverpod generator...`). Completion and
/// epilogue lines are skipped so the status keeps naming the running step.
String? _lastStatusLine(String chunk) {
  final plain = chunk.replaceAll(ansiEscapePattern, '').replaceAll('\r', '\n');
  for (final line in const LineSplitter().convert(plain).reversed) {
    final trimmed = line.trim();
    if (!trimmed.endsWith('...') && !trimmed.endsWith('…')) continue;
    // The CLI pads steps with a varying number of dots — normalize them.
    final label = trimmed.replaceAll(RegExp(r'[.…]+$'), '').trimRight();
    if (label.isNotEmpty) return '$label…';
  }
  return null;
}

/// Sets `device: web-server` on the first entry under `flutter_apps:` in a
/// Serverpod server pubspec.
///
/// Nothing else is touched. A `web-port` that is already there stays — the
/// runner publishes whichever port the app ends up on, so App Studio no longer
/// needs one, but a user who pinned one meant it.
///
/// Returns the updated document, or null when the block is not found.
String? patchFlutterAppForPreview(String pubspec) {
  final lines = pubspec.split('\n');

  final headerIndex = lines.indexWhere(
    (line) => RegExp(r'^\s*flutter_apps:\s*$').hasMatch(line),
  );
  if (headerIndex < 0) return null;
  final headerIndent = _indentOf(lines[headerIndex]);

  // First app alias under flutter_apps, e.g. `    my_app:`.
  var entryIndex = -1;
  for (var i = headerIndex + 1; i < lines.length; i++) {
    if (_isSkippable(lines[i])) continue;
    if (_indentOf(lines[i]) <= headerIndent) break;
    entryIndex = i;
    break;
  }
  if (entryIndex < 0) return null;
  final entryIndent = _indentOf(lines[entryIndex]);

  // Properties of that entry — track where to insert and what already exists.
  var lastPropertyIndex = entryIndex;
  var propertyIndent = entryIndent + 2;
  var deviceIndex = -1;
  for (var i = entryIndex + 1; i < lines.length; i++) {
    if (_isSkippable(lines[i])) continue;
    final indent = _indentOf(lines[i]);
    if (indent <= entryIndent) break;
    if (lastPropertyIndex == entryIndex) propertyIndent = indent;
    lastPropertyIndex = i;
    final key = lines[i].trim().split(':').first.trim();
    if (key == 'device') deviceIndex = i;
  }

  final deviceLine = '${' ' * propertyIndent}device: $kHeadlessWebDevice';
  if (deviceIndex >= 0) {
    lines[deviceIndex] = deviceLine;
  } else {
    lines.insert(lastPropertyIndex + 1, deviceLine);
  }
  return lines.join('\n');
}

bool _isSkippable(String line) {
  final trimmed = line.trim();
  return trimmed.isEmpty || trimmed.startsWith('#');
}

int _indentOf(String line) => line.length - line.trimLeft().length;
