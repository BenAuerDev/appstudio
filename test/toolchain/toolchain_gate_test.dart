import 'package:appstudio/toolchain/tool_status.dart';
import 'package:appstudio/toolchain/toolchain_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/toolchain_support.dart';

/// The condition that decides which screen `main.dart` shows, which App menu
/// items are live, and whether `StudioShell` will open Settings at all.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ToolManifest manifest;

  setUpAll(() async {
    manifest = await loadTestManifest();
  });

  ToolchainInventory inventoryOf(
    Map<ToolId, ToolAction> actions, {
    bool legacy = false,
  }) =>
      ToolchainInventory(
        manifest: manifest,
        legacyInstallFound: legacy,
        tools: {
          for (final e in actions.entries)
            e.key: ToolStatus(
              spec: manifest[e.key]!,
              candidates: const [],
              action: e.value,
            ),
        },
      );

  test('a tool App Studio can install puts first-run setup on screen', () {
    final inventory = inventoryOf({ToolId.flutter: ToolAction.install});

    expect(inventory.installable, isNotEmpty);
    expect(inventory.needsSetup, isTrue);
  });

  test('so does a Flutter the user has to update themselves', () {
    // Setup is where they are asked to — and the Serverpod CLI is installed
    // with that Flutter's dart, so nothing else can go ahead first.
    final inventory = inventoryOf({ToolId.flutter: ToolAction.manual});

    expect(inventory.installable, isEmpty);
    expect(inventory.needsManualUpdate, hasLength(1));
    expect(inventory.needsSetup, isTrue);
  });

  test('so does a toolchain an earlier build left behind', () {
    // Even with every tool already usable: the old copies and their PATH block
    // still have to go, and the user has to be told why.
    expect(inventoryOf(const {}, legacy: true).needsSetup, isTrue);
  });

  test('a complete toolchain does not', () {
    expect(inventoryOf(const {}).needsSetup, isFalse);
  });

  test('installable is in install order, whatever order the map is in', () {
    // The Command Line Tools supply Flutter's git, and Flutter supplies the
    // dart the Serverpod CLI is installed with.
    final inventory = inventoryOf({
      ToolId.serverpodCli: ToolAction.install,
      ToolId.flutter: ToolAction.update,
      ToolId.commandLineTools: ToolAction.install,
    });

    expect(
      [for (final t in inventory.installable) t.id],
      [ToolId.commandLineTools, ToolId.flutter, ToolId.serverpodCli],
    );
  });

  group('flutterFound', () {
    ToolchainInventory withFlutter(List<ToolCandidate> candidates) =>
        ToolchainInventory(
          manifest: manifest,
          tools: {
            ToolId.flutter: ToolStatus(
              spec: manifest[ToolId.flutter]!,
              candidates: candidates,
            ),
          },
        );

    test('is false with nothing on the Mac', () {
      expect(withFlutter(const []).flutterFound, isFalse);
      expect(
        withFlutter(const [
          ToolCandidate.notFound(ToolId.flutter, ToolSource.host),
        ]).flutterFound,
        isFalse,
      );
    });

    test('is true for a Flutter too old to use', () {
      // It is still the user's own Flutter; setup asks them to update it
      // rather than announcing that App Studio stopped shipping one.
      expect(
        withFlutter(const [
          ToolCandidate(
            id: ToolId.flutter,
            source: ToolSource.host,
            fitness: ToolFitness.wrongVersion,
          ),
        ]).flutterFound,
        isTrue,
      );
    });
  });

  group('flutterShimMissing', () {
    ToolchainInventory inventory({
      List<FlutterWrapper> wrappers = const [],
      bool onPath = false,
    }) =>
        ToolchainInventory(
          manifest: manifest,
          tools: const {},
          flutterWrappers: wrappers,
          flutterOnPath: onPath,
        );

    test('a Mac with no version manager never needs a shim', () {
      // A clean Mac included: the notice used to show there too.
      expect(inventory().flutterShimMissing, isFalse);
    });

    test('a version manager with no flutter on PATH does', () {
      expect(
        inventory(wrappers: [FlutterWrapper.fvm]).flutterShimMissing,
        isTrue,
      );
      expect(
        inventory(wrappers: [FlutterWrapper.puro]).flutterShimMissing,
        isTrue,
      );
    });

    test('a flutter on PATH is the shim, whatever it leads to', () {
      expect(
        inventory(wrappers: FlutterWrapper.values, onPath: true)
            .flutterShimMissing,
        isFalse,
      );
    });
  });

  group('flutterWrapperFor', () {
    test('names the manager that keeps an SDK', () {
      expect(flutterWrapperFor('/Users/a/fvm/versions/3.47.5'),
          FlutterWrapper.fvm);
      expect(flutterWrapperFor('/Users/a/code/app/.fvm/flutter_sdk'),
          FlutterWrapper.fvm);
      expect(flutterWrapperFor('/Users/a/.puro/envs/stable/flutter'),
          FlutterWrapper.puro);
      expect(flutterWrapperFor(r'C:\Users\a\.puro\envs\stable\flutter'),
          FlutterWrapper.puro);
    });

    test('an ordinary folder has none', () {
      expect(flutterWrapperFor('/Users/a/develop/flutter'), isNull);
      // Whole path segments only.
      expect(flutterWrapperFor('/Users/fvmfan/flutter'), isNull);
      expect(flutterWrapperFor(null), isNull);
    });
  });
}
