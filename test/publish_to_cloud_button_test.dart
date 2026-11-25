import 'package:appstudio/cloud/cloud_publish.dart';
import 'package:appstudio/theme/app_theme.dart';
import 'package:appstudio/ui/publish_to_cloud_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shad/shad.dart';
import 'package:xterm/xterm.dart';

import '../widgetbook/fakes/cloud.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpButton(
    WidgetTester tester,
    FakeCloudPublisher publisher,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ShadApp(
        theme: buildLightTheme(),
        home: Scaffold(
          body: Center(child: PublishToCloudButton(publisher: publisher)),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('Publish to Cloud'));
    // The terminal's cursor blinks, so never settles.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('starts a publish and shows its terminal', (tester) async {
    final publisher = FakeCloudPublisher();
    await pumpButton(tester, publisher);
    await open(tester);

    expect(publisher.starts, 1);
    expect(find.text('Publish to Serverpod Cloud'), findsOneWidget);
    expect(find.byType(TerminalView), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    // Alert variant: no close X.
    expect(find.byIcon(LucideIcons.x), findsNothing);
  });

  testWidgets('Cancel asks first, and only Stop cancels', (tester) async {
    final run = FakeCloudPublishRun.running();
    await pumpButton(tester, FakeCloudPublisher(run));
    await open(tester);

    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Stop publishing?'), findsOneWidget);

    await tester.tap(find.text('Keep going'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(run.cancels, 0);
    expect(find.text('Stop publishing?'), findsNothing);

    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Stop'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(run.cancels, 1);
    expect(find.text('Publishing cancelled'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('the barrier and the back gesture do not close a running '
      'publish', (tester) async {
    final run = FakeCloudPublishRun.running();
    await pumpButton(tester, FakeCloudPublisher(run));
    await open(tester);

    await tester.tapAt(const Offset(5, 5));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(PublishToCloudDialog), findsOneWidget);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator).last);
    await navigator.maybePop();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(PublishToCloudDialog), findsOneWidget);
    expect(find.text('Stop publishing?'), findsOneWidget);
  });

  testWidgets('success hides the terminal for the project links', (
    tester,
  ) async {
    final run = FakeCloudPublishRun.running();
    await pumpButton(tester, FakeCloudPublisher(run));
    await open(tester);

    run.finish(
      CloudPublishPhase.succeeded,
      code: 0,
      links: const CloudProjectLinks('my-app'),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(TerminalView), findsNothing);
    expect(find.text('Published to Serverpod Cloud'), findsOneWidget);
    expect(find.text('https://my-app.serverpod.space/'), findsOneWidget);
    expect(find.text('https://my-app.api.serverpod.space/'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(PublishToCloudDialog), findsNothing);
  });

  testWidgets('failure keeps the terminal under a banner, and Try again '
      'retries', (tester) async {
    final run = FakeCloudPublishRun.running();
    await pumpButton(tester, FakeCloudPublisher(run));
    await open(tester);

    run.finish(CloudPublishPhase.failed, code: 1);
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Publishing failed'), findsOneWidget);
    expect(find.textContaining('exit code 1'), findsOneWidget);
    expect(find.byType(TerminalView), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(run.retries, 1);
    expect(find.text('Publishing failed'), findsNothing);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('a run that could not start says why', (tester) async {
    await pumpButton(
      tester,
      FakeCloudPublisher(FakeCloudPublishRun.couldNotStart()),
    );
    await open(tester);

    expect(find.text('The Serverpod CLI is not installed.'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(PublishToCloudDialog), findsNothing);
  });

  group('keys in the terminal', () {
    Future<List<String>> typing(
      WidgetTester tester,
      Future<void> Function() keys,
    ) async {
      final run = FakeCloudPublishRun.running();
      final sent = <String>[];
      run.terminal.onOutput = sent.add;
      await pumpButton(tester, FakeCloudPublisher(run));
      await open(tester);
      await keys();
      await tester.pump();
      return sent;
    }

    testWidgets('Enter, Escape and Ctrl-C go to the CLI', (tester) async {
      final sent = await typing(tester, () async {
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      });
      expect(sent, ['\r', '\x1b', '\x03']);
      // Escape went to the CLI, not to the dialog.
      expect(find.byType(PublishToCloudDialog), findsOneWidget);
    });

    testWidgets('⌘ chords are left for the menu bar on macOS', (tester) async {
      final sent = await typing(tester, () async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      });
      expect(sent, isEmpty);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    testWidgets('Ctrl+Shift+C copies on Windows instead of reaching the CLI', (
      tester,
    ) async {
      final sent = await typing(tester, () async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      });
      // Only the plain Ctrl-C reached the CLI.
      expect(sent, ['\x03']);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  });
}
