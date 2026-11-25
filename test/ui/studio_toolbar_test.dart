import 'package:appstudio/runner/server_status.dart';
import 'package:appstudio/theme/app_theme.dart';
import 'package:appstudio/ui/studio_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shad/shad.dart';

import '../../widgetbook/fakes/cloud.dart';
import '../../widgetbook/fakes/project.dart';
import '../../widgetbook/fakes/runner.dart';
import '../../widgetbook/fakes/tools.dart';

void main() {
  Future<void> pumpAt(
    WidgetTester tester,
    double width, {
    ServerStatus status = const ServerStatus.running(),
    FakeFullRestart? process,
    VoidCallback? onBack,
    VoidCallback? onViewLogs,
  }) async {
    tester.view.physicalSize = Size(width, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ShadApp(
        theme: buildLightTheme(),
        home: Align(
          alignment: Alignment.topCenter,
          child: StudioToolbar(
            status: FakeServerStatus(status),
            tools: FakeToolsView(inventory: completeInventory),
            process: process ?? FakeFullRestart(),
            actions: FakeRunnerActions(),
            editors: FakeExternalEditors(
              editors: const [cursorEditor, claudeEditor],
            ),
            publisher: FakeCloudPublisher(),
            onManageTools: () {},
            onBack: onBack ?? () {},
            onViewLogs: onViewLogs ?? () {},
          ),
        ),
      ),
    );
  }

  testWidgets('a wide window keeps the full buttons', (tester) async {
    await pumpAt(tester, 1280);

    expect(find.text('Open in Cursor'), findsOneWidget);
    expect(find.text('Publish to Cloud'), findsOneWidget);
    expect(find.text('Open in…'), findsNothing);
  });

  testWidgets('the narrowest window folds them, and nothing overflows',
      (tester) async {
    await pumpAt(tester, 670);

    expect(find.text('Open in…'), findsOneWidget);
    expect(find.text('Open in Cursor'), findsNothing);
    expect(find.text('Running'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the back button closes the project', (tester) async {
    var backs = 0;
    await pumpAt(tester, 1280, onBack: () => backs++);

    await tester.tap(find.bySemanticsLabel('Close project'));
    expect(backs, 1);
  });

  testWidgets('a running server offers no recovery', (tester) async {
    await pumpAt(tester, 1280);

    expect(find.text('View Logs'), findsNothing);
    expect(find.text('Try Again'), findsNothing);
  });

  testWidgets('a stopped server offers View Logs and Try Again',
      (tester) async {
    final process = FakeFullRestart(isStopped: true);
    var views = 0;
    // Wider than the others: the test font makes every glyph a full em, which
    // folds the labels at 1280 when the app's font would not.
    await pumpAt(
      tester,
      1800,
      status: const ServerStatus.stopped('Failed', detail: 'boom'),
      process: process,
      onViewLogs: () => views++,
    );

    await tester.tap(find.text('View Logs'));
    expect(views, 1);

    await tester.tap(find.text('Try Again'));
    await tester.pump();
    expect(process.isTransitioning, isTrue);
    // The restart is under way: the actions step aside for its spinner.
    expect(find.text('Try Again'), findsNothing);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('the narrowest window folds them to icons, without overflow',
      (tester) async {
    await pumpAt(
      tester,
      670,
      status: const ServerStatus.stopped('Build failed'),
      process: FakeFullRestart(isStopped: true),
    );

    expect(find.text('Try Again'), findsNothing);
    expect(find.bySemanticsLabel('Try Again'), findsOneWidget);
    expect(find.bySemanticsLabel('View Logs'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
