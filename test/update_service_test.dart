import 'package:dday_before/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final sha = 'ab' * 32;
  Map<String, dynamic> release({List<Map<String, Object>>? assets, Object? body}) =>
      <String, dynamic>{
        'tag_name': 'v1.0.2',
        'body': body ?? '修正小工具顯示\n新增照片',
        'assets': assets ??
            <Map<String, Object>>[
              <String, Object>{
                'name': 'dday_before-1.0.2.apk',
                'browser_download_url':
                    'https://github.com/o/r/releases/download/v1.0.2/dday_before-1.0.2.apk',
              },
              <String, Object>{
                'name': 'update.json',
                'browser_download_url':
                    'https://github.com/o/r/releases/download/v1.0.2/update.json',
              },
            ],
      };
  Map<String, dynamic> manifest({Object? code = 9, Object? sha256}) =>
      <String, dynamic>{
        'versionCode': code,
        'versionName': '1.0.2',
        'apk': 'dday_before-1.0.2.apk',
        'sha256': sha256 ?? sha,
      };

  group('parseUpdate', () {
    test('reads a well-formed release', () {
      final info = parseUpdate(release(), manifest());
      expect(info.versionCode, 9);
      expect(info.versionName, '1.0.2');
      expect(info.apkUrl, endsWith('/dday_before-1.0.2.apk'));
      expect(info.sha256, sha);
      expect(info.notes, '修正小工具顯示\n新增照片');
    });

    test('rejects bad manifests', () {
      expect(() => parseUpdate(release(), manifest(code: 0)),
          throwsA(isA<UpdateCheckException>()));
      expect(() => parseUpdate(release(), manifest(code: '9')),
          throwsA(isA<UpdateCheckException>()));
      expect(() => parseUpdate(release(), manifest(sha256: 'AB' * 32)),
          throwsA(isA<UpdateCheckException>()));
      expect(() => parseUpdate(release(), manifest(sha256: 'short')),
          throwsA(isA<UpdateCheckException>()));
      expect(
        () => parseUpdate(release(assets: <Map<String, Object>>[]), manifest()),
        throwsA(isA<UpdateCheckException>()),
        reason: 'APK asset missing',
      );
    });

    test('missing notes become empty', () {
      final info = parseUpdate(release(body: 42), manifest());
      expect(info.notes, isEmpty);
    });
  });

  test('isNewerThan compares version codes', () {
    final info = parseUpdate(release(), manifest(code: 9));
    expect(info.isNewerThan(const AppVersion(name: '1.0.1', code: 8)), isTrue);
    expect(info.isNewerThan(const AppVersion(name: '1.0.2', code: 9)), isFalse);
    expect(info.isNewerThan(const AppVersion(name: '9.9.9', code: 10)), isFalse);
  });

  test('findAssetUrl tolerates odd release JSON', () {
    expect(findAssetUrl(<String, dynamic>{}, 'update.json'), isNull);
    expect(
      findAssetUrl(<String, dynamic>{'assets': 'nope'}, 'update.json'),
      isNull,
    );
  });

  test('automatic checks run at most once a day', () {
    final now = DateTime.utc(2026, 11, 26, 9);
    expect(shouldAutoCheck(lastCheck: null, now: now), isTrue);
    expect(
      shouldAutoCheck(lastCheck: now.subtract(const Duration(hours: 23)), now: now),
      isFalse,
    );
    expect(
      shouldAutoCheck(lastCheck: now.subtract(const Duration(hours: 24)), now: now),
      isTrue,
    );
    expect(
      shouldAutoCheck(lastCheck: now.add(const Duration(days: 3)), now: now),
      isTrue,
      reason: 'clock moved backwards',
    );
  });
}
