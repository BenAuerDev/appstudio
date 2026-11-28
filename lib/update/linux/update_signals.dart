/// What the updater and its dialog tell each other, in a file of its own,
/// free of `dart:io`, so the dialog can use it.
library;

/// Asked between chunks of a download, which stops when it says so.
class UpdateCancellation {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// The new AppImage is in place, but App Studio could not start it: there
/// is nothing to try again, only to start it by hand.
class UpdateInstalledException implements Exception {
  const UpdateInstalledException(this.version, this.message);

  /// The version now installed.
  final String version;
  final String message;

  @override
  String toString() => message;
}
