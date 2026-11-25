import 'dart:io';

/// Resolves per-item background photo names to files in app storage.
///
/// Photos are saved by the Android side as `bg_<32 hex>.jpg` in a private
/// folder. Items keep only the name, so a backup restored on another phone
/// simply finds no file and falls back to the normal look.
class BackgroundImages {
  BackgroundImages._();

  static final RegExp _namePattern = RegExp(r'^bg_[0-9a-f]{32}\.jpg$');

  static String? _dir;

  /// Folder holding the photos; set once at startup from the native side.
  static String? get directory => _dir;

  static void configure(String? directory) {
    _dir = directory;
  }

  static bool isValidName(String name) => _namePattern.hasMatch(name);

  /// Returns [raw] if it is a well-formed photo name, otherwise null.
  static String? normalizeName(dynamic raw) =>
      raw is String && isValidName(raw) ? raw : null;

  /// The photo file for [name], or null if unset, unknown, or missing on disk.
  static File? fileFor(String? name) {
    final dir = _dir;
    if (name == null || dir == null || !isValidName(name)) return null;
    final file = File('$dir${Platform.pathSeparator}$name');
    return file.existsSync() ? file : null;
  }
}
