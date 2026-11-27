import 'package:flutter_test/flutter_test.dart';
import 'package:makhzan/main.dart';

void main() {
  test('downloadable needs https url and 64 hex sha', () {
    final base = <String, dynamic>{
      'id': 'a',
      'name': 'A',
      'name_ar': 'أ',
      'category': 'games',
      'version': '1.0',
      'apk_url': 'https://example.com/a.apk',
      'sha256': 'a' * 64,
    };
    final ok = StoreApp.fromJson(base);
    expect(ok.downloadable, isTrue);
    expect(ok.isGame, isTrue);

    final noHash = StoreApp.fromJson(<String, dynamic>{...base, 'sha256': 'abc'});
    expect(noHash.downloadable, isFalse);

    final http = StoreApp.fromJson(<String, dynamic>{...base, 'apk_url': 'http://example.com/a.apk'});
    expect(http.downloadable, isFalse);
  });

  test('catalog parses apps and skips junk', () {
    final cat = Catalog.fromJson(<String, dynamic>{
      'store': 'مخزن',
      'updated': '2026-11-27',
      'apps': <dynamic>[
        <String, dynamic>{'id': 'x', 'name_ar': 'إكس', 'name': 'X', 'size_mb': 4.8},
        'junk',
      ],
    });
    expect(cat.store, 'مخزن');
    expect(cat.apps.length, 1);
    expect(cat.apps.first.displayName, 'إكس');
    expect(cat.apps.first.sizeMb, 4.8);
  });
}
