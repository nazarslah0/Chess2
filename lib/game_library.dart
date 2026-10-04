import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'analysis_cache.dart' show AnalysisCache, stableHash;
import 'chesscom_service.dart';
import 'pgn_utils.dart';

/// مصدر المباراة في المكتبة.
const String kSourceChessCom = 'chess_com';
const String kSourcePgn = 'pgn';

/// إعدادات التحليل الافتراضية التي يستخدمها GameAnalysisController
/// (يجب أن تبقى مطابقة لها حتى يُعثر على التحليل المحفوظ في الكاش).
const int kLibraryAnalysisDepth = 14;
const int kLibraryAnalysisMultiPv = 2;

/// وسم قواعد التصنيف. غيّره عند أي تعديل في قواعد التصنيف (مثل
/// البريلينت) فيتغير مفتاح الكاش وتُحلَّل المباريات المحفوظة من جديد
/// بدل عرض تصنيفات قديمة.
const String kAnalysisRulesTag = 'brl2';

/// مفتاح إعدادات التحليل الموحَّد (أوزان Maia المتاحة + وسم القواعد).
/// يجب أن يستخدمه المتحكم والمكتبة والإحصائيات معًا.
String analysisSettingsKey(Iterable<dynamic> maiaBuckets) =>
    'maia:${maiaBuckets.join(",")};rules:$kAnalysisRulesTag';

/// معرّف ثابت للمباراة:
///  - Chess.com: `cc_<gameId>` من ترويسة Link / رابط المباراة.
///  - غير ذلك: `h_<hash>` من (White, Black, Date, Time, Result, PGN).
String libraryGameIdFromPgn(String pgn, {String? chessComGameId}) {
  final cc = chessComGameId ?? _chessComIdFromLink(extractPgnHeaders(pgn)['Link']);

  if (cc != null && cc.isNotEmpty) return 'cc_$cc';

  final h = extractPgnHeaders(pgn);

  return 'h_${stableHash([
    h['White'] ?? '',
    h['Black'] ?? '',
    h['Date'] ?? h['UTCDate'] ?? '',
    h['StartTime'] ?? h['UTCTime'] ?? h['EndTime'] ?? '',
    h['Result'] ?? '',
    pgn.trim(),
  ].join('\u0000'))}';
}

String? _chessComIdFromLink(String? link) {
  if (link == null || !link.contains('chess.com')) return null;

  final segs = link.split('/').where((e) => e.isNotEmpty).toList();

  return segs.isNotEmpty && RegExp(r'^\d+$').hasMatch(segs.last)
      ? segs.last
      : null;
}

/// مفتاح التحليل المحفوظ لمباراة في الكاش الدائم (نفس مفتاح
/// GameAnalysisController). [settingsKey] مثل `maia:1100,1500`.
String libraryAnalysisKey(LibraryGame g, String settingsKey) =>
    AnalysisCache.instance.keyFor(
      pgn: g.pgn,
      depth: kLibraryAnalysisDepth,
      multiPv: kLibraryAnalysisMultiPv,
      settings: settingsKey,
    );

/// مباراة محفوظة في مكتبة المستخدم.
class LibraryGame {
  final String id;
  final String? chessComGameId;
  final String username;
  final String white;
  final String black;
  final int? whiteRating;
  final int? blackRating;
  final String result; // 1-0 / 0-1 / 1/2-1/2 / *
  final String date; // yyyy.MM.dd
  final int endTimeMs;
  final String timeClass; // bullet / blitz / rapid / daily / ''
  final String timeControl;
  final bool rated;
  final String eco;
  final String opening;
  final String url;
  final String pgn;
  final String source;
  final int importedAt;

  const LibraryGame({
    required this.id,
    required this.username,
    required this.white,
    required this.black,
    required this.result,
    required this.date,
    required this.pgn,
    required this.source,
    this.chessComGameId,
    this.whiteRating,
    this.blackRating,
    this.endTimeMs = 0,
    this.timeClass = '',
    this.timeControl = '',
    this.rated = true,
    this.eco = '',
    this.opening = '',
    this.url = '',
    this.importedAt = 0,
  });

