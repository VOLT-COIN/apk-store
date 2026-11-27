import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

// Catalogue locations, tried in order. The raw repo file is always current,
// the site URLs are kept as fallbacks in case GitHub raw is unreachable.
const List<String> kCatalogUrls = <String>[
  'https://raw.githubusercontent.com/VOLT-COIN/apk-store/main/catalog.json',
  'https://makhzan-apps.pages.dev/catalog.json',
  'https://volt-coin.github.io/apk-store/catalog.json',
];
const MethodChannel kNative = MethodChannel('makhzan/native');

const Color kBg = Color(0xFF0F1420);
const Color kCard = Color(0xFF1A2234);
const Color kFg = Color(0xFFEEF2F8);
const Color kMut = Color(0xFF9AA7BD);
const Color kAccent = Color(0xFF3DDC97);
const Color kOnAccent = Color(0xFF06210F);
const Color kLine = Color(0xFF2A3550);

void main() {
  runApp(const MakhzanApp());
}

// ---------------------------------------------------------------- models

class StoreApp {
  final String id;
  final String name;
  final String nameAr;
  final String category;
  final String version;
  final String developer;
  final String descAr;
  final String apkUrl;
  final String sha256;
  final String status;
  final String packageName;
  final String iconUrl;
  final String changelogAr;
  final String license;
  final String sourceUrl;
  final double? sizeMb;
  final List<String> screenshots;

  StoreApp({
    required this.id,
    required this.name,
    required this.nameAr,
    required this.category,
    required this.version,
    required this.developer,
    required this.descAr,
    required this.apkUrl,
    required this.sha256,
    required this.status,
    required this.packageName,
    required this.iconUrl,
    required this.changelogAr,
    required this.license,
    required this.sourceUrl,
    this.sizeMb,
    this.screenshots = const <String>[],
  });

  factory StoreApp.fromJson(Map<String, dynamic> j) {
    String s(String k) => (j[k] ?? '').toString();
    return StoreApp(
      id: s('id'),
      name: s('name'),
      nameAr: s('name_ar'),
      category: s('category'),
      version: s('version'),
      developer: s('developer'),
      descAr: s('desc_ar'),
      apkUrl: s('apk_url'),
      sha256: s('sha256'),
      status: s('status'),
      packageName: s('package_name'),
      iconUrl: s('icon_url'),
      changelogAr: s('changelog_ar'),
      license: s('license'),
      sourceUrl: s('source_url'),
      sizeMb: j['size_mb'] is num ? (j['size_mb'] as num).toDouble() : null,
      screenshots: j['screenshots'] is List
          ? (j['screenshots'] as List)
              .map((e) => e.toString())
              .where((e) => e.isNotEmpty)
              .toList()
          : const <String>[],
    );
  }

  String get displayName => nameAr.isNotEmpty ? nameAr : name;

  bool get isGame => category == 'games';

  bool get downloadable =>
      apkUrl.startsWith('https://') &&
      RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(sha256);
}

class Catalog {
  final String store;
  final String updated;
  final List<StoreApp> apps;

  Catalog({required this.store, required this.updated, required this.apps});

