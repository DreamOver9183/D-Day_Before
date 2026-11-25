import 'package:shared_preferences/shared_preferences.dart';

/// In-memory [SharedPreferences] whose writes can be made to fail, either by
/// returning `false` (what the plugin does on a failed commit) or by throwing.
class FakePrefs implements SharedPreferences {
  FakePrefs([Map<String, Object>? initial])
      : data = <String, Object>{...?initial};

  final Map<String, Object> data;

  /// Keys whose writes return `false`.
  final Set<String> rejectKeys = <String>{};

  /// Keys whose writes throw.
  final Set<String> throwKeys = <String>{};

  /// Awaited before every write; lets tests hold writes in flight.
  Future<void> Function(String key)? beforeWrite;

  Future<bool> _write(String key, void Function() apply) async {
    final hook = beforeWrite;
    if (hook != null) {
      await hook(key);
    }
    if (throwKeys.contains(key)) {
      throw StateError('disk full');
    }
    if (rejectKeys.contains(key)) {
      return false;
    }
    apply();
    return true;
  }

  @override
  String? getString(String key) => data[key] as String?;

  @override
  bool? getBool(String key) => data[key] as bool?;

  @override
  bool containsKey(String key) => data.containsKey(key);

  @override
  Future<bool> setString(String key, String value) =>
      _write(key, () => data[key] = value);

  @override
  Future<bool> setBool(String key, bool value) =>
      _write(key, () => data[key] = value);

  @override
  Future<bool> remove(String key) => _write(key, () => data.remove(key));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
