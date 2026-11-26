import 'package:appstudio/process/project_creator.dart';
import 'package:appstudio/theme/app_theme.dart';
import 'package:appstudio/widgets/error_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shad/shad.dart';

import '../../widgetbook/fakes/project.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> copied;

  setUp(() {
    copied = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  // macOS, the platform the shortcuts are written for. On the test default
  // (Android) Flutter binds Ctrl-C itself.
  final macOS = TargetPlatformVariant.only(TargetPlatform.macOS);

  final crash = ProjectCreationException.fromCliOutput(
    kSampleInternalErrorOutput,
    exitCode: 1,
  );

  /// The banner as the New Project form shows it, above a text field standing
  /// in for the form's name field.
  Future<void> pumpBanner(WidgetTester tester, {bool withLog = true}) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ShadApp(
        theme: buildLightTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 460,
            child: Column(
              children: [
                ErrorBanner(
                  message: crash.message,
                  log: withLog ? crash.log : null,
                  fullLog: withLog ? crash.output : null,
                ),
                const ShadInput(),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<bool> pressWithCommand(
    WidgetTester tester,
    LogicalKeyboardKey key,
    String character,
  ) async {
    await tester.sendKeyDownEvent(
      LogicalKeyboardKey.metaLeft,
      platform: 'macos',
    );
    final handled = await tester.sendKeyDownEvent(
      key,
      platform: 'macos',
      character: character,
    );
    await tester.sendKeyUpEvent(key, platform: 'macos');
    await tester.sendKeyUpEvent(
      LogicalKeyboardKey.metaLeft,
      platform: 'macos',
    );
    await tester.pump();
    return handled;
  }

  Finder copyButton() => find.byWidgetPredicate(
        (w) =>
            w is ShadIconButton && w.semanticLabel == 'Copy error and output',
      );

  /// Taps the log, which is what a user does before dragging a selection,
  /// and checks the banner's selection now holds focus.
  Future<void> focusBanner(WidgetTester tester) async {
    // Near the top of the log: its centre is scrolled out of the pane.
    await tester.tapAt(
      tester.getTopLeft(find.textContaining('#0      parsePubspec')) +
          const Offset(20, 6),
    );
    await tester.pump();
    final focused = FocusManager.instance.primaryFocus?.context;
    expect(
      focused?.findAncestorWidgetOfExactType<SelectionArea>(),
      isNotNull,
      reason: 'the banner should hold focus',
    );
  }

  testWidgets('the message and log are selectable and ⌘C copies them', (
    tester,
  ) async {
    await pumpBanner(tester);
    await focusBanner(tester);

    expect(await pressWithCommand(tester, LogicalKeyboardKey.keyA, 'a'), isTrue);
    expect(await pressWithCommand(tester, LogicalKeyboardKey.keyC, 'c'), isTrue);

    // One selection across both, so a drag can take the message and the
    // stack together.
    expect(copied.single, contains(crash.message));
    expect(copied.single, contains('#0      parsePubspec'));
  }, variant: macOS);

  testWidgets('the copy button copies the message and the whole output', (
    tester,
  ) async {
    await pumpBanner(tester);

    await tester.tap(copyButton());
    await tester.pump();

    expect(
      copied.single,
      '${crash.message}\n\n```\n${kSampleInternalErrorOutput.trimRight()}\n```',
    );
    // The full output, not the part the pane shows.
    expect(copied.single, contains('Yikes!'));
    expect(find.byIcon(LucideIcons.check), findsOneWidget);
  });

  testWidgets('a banner with no log has no copy button', (tester) async {
    await pumpBanner(tester, withLog: false);

    expect(copyButton(), findsNothing);
    // Still selectable.
    expect(find.byType(SelectionArea), findsOneWidget);
  });

  testWidgets('the log pane stays capped and scrolls', (tester) async {
    await pumpBanner(tester);

    final pane = find.ancestor(
      of: find.textContaining('#0      parsePubspec'),
      matching: find.byType(SingleChildScrollView),
    );
    expect(
      tester.getSize(pane).height,
      lessThanOrEqualTo(ErrorBanner.logMaxHeight),
    );
  });

  group('keys the banner does not own pass through', () {
    testWidgets('a menu shortcut', (tester) async {
      await pumpBanner(tester);
      await focusBanner(tester);

      expect(
        await pressWithCommand(tester, LogicalKeyboardKey.keyW, 'w'),
        isFalse,
        reason: '⌘W belongs to the menu bar',
      );
    }, variant: macOS);

    testWidgets('typing', (tester) async {
      await pumpBanner(tester);
      await focusBanner(tester);

      expect(
        await tester.sendKeyEvent(LogicalKeyboardKey.keyX, platform: 'macos'),
        isFalse,
      );
    }, variant: macOS);

    testWidgets('Tab moves on, to the copy button and then the form', (
      tester,
    ) async {
      await pumpBanner(tester);
      await focusBanner(tester);

      Future<BuildContext?> tab() async {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab, platform: 'macos');
        await tester.pump();
        return FocusManager.instance.primaryFocus?.context;
      }

      expect(
        (await tab())?.findAncestorWidgetOfExactType<ShadIconButton>(),
        isNotNull,
      );
      expect(
        (await tab())?.findAncestorWidgetOfExactType<EditableText>(),
        isNotNull,
      );
    }, variant: macOS);
  });
}
