import 'package:appstudio/platform/host_platform.dart';
import 'package:appstudio/toolchain/tool_status.dart';
import 'package:appstudio/toolchain/toolchain.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/toolchain_support.dart';

/// The environment every spawned tool gets: the resolved SDKs first on `PATH`,
/// written the way the host writes it.
void main() {
  Future<Toolchain> withFlutterAt(String root, String executable,
      {required HostPlatform host, Map<String, String> facts = const {}}) async {
    final manifest = await loadTestManifest();
    return Toolchain(
      ToolchainInventory(
        manifest: manifest,
        tools: {
          ToolId.flutter: ToolStatus(
            spec: manifest[ToolId.flutter]!,
            candidates: [
              ToolCandidate(
                id: ToolId.flutter,
                source: ToolSource.host,
                fitness: ToolFitness.satisfied,
                root: root,
                executable: executable,
                facts: {'flutterRoot': root, ...facts},
              ),
            ],
            action: ToolAction.none,
          ),
        },
      ),
      host: host,
    );
  }

  test('macOS puts Flutter first on a colon-separated PATH', () async {
    final toolchain = await withFlutterAt(
      '/Users/a/develop/flutter',
      '/Users/a/develop/flutter/bin/flutter',
      host: HostPlatform.macos,
    );

    final env = toolchain.processEnvironment(
      parent: {'PATH': '/usr/bin:/bin', 'HOME': '/Users/a'},
    );

    expect(env['PATH'], '/Users/a/develop/flutter/bin:/usr/bin:/bin');
    expect(env['FLUTTER_ROOT'], '/Users/a/develop/flutter');
  });

  test('Windows rewrites the existing Path in place, joined with ;', () async {
    final toolchain = await withFlutterAt(
      r'C:\Users\a\develop\flutter',
      r'C:\Users\a\develop\flutter\bin\flutter.bat',
      host: HostPlatform.windows,
    );

    final env = toolchain.processEnvironment(
      parent: {
        'Path': r'C:\Windows\system32;C:\Program Files\Git\cmd',
        'SystemRoot': r'C:\Windows',
      },
    );

    expect(
      env['PATH'],
      r'C:\Users\a\develop\flutter\bin;C:\Windows\system32;'
      r'C:\Program Files\Git\cmd',
    );
    // One entry, not a `Path` and a `PATH` that disagree.
    expect(
      env.keys.where((k) => k.toUpperCase() == 'PATH'),
      hasLength(1),
    );
    expect(env['SystemRoot'], r'C:\Windows');
  });

  test('a Flutter behind a shim is not pinned', () async {
    // The runner asks the shim from each project's folder, so FVM or Puro
    // picks the SDK that project is pinned to. FLUTTER_ROOT or DART_SDK would
    // override that with whatever the shim answered at probe time.
    final toolchain = await withFlutterAt(
      '/Users/a/fvm/versions/3.47.5',
      '/Users/a/.fvm_shim/flutter',
      host: HostPlatform.macos,
      facts: {
        'launcher': '/Users/a/.fvm_shim/flutter',
        'launcherPath': '/Users/a/.fvm_shim:/opt/homebrew/bin:/usr/bin',
      },
    );

    // A Finder launch: launchd's PATH, which has neither the shim nor fvm.
    final env = toolchain.processEnvironment(
      parent: {'PATH': '/usr/bin:/bin', 'HOME': '/Users/a'},
    );

    expect(env['PATH'], '/Users/a/.fvm_shim:/opt/homebrew/bin:/usr/bin:/bin');
    expect(env.containsKey('FLUTTER_ROOT'), isFalse);
    expect(env.containsKey('DART_SDK'), isFalse);
  });

  test('Windows puts a shim and its Path first, once each', () async {
    final toolchain = await withFlutterAt(
      r'C:\Users\a\.puro\envs\stable\flutter',
      r'C:\Users\a\.puro\bin\flutter.bat',
      host: HostPlatform.windows,
      facts: {
        'launcher': r'C:\Users\a\.puro\bin\flutter.bat',
        'launcherPath': r'C:\Users\a\.puro\bin;C:\Windows\system32',
      },
    );

    final env = toolchain.processEnvironment(
      parent: {'Path': r'C:\WINDOWS\system32'},
    );

    expect(env['PATH'], r'C:\Users\a\.puro\bin;C:\Windows\system32');
  });
}
