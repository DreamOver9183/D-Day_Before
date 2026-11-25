import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The installed app's version (from the Android package).
class AppVersion {
  const AppVersion({required this.name, required this.code});

  final String name;
  final int code;
}

/// A newer release available on GitHub.
class UpdateInfo {
  const UpdateInfo({
    required this.versionName,
    required this.versionCode,
    required this.apkUrl,
    required this.sha256,
    this.notes = '',
  });

  final String versionName;
  final int versionCode;
  final String apkUrl;
  final String sha256;
  final String notes;

  bool isNewerThan(AppVersion current) => versionCode > current.code;
}

/// Thrown when the update check cannot reach GitHub or gets bad data.
class UpdateCheckException implements Exception {
  const UpdateCheckException(this.message);
  final String message;

  @override
  String toString() => 'UpdateCheckException: $message';
}

/// Error codes from the native installer (see `UpdateInstaller.kt`).
abstract final class UpdateErrorCodes {
  static const String downloadFailed = 'DOWNLOAD_FAILED';
  static const String checksumMismatch = 'CHECKSUM_MISMATCH';
  static const String installNotAllowed = 'INSTALL_NOT_ALLOWED';
}

/// Where update information comes from.
abstract class UpdateSource {
  /// The latest published release, or null if none is published.
  Future<UpdateInfo?> fetchLatest();
}

/// Name of the release asset describing the update.
const String updateManifestAsset = 'update.json';

/// Reads the latest GitHub Release of the app's public repository.
///
/// Each release carries the APK plus `update.json` with `versionCode`,
/// `versionName`, `apk` (the APK asset name) and `sha256` (64 lowercase hex).
/// Only public GitHub endpoints are contacted and no personal data is sent.
class GitHubUpdateSource implements UpdateSource {
  const GitHubUpdateSource({
    this.owner = 'DreamOver9183',
    this.repo = 'D-Day_Before',
    this.timeout = const Duration(seconds: 15),
  });

  final String owner;
  final String repo;
  final Duration timeout;

  @override
  Future<UpdateInfo?> fetchLatest() async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final release = await _getJson(
        client,
        Uri.https('api.github.com', '/repos/$owner/$repo/releases/latest'),
        allowNotFound: true,
      );
      if (release == null) return null; // nothing published yet

      final manifestUrl = findAssetUrl(release, updateManifestAsset);
      if (manifestUrl == null) {
        throw const UpdateCheckException('release has no update.json');
      }
      final manifest = await _getJson(client, Uri.parse(manifestUrl));
      return parseUpdate(release, manifest!);
    } on UpdateCheckException {
      rethrow;
    } on Exception catch (e) {
      throw UpdateCheckException(e.toString());
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>?> _getJson(
    HttpClient client,
    Uri uri, {
    bool allowNotFound = false,
  }) async {
    final request = await client.getUrl(uri).timeout(timeout);
    request.headers
      ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
      ..set(HttpHeaders.userAgentHeader, 'D-Day-Before-Updater');
    final response = await request.close().timeout(timeout);
    final body = await response.transform(utf8.decoder).join().timeout(timeout);
    if (allowNotFound && response.statusCode == HttpStatus.notFound) {
      return null;
    }
    if (response.statusCode != HttpStatus.ok) {
      throw UpdateCheckException('HTTP ${response.statusCode} for $uri');
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const UpdateCheckException('unexpected JSON');
    }
    return decoded;
  }
}

final RegExp _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');

/// Download URL of the release asset called [name], or null.
String? findAssetUrl(Map<String, dynamic> release, String name) {
  final assets = release['assets'];
  if (assets is! List) return null;
  for (final asset in assets) {
    if (asset is Map && asset['name'] == name) {
      final url = asset['browser_download_url'];
      if (url is String) return url;
    }
  }
  return null;
}

/// Combines a GitHub release with its `update.json`; throws on bad data.
UpdateInfo parseUpdate(
  Map<String, dynamic> release,
  Map<String, dynamic> manifest,
) {
  final code = manifest['versionCode'];
  final name = manifest['versionName'];
  final apk = manifest['apk'];
  final sha = manifest['sha256'];
  if (code is! int || code <= 0) {
    throw const UpdateCheckException('bad versionCode');
  }
  if (name is! String || name.isEmpty) {
    throw const UpdateCheckException('bad versionName');
  }
  if (apk is! String || apk.isEmpty) {
    throw const UpdateCheckException('bad apk name');
  }
  if (sha is! String || !_sha256Pattern.hasMatch(sha)) {
    throw const UpdateCheckException('bad sha256');
  }
  final apkUrl = findAssetUrl(release, apk);
  if (apkUrl == null) {
    throw const UpdateCheckException('apk asset missing');
  }
  final body = release['body'];
  return UpdateInfo(
    versionName: name,
    versionCode: code,
    apkUrl: apkUrl,
    sha256: sha,
    notes: body is String ? body.trim() : '',
  );
}

/// Automatic checks run at most once a day. A last-check time in the future
/// (clock changed) also allows a check.
bool shouldAutoCheck({required DateTime? lastCheck, required DateTime now}) {
  if (lastCheck == null) return true;
  final elapsed = now.difference(lastCheck);
  return elapsed.isNegative || elapsed >= const Duration(hours: 24);
}