  factory Catalog.fromJson(Map<String, dynamic> j) {
    final raw = j['apps'] is List ? (j['apps'] as List) : const <dynamic>[];
    return Catalog(
      store: (j['store'] ?? 'مخزن التطبيقات').toString(),
      updated: (j['updated'] ?? '').toString(),
      apps: raw
          .whereType<Map<dynamic, dynamic>>()
          .map((e) => StoreApp.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

class CatalogResult {
  final Catalog? catalog;
  final bool fromCache;
  final String? error;
  CatalogResult(this.catalog, {this.fromCache = false, this.error});
}

// ------------------------------------------------------------ networking

class CatalogRepo {
  static Future<File> _cacheFile() async {
    final dir = await Native.filesDir();
    return File('$dir/catalog-cache.json');
  }

  static Future<CatalogResult> fetch() async {
    File? cache;
    try {
      cache = await _cacheFile();
    } catch (_) {
      cache = null;
    }
    try {
      String body = '';
      Object? lastError;
      for (final url in kCatalogUrls) {
        try {
          body = await _httpGet(url);
          break;
        } catch (e) {
          lastError = e;
        }
      }
      if (body.isEmpty) throw lastError ?? Exception('مفيش اتصال بأي مصدر للكتالوج');
      final map = jsonDecode(body);
      if (map is! Map<String, dynamic>) throw Exception('صيغة الكتالوج غير صحيحة');
      final catalog = Catalog.fromJson(map);
      if (catalog.apps.isEmpty) throw Exception('الكتالوج فاضي');
      if (cache != null) {
        try {
          await cache.writeAsString(body);
        } catch (_) {}
      }
      return CatalogResult(catalog);
    } catch (e) {
      if (cache != null) {
        try {
          if (await cache.exists()) {
            final txt = await cache.readAsString();
            final map = jsonDecode(txt);
            if (map is Map<String, dynamic>) {
              return CatalogResult(Catalog.fromJson(map),
                  fromCache: true, error: _short(e));
            }
          }
        } catch (_) {}
      }
      return CatalogResult(null, error: _short(e));
    }
  }

  static Future<String> _httpGet(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.userAgentHeader, 'MakhzanStore/1.0 (Android)');
      req.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      final res = await req.close();
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      return await res.transform(utf8.decoder).join();
    } finally {
      client.close(force: true);
    }
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest d) {
    value = d;
  }

  @override
  void close() {}
}

class Downloader {
  static Future<File> download(
    StoreApp app, {
    required void Function(double) onProgress,
  }) async {
    final dir = await Native.filesDir();
    final target = Directory('$dir/apk');
    if (!await target.exists()) await target.create(recursive: true);
    final raw = app.apkUrl.split('/').last;
    final safe = raw.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final file = File('${target.path}/${app.id}-$safe');
    if (await file.exists()) await file.delete();

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    IOSink? sink;
    try {
      final req = await client.getUrl(Uri.parse(app.apkUrl));
      req.headers.set(HttpHeaders.userAgentHeader, 'MakhzanStore/1.0 (Android)');
      req.followRedirects = true;
      req.maxRedirects = 8;
      final res = await req.close();
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final total = res.contentLength;
      sink = file.openWrite();
      final acc = _DigestSink();
      final hasher = sha256.startChunkedConversion(acc);
      var received = 0;
      await for (final chunk in res) {
        hasher.add(chunk);
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress(received / total);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      hasher.close();
      final got = (acc.value?.toString() ?? '').toLowerCase();
      if (got != app.sha256.toLowerCase()) {
        try {
          await file.delete();
        } catch (_) {}
        throw Exception('الملف مش مطابق لرقم التحقق، اتحذف');
      }
      onProgress(1);
      return file;
    } finally {
      if (sink != null) {
        try {
          await sink.close();
        } catch (_) {}
      }
      client.close(force: true);
    }
  }
}

// ---------------------------------------------------------------- native

class Native {
  static Future<String> filesDir() async {
    try {
      final v = await kNative.invokeMethod<String>('filesDir');
      if (v != null && v.isNotEmpty) return v;
    } catch (_) {}
    return Directory.systemTemp.path;
  }

  static Future<bool> canInstall() async {
    try {
      return await kNative.invokeMethod<bool>('canInstall') ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> openInstallSettings() async {
    try {
      await kNative.invokeMethod('openInstallSettings');
    } catch (_) {}
  }

  static Future<bool> install(String path) async {
    try {
      return await kNative.invokeMethod<bool>('install', {'path': path}) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> installedVersion(String pkg) async {
    if (pkg.isEmpty) return null;
    try {
      return await kNative.invokeMethod<String>('installedVersion', {'package': pkg});
    } catch (_) {
      return null;
    }
  }
}

// ---------------------------------------------------------------- helpers

String _short(Object e) {
  final s = e.toString().replaceFirst('Exception: ', '');
  return s.length > 140 ? '${s.substring(0, 140)}…' : s;
}

String _sizeLabel(double? mb) {
  if (mb == null) return '';
  if (mb >= 1) return '${mb.toStringAsFixed(2)} MB';
  return '${(mb * 1024).round()} KB';
}

// ------------------------------------------------------------------ app

class MakhzanApp extends StatelessWidget {
  const MakhzanApp({super.key});

  @override
  Widget build(BuildContext context) {
    final seed = ColorScheme.fromSeed(seedColor: kAccent, brightness: Brightness.dark);
    final dark = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: kBg,
      colorScheme: seed.copyWith(primary: kAccent, onPrimary: kOnAccent, surface: kBg),
      textTheme: Typography.material2021(platform: TargetPlatform.android)
          .white
          .apply(bodyColor: kFg, displayColor: kFg),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
    return MaterialApp(
      title: 'مخزن التطبيقات',
      debugShowCheckedModeBanner: false,
      theme: dark,
      locale: const Locale('ar'),
      supportedLocales: const <Locale>[Locale('ar'), Locale('en')],
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child ?? const SizedBox()),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Catalog? _catalog;
  bool _loading = true;
  bool _fromCache = false;
  String? _error;
  String _query = '';
  String _category = '';
  final Map<String, String?> _installed = <String, String?>{};
  final Map<String, double> _progress = <String, double>{};
  final Set<String> _busy = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await CatalogRepo.fetch();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _catalog = r.catalog;
      _fromCache = r.fromCache;
      _error = r.error;
    });
    unawaited(_refreshInstalled());
  }

  Future<void> _refreshInstalled() async {
    final apps = _catalog?.apps ?? const <StoreApp>[];
    final map = <String, String?>{};
    for (final a in apps) {
      map[a.id] = await Native.installedVersion(a.packageName);
    }
    if (!mounted) return;
    setState(() {
      _installed
        ..clear()
        ..addAll(map);
    });
  }

  List<StoreApp> get _visible {
    final apps = _catalog?.apps ?? const <StoreApp>[];
    final q = _query.trim().toLowerCase();
    return apps.where((a) {
      if (_category.isNotEmpty && a.category != _category) return false;
      if (q.isEmpty) return true;
      final hay = '${a.name} ${a.nameAr} ${a.descAr} ${a.developer}'.toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _askInstallPermission() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('السماح بالتثبيت'),
        content: const Text(
            'عشان نثبّت التطبيقات، لازم تسمح لمخزن التطبيقات إنه يفتح ملفات APK. اضغط «الإعدادات» وفعّل «السماح من هذا المصدر»، وبعدين ارجع وجرّب تاني.'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('الإعدادات')),
        ],
      ),
    );
    if (go == true) await Native.openInstallSettings();
  }

  Future<void> _download(StoreApp app) async {
    if (_busy.contains(app.id)) return;
    if (!app.downloadable) {
      _toast('الملف مش متاح للتحميل لحد ما يترفع');
      return;
    }
    final can = await Native.canInstall();
    if (!can) {
      await _askInstallPermission();
      return;
    }
    setState(() {
      _busy.add(app.id);
      _progress[app.id] = 0;
    });
    try {
      final f = await Downloader.download(app, onProgress: (p) {
        if (mounted) setState(() => _progress[app.id] = p);
      });
      final opened = await Native.install(f.path);
      _toast(opened ? 'تم التحقق من الملف ✓ اتبع خطوات التثبيت' : 'الملف اتحمّل بس المثبّت مفتحش');
      await Future<void>.delayed(const Duration(seconds: 2));
      unawaited(_refreshInstalled());
    } catch (e) {
      _toast('فشل التحميل: ${_short(e)}');
    } finally {
      if (mounted) {
        setState(() {
          _busy.remove(app.id);
          _progress.remove(app.id);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final apps = _visible;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: kAccent,
          backgroundColor: kCard,
          onRefresh: _load,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: <Widget>[
              SliverToBoxAdapter(child: _header(context)),
              if (_fromCache)
                SliverToBoxAdapter(
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0x33FFB020),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0x66FFB020)),
                    ),
                    child: const Text('بتشوف نسخة محفوظة من الكتالوج، مفيش اتصال بالإنترنت دلوقتي.',
                        style: TextStyle(fontSize: 13)),
                  ),
                ),
              if (_loading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator(color: kAccent)),
                )
              else if (apps.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _emptyState(),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (c, i) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _AppCard(
                          app: apps[i],
                          installedVersion: _installed[apps[i].id],
                          progress: _progress[apps[i].id],
                          busy: _busy.contains(apps[i].id),
                          onOpen: () => _openDetail(apps[i]),
                          onDownload: () => _download(apps[i]),
                        ),
                      ),
                      childCount: apps.length,
                    ),
                  ),
                ),
              SliverToBoxAdapter(child: _footer(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final total = _catalog?.apps.length ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: <Color>[kAccent, Color(0xFF2BB3FF)]),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: const Text('م',
                    style: TextStyle(
                        color: kOnAccent, fontSize: 26, fontWeight: FontWeight.w900, height: 1.1)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text('مخزن التطبيقات',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                    Text(
                      total > 0 ? '$total تطبيق ولعبة · تحميل مباشر مع رقم تحقق SHA-256' : 'تحميل مباشر مع رقم تحقق SHA-256',
                      style: const TextStyle(fontSize: 12.5, color: kMut),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'تحديث',
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh_rounded),
                color: kMut,
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            onChanged: (v) => setState(() => _query = v),
            textInputAction: TextInputAction.search,
            style: const TextStyle(fontSize: 15),
            decoration: InputDecoration(
              hintText: 'ابحث عن تطبيق أو لعبة',
              hintStyle: const TextStyle(color: kMut, fontSize: 15),
              prefixIcon: const Icon(Icons.search_rounded, color: kMut),
              filled: true,
              fillColor: kCard,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                _chip('الكل', ''),
                _chip('ألعاب', 'games'),
                _chip('تطبيقات', 'apps'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, String value) {
    final on = _category == value;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: GestureDetector(
        onTap: () => setState(() => _category = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          decoration: BoxDecoration(
            color: on ? kAccent : kCard,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: on ? kAccent : kLine),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: on ? kOnAccent : kFg)),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(_error == null ? Icons.search_off_rounded : Icons.cloud_off_rounded,
              size: 54, color: kMut),
          const SizedBox(height: 14),
          Text(
            _error == null ? 'مفيش نتائج للبحث ده' : 'مش قادر أجيب الكتالوج',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(_error!, style: const TextStyle(fontSize: 12.5, color: kMut), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('جرّب تاني'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _footer(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      child: Column(
        children: <Widget>[
          const Divider(color: kLine),
          const SizedBox(height: 8),
          Text(
            'كل التطبيقات هنا من تطوير أصحابها أو بإذنهم. قبل التثبيت فعّل «التثبيت من مصادر غير معروفة» من إعدادات الجهاز.',
            style: const TextStyle(fontSize: 12, color: kMut, height: 1.5),
            textAlign: TextAlign.center,
          ),
          if ((_catalog?.updated ?? '').isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text('آخر تحديث للكتالوج: ${_catalog!.updated}',
                style: const TextStyle(fontSize: 11.5, color: kMut)),
          ],
        ],
      ),
    );
  }

  void _openDetail(StoreApp app) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (c) => _DetailSheet(
        app: app,
        installedVersion: _installed[app.id],
        busy: _busy.contains(app.id),
        progress: _progress[app.id],
        onDownload: () {
          Navigator.pop(c);
          _download(app);
        },
      ),
    );
  }
}

class _AppCard extends StatelessWidget {
  final StoreApp app;
  final String? installedVersion;
  final double? progress;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onDownload;

  const _AppCard({
    required this.app,
    required this.installedVersion,
    required this.progress,
    required this.busy,
    required this.onOpen,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final pct = ((progress ?? 0) * 100).clamp(0, 100).toStringAsFixed(0);
    return Material(
      color: kCard,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  AppIcon(app: app, size: 60),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Flexible(
                              child: Text(app.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 16.5, fontWeight: FontWeight.w800)),
                            ),
                            if (installedVersion != null) ...<Widget>[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0x223DDC97),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0x663DDC97)),
                                ),
                                child: const Text('مثبّت',
                                    style: TextStyle(fontSize: 10.5, color: kAccent)),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          <String>[
                            if (app.version.isNotEmpty) 'الإصدار ${app.version}',
                            if (app.sizeMb != null) _sizeLabel(app.sizeMb),
                            if (app.isGame) 'لعبة' else if (app.category.isNotEmpty) 'تطبيق',
                          ].join(' · '),
                          style: const TextStyle(fontSize: 12, color: kMut),
                        ),
                        const SizedBox(height: 6),
                        Text(app.descAr,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, height: 1.45)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: app.downloadable
                    ? FilledButton.icon(
                        onPressed: busy ? null : onDownload,
                        style: FilledButton.styleFrom(
                          backgroundColor: busy ? kLine : kAccent,
                          foregroundColor: busy ? kFg : kOnAccent,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: kFg),
                              )
                            : const Icon(Icons.download_rounded, size: 20),
                        label: Text(
                          busy ? 'جارٍ التحميل $pct%' : 'تحميل وتثبيت',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
                        ),
                      )
                    : Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          color: kLine,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text('قريبًا',
                            style: TextStyle(fontWeight: FontWeight.w700, color: kMut)),
                      ),
              ),
              if (busy && progress != null) ...<Widget>[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress == 0 ? null : progress,
                    minHeight: 4,
                    backgroundColor: kLine,
                    color: kAccent,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class AppIcon extends StatelessWidget {
  final StoreApp app;
  final double size;

  const AppIcon({super.key, required this.app, required this.size});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.26);
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: kAccent, borderRadius: radius),
      alignment: Alignment.center,
      child: Text(
        app.displayName.isEmpty ? '?' : app.displayName.substring(0, 1),
        style: TextStyle(color: kOnAccent, fontSize: size * 0.44, fontWeight: FontWeight.w900),
      ),
    );
    final url = app.iconUrl;
    if (url.startsWith('data:image')) {
      try {
        final bytes = base64Decode(url.substring(url.indexOf(',') + 1));
        return ClipRRect(
          borderRadius: radius,
          child: Image.memory(bytes,
              width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback),
        );
      } catch (_) {
        return fallback;
      }
    }
    if (url.startsWith('https://')) {
      return ClipRRect(
        borderRadius: radius,
        child: Image.network(url,
            width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback),
      );
    }
    return fallback;
  }
}