  /// من مباراة Chess.com (Public API).
  factory LibraryGame.fromChessCom(ChessComGame g, String username) {
    final h = extractPgnHeaders(g.pgn);
    final end = g.endTime;

    final date = end != null
        ? '${end.year}.${end.month.toString().padLeft(2, '0')}.${end.day.toString().padLeft(2, '0')}'
        : (h['Date'] ?? '');

    final gid = g.gameId.isEmpty ? null : g.gameId;

    return LibraryGame(
      id: libraryGameIdFromPgn(g.pgn, chessComGameId: gid),
      chessComGameId: gid,
      username: username.trim().toLowerCase(),
      white: g.whiteUsername,
      black: g.blackUsername,
      whiteRating: g.whiteRating,
      blackRating: g.blackRating,
      result: h['Result'] ?? _resultFrom(g),
      date: date,
      endTimeMs: end?.millisecondsSinceEpoch ?? 0,
      timeClass: g.timeClass,
      timeControl: g.timeControl,
      rated: g.rated,
      eco: g.eco,
      opening: g.opening,
      url: g.url,
      pgn: g.pgn,
      source: kSourceChessCom,
      importedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// من PGN ملصوق (بلا اسم مستخدم).
  factory LibraryGame.fromPgn(String pgn, {String username = ''}) {
    final h = extractPgnHeaders(pgn);

    return LibraryGame(
      id: libraryGameIdFromPgn(pgn),
      chessComGameId: null,
      username: username.trim().toLowerCase(),
      white: h['White'] ?? '?',
      black: h['Black'] ?? '?',
      whiteRating: int.tryParse(h['WhiteElo'] ?? ''),
      blackRating: int.tryParse(h['BlackElo'] ?? ''),
      result: h['Result'] ?? '*',
      date: h['Date'] ?? h['UTCDate'] ?? '',
      timeControl: h['TimeControl'] ?? '',
      eco: h['ECO'] ?? '',
      opening: h['Opening'] ?? '',
      url: h['Link'] ?? '',
      pgn: pgn,
      source: kSourcePgn,
      importedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  static String _resultFrom(ChessComGame g) {
    if (g.whiteResult == 'win') return '1-0';
    if (g.blackResult == 'win') return '0-1';

    return g.whiteResult.isEmpty && g.blackResult.isEmpty ? '*' : '1/2-1/2';
  }

  /// لون المستخدم في المباراة: 'w' / 'b' / null إن لم يُعرف.
  String? get userColor {
    final u = username.toLowerCase();

    if (u.isEmpty) return null;

    if (white.toLowerCase() == u) return 'w';
    if (black.toLowerCase() == u) return 'b';

    return null;
  }

  /// 'win' / 'draw' / 'loss' بالنسبة للمستخدم، أو null.
  String? get outcome {
    final c = userColor;

    if (c == null) return null;

    switch (result) {
      case '1-0':
        return c == 'w' ? 'win' : 'loss';
      case '0-1':
        return c == 'b' ? 'win' : 'loss';
      case '1/2-1/2':
        return 'draw';
    }

    return null;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'cc': chessComGameId,
        'user': username,
        'white': white,
        'black': black,
        'wr': whiteRating,
        'br': blackRating,
        'result': result,
        'date': date,
        'end': endTimeMs,
        'tc': timeClass,
        'tctl': timeControl,
        'rated': rated,
        'eco': eco,
        'opening': opening,
        'url': url,
        'pgn': pgn,
        'source': source,
        'imp': importedAt,
      };

  static LibraryGame? fromJson(dynamic j) {
    if (j is! Map) return null;

    final id = j['id']?.toString();
    final pgn = j['pgn']?.toString();

    if (id == null || pgn == null || pgn.isEmpty) return null;

    int? asInt(dynamic v) => v is num ? v.toInt() : null;

    return LibraryGame(
      id: id,
      chessComGameId: j['cc']?.toString(),
      username: j['user']?.toString() ?? '',
      white: j['white']?.toString() ?? '?',
      black: j['black']?.toString() ?? '?',
      whiteRating: asInt(j['wr']),
      blackRating: asInt(j['br']),
      result: j['result']?.toString() ?? '*',
      date: j['date']?.toString() ?? '',
      endTimeMs: asInt(j['end']) ?? 0,
      timeClass: j['tc']?.toString() ?? '',
      timeControl: j['tctl']?.toString() ?? '',
      rated: j['rated'] != false,
      eco: j['eco']?.toString() ?? '',
      opening: j['opening']?.toString() ?? '',
      url: j['url']?.toString() ?? '',
      pgn: pgn,
      source: j['source']?.toString() ?? kSourcePgn,
      importedAt: asInt(j['imp']) ?? 0,
    );
  }
}

/// حالة آخر مزامنة لحساب Chess.com.
class SyncState {
  final int lastSyncMs;

  /// آخر شهر (yyyy/MM) جُلب بالكامل أو جزئيًا.
  final String lastMonth;

  const SyncState({required this.lastSyncMs, required this.lastMonth});
}

/// تخزين دائم لمكتبة المباريات (ملف JSON مضغوط في مجلد التطبيق،
/// كتابة ذرية). لا يضيف أي اعتماد جديد.
class GameLibraryStorage {
  GameLibraryStorage({Future<Directory> Function()? directoryProvider})
      : _directoryProvider = directoryProvider ?? _defaultDirectory;

  static GameLibraryStorage instance = GameLibraryStorage();

  final Future<Directory> Function() _directoryProvider;

  Map<String, LibraryGame>? _games;
  final Map<String, SyncState> _sync = <String, SyncState>{};

  Future<void> _queue = Future<void>.value();

  static Future<Directory> _defaultDirectory() async {
    final base = await getApplicationSupportDirectory();

    return Directory('${base.path}/game_library');
  }

  Future<File> _file() async {
    final d = await _directoryProvider();

    if (!await d.exists()) await d.create(recursive: true);

    return File('${d.path}/library.json.gz');
  }

  Future<Map<String, LibraryGame>> _load() async {
    final cached = _games;

    if (cached != null) return cached;

    final out = <String, LibraryGame>{};

    try {
      final f = await _file();

      if (await f.exists()) {
        final json = jsonDecode(utf8.decode(gzip.decode(await f.readAsBytes())));

        if (json is Map) {
          if (json['games'] is List) {
            for (final j in json['games'] as List) {
              final g = LibraryGame.fromJson(j);

              if (g != null) out[g.id] = g;
            }
          }

          if (json['sync'] is Map) {
            (json['sync'] as Map).forEach((k, v) {
              if (v is Map) {
                _sync[k.toString()] = SyncState(
                  lastSyncMs: (v['t'] as num?)?.toInt() ?? 0,
                  lastMonth: v['m']?.toString() ?? '',
                );
              }
            });
          }
        }
      }
    } catch (_) {}

    return _games = out;
  }

  Future<void> _persist() async {
    final games = _games;

    if (games == null) return;

    final text = jsonEncode(<String, dynamic>{
      'games': [for (final g in games.values) g.toJson()],
      'sync': {
        for (final e in _sync.entries)
          e.key: {'t': e.value.lastSyncMs, 'm': e.value.lastMonth},
      },
    });

    final next = _queue.then((_) async {
      try {
        final f = await _file();
        final tmp = File('${f.path}.tmp');

        await tmp.writeAsBytes(gzip.encode(utf8.encode(text)), flush: true);
        await tmp.rename(f.path);
      } catch (_) {}
    });

    _queue = next.catchError((Object _) {});

    await next;
  }

  /// كل المباريات (الأحدث أولًا).
  Future<List<LibraryGame>> all() async {
    final list = (await _load()).values.toList();

    list.sort((a, b) {
      final c = b.endTimeMs.compareTo(a.endTimeMs);

      return c != 0 ? c : b.importedAt.compareTo(a.importedAt);
    });

    return list;
  }

  Future<bool> contains(String id) async => (await _load()).containsKey(id);

  Future<Set<String>> ids() async => (await _load()).keys.toSet();

  /// يضيف المباريات الجديدة فقط ويتجاهل الموجودة. يعيد عدد المضافة.
  Future<int> add(List<LibraryGame> games) async {
    final map = await _load();

    var added = 0;

    for (final g in games) {
      if (map.containsKey(g.id)) continue;

      map[g.id] = g;
      added++;
    }

    if (added > 0) await _persist();

    return added;
  }

  Future<void> remove(String id) async {
    final map = await _load();

    if (map.remove(id) != null) await _persist();
  }

  Future<SyncState?> syncState(String username) async {
    await _load();

    return _sync[username.trim().toLowerCase()];
  }

  Future<void> saveSyncState(String username, SyncState s) async {
    await _load();

    _sync[username.trim().toLowerCase()] = s;

    await _persist();
  }

  /// للاختبار: يحاكي إعادة تشغيل التطبيق.
  void resetMemory() {
    _games = null;
    _sync.clear();
  }
}
