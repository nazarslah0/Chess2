import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'analysis_result.dart';

/// بصمة 64 بت (مكوّنة من FNV-1a بـ32 بت مرتين ببذرتين مختلفتين) لنص
/// طويل، بدون حزمة crypto. كافية لمفاتيح التخزين (ليست أمنية).
String stableHash(String input) {
  var h1 = 0x811c9dc5;
  var h2 = 0x01000193 ^ 0x9e3779b9;

  for (final unit in utf8.encode(input)) {
    h1 = ((h1 ^ unit) * 0x01000193) & 0xFFFFFFFF;
    h2 = ((h2 ^ unit) * 0x01000193 + 0x7f4a7c15) & 0xFFFFFFFF;
  }

  String hex(int v) => v.toRadixString(16).padLeft(8, '0');

  return '${hex(h1)}${hex(h2)}';
}

/// ملخص مباراة محفوظة (لقائمة المباريات المحلَّلة).
class CachedGameSummary {
  final String key;
  final SavedGame game;
  final int createdAt;
  final int depth;

  const CachedGameSummary({
    required this.key,
    required this.game,
    required this.createdAt,
    required this.depth,
  });
}

/// كاش دائم لتحليل المباريات.
///
/// - الطبقة 1: ذاكرة (Map) لأسرع وصول داخل الجلسة.
/// - الطبقة 2: ملفات JSON مضغوطة (gzip) في مجلد التطبيق، ملف لكل
///   تحليل باسم مفتاحه. لا يضيف أي اعتماد جديد (path_provider موجود).
///
/// المفتاح = بصمة (PGN + إصدار المحرك + العمق + MultiPV + إصدار
/// التحليل + إعدادات التحليل). أي تغيير في أحدها يعطي مفتاحًا مختلفًا
/// فلا يُستخدم تحليل قديم غير متوافق. وأي ملف إصدار تحليله مختلف
/// يُتجاهل ويُحذف.
///
/// الإخراج من المجلد بسياسة LRU: عند تجاوز [maxEntries] يُحذف الأقدم
/// استخدامًا. كل خطأ I/O يُبتلع (الكاش اختياري، لا يكسر التحليل).
class AnalysisCache {
  AnalysisCache({
    Future<Directory> Function()? directoryProvider,
    this.maxEntries = 100,
  }) : _directoryProvider = directoryProvider ?? _defaultDirectory;

  static AnalysisCache instance = AnalysisCache();

  final Future<Directory> Function() _directoryProvider;
  final int maxEntries;

  final Map<String, ({SavedGame game, GameAnalysis analysis})> _memory =
      <String, ({SavedGame game, GameAnalysis analysis})>{};

  Directory? _dir;

  // تسلسل عمليات الكتابة/الحذف كي لا تتداخل.
  Future<void> _queue = Future<void>.value();

  static Future<Directory> _defaultDirectory() async {
    final base = await getApplicationSupportDirectory();

    return Directory('${base.path}/analysis_cache');
  }

  /// مفتاح الكاش: بصمة (PGN + المحرك + العمق + MultiPV + الإصدار +
  /// الإعدادات).
  String keyFor({
    required String pgn,
    required int depth,
    required int multiPv,
    String engineVersion = kEngineVersion,
    String settings = '',
  }) {
    final composite = [
      pgn.trim(),
      engineVersion,
      'd$depth',
      'mpv$multiPv',
      'v$kAnalysisVersion',
      settings,
    ].join('\u0000');

    return stableHash(composite);
  }

  Future<Directory?> _directory() async {
    if (_dir != null) return _dir;

    try {
      final d = await _directoryProvider();

      if (!await d.exists()) await d.create(recursive: true);

      _dir = d;

      return d;
    } catch (_) {
      return null;
    }
  }

  File _file(Directory d, String key) => File('${d.path}/$key.json.gz');

