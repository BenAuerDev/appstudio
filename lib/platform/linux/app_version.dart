import 'package:flutter/foundation.dart';

/// A version of App Studio: `0.4.1` and the build counter (`25`) that orders
/// releases.
@immutable
class AppVersion {
  const AppVersion(this.version, this.build);

  final String version;
  final int build;

  @override
  bool operator ==(Object other) =>
      other is AppVersion && other.version == version && other.build == build;

  @override
  int get hashCode => Object.hash(version, build);

  @override
  String toString() => '$version+$build';
}

/// Another copy of App Studio than the one in the app menu is running: one
/// downloaded again, say. Only for a copy App Studio added itself; Gear
/// Lever updates its own.
@immutable
class OtherCopy {
  const OtherCopy({required this.running, required this.added});

  final AppVersion running;
  final AppVersion added;

  bool get runningIsNewer => running.build > added.build;
  bool get runningIsOlder => running.build < added.build;
}
