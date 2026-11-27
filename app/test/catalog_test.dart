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

  test('v2 schema fields map to name, blurb and description', () {
    final a = StoreApp.fromJson(<String, dynamic>{
      'id': 'org.example.app',
      'name': 'Example',
      'summary': 'ملخص قصير',
      'desc': 'وصف كامل',
      'category': 'tools',
      'screenshots': <dynamic>['https://x/1.png', ''],
      'license': 'GPL-3.0',
      'min_sdk': 21,
      'updated': '2026-11-20',
    });
    expect(a.displayName, 'Example');
    expect(a.blurb, 'ملخص قصير');
    expect(a.description, 'وصف كامل');
    expect(a.screenshots.length, 1);
    expect(a.minSdk, 21);
    expect(a.updatedAt, '2026-11-20');

    final ar = StoreApp.fromJson(<String, dynamic>{
      'id': 'x',
      'name': 'X',
      'name_ar': 'إكس',
      'desc_ar': 'وصف عربي',
      'desc': 'english',
    });
    expect(ar.displayName, 'إكس');
    expect(ar.description, 'وصف عربي');
  });

  test('catalog reads categories', () {
    final cat = Catalog.fromJson(<String, dynamic>{
      'apps': <dynamic>[],
      'categories': <dynamic>[
        <String, dynamic>{'id': 'games', 'name': 'ألعاب'},
        <String, dynamic>{'id': 'tools', 'name': 'أدوات'},
      ],
    });
    expect(cat.categories.length, 2);
    expect(cat.categories.first.name, 'ألعاب');
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