class _DetailSheet extends StatelessWidget {
  final StoreApp app;
  final String? installedVersion;
  final bool busy;
  final double? progress;
  final VoidCallback onDownload;

  const _DetailSheet({
    required this.app,
    required this.installedVersion,
    required this.busy,
    required this.progress,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 24 + bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Center(
            child: Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(color: kLine, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: <Widget>[
              AppIcon(app: app, size: 72),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(app.displayName,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(
                      <String>[
                        app.name,
                        if (app.developer.isNotEmpty) app.developer,
                      ].where((e) => e.isNotEmpty).join(' · '),
                      style: const TextStyle(fontSize: 12.5, color: kMut),
                    ),
                    if (installedVersion != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('مثبّت عندك: الإصدار $installedVersion',
                            style: const TextStyle(fontSize: 12, color: kAccent)),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              _stat('الإصدار', app.version.isEmpty ? '—' : app.version),
              _stat('الحجم', app.sizeMb == null ? '—' : _sizeLabel(app.sizeMb)),
              _stat('النوع', app.isGame ? 'لعبة' : 'تطبيق'),
            ],
          ),
          const SizedBox(height: 18),
          Text(app.descAr, style: const TextStyle(fontSize: 14, height: 1.6)),
          if (app.changelogAr.isNotEmpty) ...<Widget>[
            const SizedBox(height: 16),
            const Text('الجديد', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(app.changelogAr, style: const TextStyle(fontSize: 13, color: kMut, height: 1.5)),
          ],
          if (app.screenshots.isNotEmpty) ...<Widget>[
            const SizedBox(height: 16),
            SizedBox(
              height: 180,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: app.screenshots.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (c, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(app.screenshots[i], fit: BoxFit.cover),
                ),
              ),
            ),
          ],
          if (app.packageName.isNotEmpty) ...<Widget>[
            const SizedBox(height: 16),
            _copyRow(context, 'اسم الحزمة', app.packageName),
          ],
          if (app.sha256.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            _copyRow(context, 'SHA-256', app.sha256),
          ],
          if (app.license.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Text('الترخيص: ${app.license}',
                style: const TextStyle(fontSize: 12, color: kMut)),
          ],
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: app.downloadable
                ? FilledButton.icon(
                    onPressed: busy ? null : onDownload,
                    style: FilledButton.styleFrom(
                      backgroundColor: kAccent,
                      foregroundColor: kOnAccent,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('تحميل وتثبيت',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  )
                : Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    decoration:
                        BoxDecoration(color: kLine, borderRadius: BorderRadius.circular(14)),
                    child: const Text('مش متاح للتحميل لسه',
                        style: TextStyle(fontWeight: FontWeight.w700, color: kMut)),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(left: 8),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: <Widget>[
            Text(label, style: const TextStyle(fontSize: 11, color: kMut)),
            const SizedBox(height: 3),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Widget _copyRow(BuildContext context, String label, String value) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: value));
        if (context.mounted) {
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(SnackBar(content: Text('اتنسخ $label')));
        }
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(10)),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(label, style: const TextStyle(fontSize: 11, color: kMut)),
                  const SizedBox(height: 2),
                  Text(value,
                      style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const Icon(Icons.copy_rounded, size: 16, color: kMut),
          ],
        ),
      ),
    );
  }
}