  /// يحمّل تحليلًا محفوظًا، أو null إن لم يوجد أو لم يعد صالحًا.
  Future<GameAnalysis?> load(String key) async {
    final mem = _memory[key];

    if (mem != null) return mem.analysis;

    final d = await _directory();

    if (d == null) return null;

    final f = _file(d, key);

    try {
      if (!await f.exists()) return null;

      final text = utf8.decode(gzip.decode(await f.readAsBytes()));
      final json = jsonDecode(text) as Map;

      final analysis = GameAnalysis.fromJson(json['analysis']);

      if (analysis.analysisVersion != kAnalysisVersion ||
          !analysis.isConsistent) {
        await _safeDelete(f);

        return null;
      }

      final game = SavedGame.fromJson(json['game']);

      _memory[key] = (game: game, analysis: analysis);

      // "لمس" الملف لسياسة LRU.
      try {
        await f.setLastModified(DateTime.now());
      } catch (_) {}

      return analysis;
    } catch (_) {
      // ملف تالف: نحذفه.
      await _safeDelete(f);

      return null;
    }
  }

  /// يحفظ تحليلًا مكتملًا (الذاكرة + القرص).
  Future<void> save(
    String key,
    SavedGame game,
    GameAnalysis analysis,
  ) {
    _memory[key] = (game: game, analysis: analysis);

    return _enqueue(() async {
      final d = await _directory();

      if (d == null) return;

      try {
        final text = jsonEncode(<String, dynamic>{
          'game': game.toJson(),
          'analysis': analysis.toJson(),
        });

        final bytes = gzip.encode(utf8.encode(text));

        final target = _file(d, key);
        final tmp = File('${target.path}.tmp');

        // كتابة ذرية: ملف مؤقت ثم إعادة تسمية.
        await tmp.writeAsBytes(bytes, flush: true);
        await tmp.rename(target.path);

        await _evict(d);
      } catch (_) {}
    });
  }

  /// قائمة المباريات المحفوظة (الأحدث أولًا).
  Future<List<CachedGameSummary>> list() async {
    final d = await _directory();

    if (d == null) return const <CachedGameSummary>[];

    final out = <CachedGameSummary>[];

    try {
      await for (final e in d.list()) {
        if (e is! File || !e.path.endsWith('.json.gz')) continue;

        try {
          final json = jsonDecode(
            utf8.decode(gzip.decode(await e.readAsBytes())),
          ) as Map;

          final a = GameAnalysis.fromJson(json['analysis']);

          if (a.analysisVersion != kAnalysisVersion) continue;

          final name = e.uri.pathSegments.last;

          out.add(
            CachedGameSummary(
              key: name.substring(0, name.length - '.json.gz'.length),
              game: SavedGame.fromJson(json['game']),
              createdAt: a.createdAt,
              depth: a.depth,
            ),
          );
        } catch (_) {}
      }
    } catch (_) {}

    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return out;
  }

  Future<void> clear() {
    _memory.clear();

    return _enqueue(() async {
      final d = await _directory();

      if (d == null) return;

      try {
        await for (final e in d.list()) {
          if (e is File) await _safeDelete(e);
        }
      } catch (_) {}
    });
  }

  /// يمسح طبقة الذاكرة فقط (للاختبار: محاكاة إعادة تشغيل التطبيق).
  void clearMemory() => _memory.clear();

  Future<void> _evict(Directory d) async {
    final files = <(File, DateTime)>[];

    await for (final e in d.list()) {
      if (e is File && e.path.endsWith('.json.gz')) {
        files.add((e, (await e.lastModified())));
      }
    }

    if (files.length <= maxEntries) return;

    files.sort((a, b) => a.$2.compareTo(b.$2));

    for (final f in files.take(files.length - maxEntries)) {
      await _safeDelete(f.$1);

      final name = f.$1.uri.pathSegments.last;

      _memory.remove(name.substring(0, name.length - '.json.gz'.length));
    }
  }

  Future<void> _safeDelete(File f) async {
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  Future<void> _enqueue(Future<void> Function() job) {
    final next = _queue.then((_) => job()).catchError((Object _) {});

    _queue = next;

    return next;
  }
}
