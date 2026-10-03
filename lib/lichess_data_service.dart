import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

// ================================================================
// خدمات بيانات Lichess المجانية:
//
//  1) Tablebase  (tablebase.lichess.ovh): نتيجة مضمونة (فوز / تعادل /
//     خسارة) لأي وضعية فيها 7 قطع أو أقل.
//  2) Opening Explorer (explorer.lichess.ovh): إحصائيات النقلات من
//     مباريات الأساتذة (Masters) ومباريات لاعبي Lichess.
//
// المبدأ العام: أي فشل (انقطاع إنترنت، 429، رفض صلاحية...) يعيد null،
// والمستدعي يرجع للتقدير المحلي — لا نكسر التحليل أبدًا بسبب هذه
// الخدمات.
//
// ملاحظة عن Explorer: Lichess قد يطلب Personal API Token (مجاني، بلا
// أي صلاحيات scopes) لطلبات الـ Explorer. مرّره عند البناء:
//   flutter build apk --dart-define=LICHESS_TOKEN=lip_xxxxx
// أو برمجيًا: LichessApiConfig.explorerToken = '...'.
// Tablebase لا يحتاج توكن.
// ================================================================

const String _kEnvToken = String.fromEnvironment('LICHESS_TOKEN');

class LichessApiConfig {
  LichessApiConfig._();

  static String? explorerToken = _kEnvToken.isEmpty ? null : _kEnvToken;
}

class _Resp {
  final int status;
  final String body;

  const _Resp(this.status, this.body);
}

const Duration _kTimeout = Duration(seconds: 8);

String _fenParam(String fen) =>
    Uri.encodeQueryComponent(fen.trim()).replaceAll('+', '%20');

Future<_Resp?> _httpGet(
  String url, {
  String? bearer,
}) async {
  try {
    final headers = <String, String>{
      'Accept': 'application/json',
      'User-Agent': 'ChessAnalyzer/1.0 (Flutter)',
    };

    if (bearer != null && bearer.isNotEmpty) {
      headers['Authorization'] = 'Bearer $bearer';
    }

    final res = await http
        .get(Uri.parse(url), headers: headers)
        .timeout(_kTimeout);

    return _Resp(res.statusCode, utf8.decode(res.bodyBytes));
  } catch (_) {
    return null;
  }
}

/// كتلة صغيرة لإيقاف الطلبات مؤقتًا بعد 429 أو فشل متكرر، بدل
/// إغراق الخادم (Lichess يطلب عدم الإلحاح عند 429).
class _Backoff {
  DateTime? _until;
  int _failures = 0;

  bool get blocked =>
      _until != null && DateTime.now().isBefore(_until!);

  void success() => _failures = 0;

  void rateLimited() {
    _until = DateTime.now().add(const Duration(seconds: 60));
  }

  void failure() {
    _failures++;

    if (_failures >= 3) {
      _failures = 0;
      _until = DateTime.now().add(const Duration(seconds: 30));
    }
  }
}

// ================================================================
// Tablebase
// ================================================================

class TablebaseService {
  TablebaseService._();

  static final TablebaseService instance = TablebaseService._();

  static const String _base = 'https://tablebase.lichess.ovh/standard';

  final Map<String, int?> _cache = <String, int?>{};
  final _Backoff _backoff = _Backoff();

  /// هل الوضعية صالحة للاستعلام؟ (7 قطع أو أقل، بلا حقوق تبييت —
  /// الـ Tablebase لا يدعم التبييت).
  static bool isEligible(String fen) {
    final parts = fen.trim().split(RegExp(r'\s+'));

    if (parts.length < 3) return false;

    if (parts[2] != '-') return false;

    var pieces = 0;

    for (final unit in parts[0].codeUnits) {
      final isUpper = unit >= 65 && unit <= 90;
      final isLower = unit >= 97 && unit <= 122;

      if (isUpper || isLower) pieces++;
    }

    return pieces >= 2 && pieces <= 7;
  }

  /// يحوّل category من Lichess (من منظور اللاعب صاحب الدور) إلى
  /// نتيجة من منظور الأبيض: 1 فوز الأبيض، 0 تعادل، -1 فوز الأسود،
  /// أو null إن كانت غير حاسمة (unknown / maybe-* / syzygy-*).
  /// "فوز مشروط بقاعدة الـ50 نقلة" و"خسارة مشروطة" = تعادل.
  static int? whiteWdlFromCategory(String? category, String fen) {
    final sideToMove = _categoryResult(category);

    if (sideToMove == null) return null;

    final parts = fen.trim().split(RegExp(r'\s+'));
    final white = parts.length > 1 ? parts[1] == 'w' : true;

    return white ? sideToMove : -sideToMove;
  }

  final Map<String, TablebaseDetail?> _detailCache =
      <String, TablebaseDetail?>{};

  static int? _categoryResult(String? category) {
    switch (category) {
      case 'win':
        return 1;
      case 'loss':
        return -1;
      case 'draw':
      case 'cursed-win':
      case 'blessed-loss':
        return 0;
      default:
        return null;
    }
  }

  /// تفاصيل الوضعية: النتيجة والنقلات مرتبة (للعرض في شاشة تحليل
  /// الوضعية). null إن لم تكن مؤهلة أو تعذّر الجلب.
  Future<TablebaseDetail?> probeDetailed(String fen) async {
    final clean = fen.trim();

    if (!isEligible(clean)) return null;

    final key = clean.split(RegExp(r'\s+')).take(4).join(' ');

    if (_detailCache.containsKey(key)) return _detailCache[key];

    if (_backoff.blocked) return null;

    final res = await _httpGet('$_base?fen=${_fenParam(clean)}');

    if (res == null) {
      _backoff.failure();
      return null;
    }

    if (res.status == 429) {
      _backoff.rateLimited();
      return null;
    }

    if (res.status != 200) {
      _detailCache[key] = null;
      return null;
    }

    _backoff.success();

    try {
      final json = jsonDecode(res.body);

      if (json is! Map) return null;

      int? asInt(dynamic v) => v is num ? v.toInt() : null;

      final moves = <TablebaseMove>[];

      final raw = json['moves'];

      if (raw is List) {
        for (final m in raw) {
          if (m is! Map) continue;

          // category النقلة من منظور الخصم بعد تنفيذها.
          final opp = _categoryResult(m['category']?.toString());

          moves.add(
            TablebaseMove(
              uci: m['uci']?.toString() ?? '',
              san: m['san']?.toString() ?? '',
              result: opp == null ? null : -opp,
              dtz: asInt(m['dtz']),
              dtm: asInt(m['dtm']),
            ),
          );
        }
      }

      final detail = TablebaseDetail(
        result: _categoryResult(json['category']?.toString()),
        checkmate: json['checkmate'] == true,
        stalemate: json['stalemate'] == true,
        dtz: asInt(json['dtz']),
        dtm: asInt(json['dtm']),
        moves: moves,
      );

      if (_detailCache.length > 500) _detailCache.clear();

      _detailCache[key] = detail;

      return detail;
    } catch (_) {
      return null;
    }
  }

  /// النتيجة المضمونة من منظور الأبيض: 1 = فوز الأبيض، 0 = تعادل،
  /// -1 = فوز الأسود، null = غير معروفة (غير مؤهلة / فشل الاتصال /
  /// نتيجة غير حاسمة بسبب قاعدة الـ50 نقلة).
  ///
  /// "فوز مشروط بقاعدة 50 نقلة" (cursed-win) و"خسارة مشروطة"
  /// (blessed-loss) تُعامل كتعادل، لأن اللاعب لن يستطيع تحويلها فعليًا
  /// ضمن القاعدة.
  Future<int?> probeWhiteWdl(String fen) async {
    final clean = fen.trim();

    if (!isEligible(clean)) return null;

    final key = clean.split(RegExp(r'\s+')).take(2).join(' ');

    if (_cache.containsKey(key)) return _cache[key];

    if (_backoff.blocked) return null;

    final res = await _httpGet('$_base?fen=${_fenParam(clean)}');

    if (res == null) {
      _backoff.failure();
      return null;
    }

    if (res.status == 429) {
      _backoff.rateLimited();
      return null;
    }

    if (res.status != 200) {
      // 400/404: وضعية غير مدعومة — نخزّن null كي لا نعيد السؤال.
      _cache[key] = null;
      return null;
    }

    _backoff.success();

    int? result;

    try {
      final json = jsonDecode(res.body);

      if (json is Map) {
        result = whiteWdlFromCategory(
          json['category']?.toString(),
          clean,
        );
      }
    } catch (_) {
      result = null;
    }

    if (_cache.length > 2000) _cache.clear();

    _cache[key] = result;

    return result;
  }
}

/// نقلة من Tablebase، والنتيجة من منظور اللاعب الذي ينفّذها:
/// 1 = تحافظ على الفوز، 0 = تعادل، -1 = خسارة.
class TablebaseMove {
  final String uci;
  final String san;
  final int? result;
  final int? dtz;
  final int? dtm;

  const TablebaseMove({
    required this.uci,
    required this.san,
    required this.result,
    this.dtz,
    this.dtm,
  });
}

/// تفاصيل وضعية من Tablebase. [result] من منظور اللاعب الذي عليه
/// الدور (1 فوز، 0 تعادل، -1 خسارة، null غير معروفة).
class TablebaseDetail {
  final int? result;
  final bool checkmate;
  final bool stalemate;
  final int? dtz;
  final int? dtm;

  /// مرتبة من الأفضل إلى الأسوأ (كما يعيدها Lichess).
  final List<TablebaseMove> moves;

  const TablebaseDetail({
    required this.result,
    required this.checkmate,
    required this.stalemate,
    required this.dtz,
    required this.dtm,
    required this.moves,
  });
}

// ================================================================
// Opening Explorer
// ================================================================

/// إحصائيات نقلة واحدة من Opening Explorer.
class ExplorerMoveStat {
  final String uci;
  final String san;
  final int white;
  final int draws;
  final int black;

  const ExplorerMoveStat({
    required this.uci,
    required this.san,
    required this.white,
    required this.draws,
    required this.black,
  });

  int get total => white + draws + black;
}

/// إحصائيات وضعية من Opening Explorer (قاعدة واحدة).
class ExplorerPositionData {
  final int total;
  final List<ExplorerMoveStat> moves;

  const ExplorerPositionData(this.total, this.moves);

  int gamesFor(String normalizedSan) {
    for (final m in moves) {
      if (OpeningExplorerService.normalizeSan(m.san) == normalizedSan) {
        return m.total;
      }
    }

    return 0;
  }
}

/// ما نعرفه عن نقلة مُلعَبة في الافتتاح.
class BookMoveInfo {
  /// "كتاب": لُعبت في عدد كافٍ من مباريات الأساتذة.
  final bool isBook;

  /// عدد مباريات الأساتذة التي لُعبت فيها هذه النقلة / إجمالي مباريات
  /// الأساتذة في هذه الوضعية.
  final int mastersGames;
  final int mastersPositionGames;

  /// نفس الشيء لمباريات لاعبي Lichess (null = تعذّر الجلب).
  final int? lichessGames;
  final int? lichessPositionGames;

  const BookMoveInfo({
    required this.isBook,
    required this.mastersGames,
    required this.mastersPositionGames,
    this.lichessGames,
    this.lichessPositionGames,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'isBook': isBook,
        'mg': mastersGames,
        'mp': mastersPositionGames,
        'lg': lichessGames,
        'lp': lichessPositionGames,
      };

  static BookMoveInfo? fromJson(dynamic j) {
    if (j is! Map) return null;

    return BookMoveInfo(
      isBook: j['isBook'] == true,
      mastersGames: (j['mg'] as num?)?.toInt() ?? 0,
      mastersPositionGames: (j['mp'] as num?)?.toInt() ?? 0,
      lichessGames: (j['lg'] as num?)?.toInt(),
      lichessPositionGames: (j['lp'] as num?)?.toInt(),
    );
  }

  /// نسبة الأساتذة الذين لعبوا هذه النقلة في هذه الوضعية (0-100).
  double? get mastersPercent => mastersPositionGames > 0
      ? 100.0 * mastersGames / mastersPositionGames
      : null;

  /// نسبة لاعبي Lichess الذين لعبوا هذه النقلة (0-100).
  double? get lichessPercent {
    final total = lichessPositionGames;
    final games = lichessGames;

    if (total == null || games == null || total <= 0) return null;

    return 100.0 * games / total;
  }
}

class OpeningExplorerService {
  OpeningExplorerService._();

  static final OpeningExplorerService instance =
      OpeningExplorerService._();

  static const String _base = 'https://explorer.lichess.ovh';

  /// أقل عدد مباريات أساتذة لاعتبار النقلة "كتاب".
  static const int minMasterGames = 10;

  final Map<String, ExplorerPositionData?> _cache =
      <String, ExplorerPositionData?>{};

  final _Backoff _backoff = _Backoff();

  /// آخر سبب فشل (للتشخيص فقط): 'unauthorized' / 'rate-limited' /
  /// 'network' / null.
  String? lastError;

  static String normalizeSan(String san) =>
      san.replaceAll(RegExp(r'[+#!?]'), '').trim();

  Future<ExplorerPositionData?> _fetch(
    String db,
    String fen,
  ) async {
    final key = '$db|${fen.trim().split(RegExp(r'\s+')).take(4).join(' ')}';

    if (_cache.containsKey(key)) return _cache[key];

    if (_backoff.blocked) return null;

    final url = '$_base/$db?fen=${_fenParam(fen)}'
        '&moves=40&topGames=0&recentGames=0';

    final res = await _httpGet(
      url,
      bearer: LichessApiConfig.explorerToken,
    );

    if (res == null) {
      lastError = 'network';
      _backoff.failure();
      return null;
    }

    if (res.status == 401 || res.status == 403) {
      lastError = 'unauthorized';
      _backoff.rateLimited();
      return null;
    }

    if (res.status == 429) {
      lastError = 'rate-limited';
      _backoff.rateLimited();
      return null;
    }

    if (res.status != 200) {
      lastError = 'network';
      _backoff.failure();
      return null;
    }

    _backoff.success();
    lastError = null;

    try {
      final json = jsonDecode(res.body);

      if (json is! Map) return null;

      int n(dynamic v) => v is num ? v.toInt() : 0;

      final moves = <ExplorerMoveStat>[];

      final rawMoves = json['moves'];

      if (rawMoves is List) {
        for (final m in rawMoves) {
          if (m is! Map) continue;

          moves.add(
            ExplorerMoveStat(
              uci: m['uci']?.toString() ?? '',
              san: m['san']?.toString() ?? '',
              white: n(m['white']),
              draws: n(m['draws']),
              black: n(m['black']),
            ),
          );
        }
      }

      final position = ExplorerPositionData(
        n(json['white']) + n(json['draws']) + n(json['black']),
        moves,
      );

      if (_cache.length > 500) _cache.clear();

      _cache[key] = position;

      return position;
    } catch (_) {
      return null;
    }
  }

  /// إحصائيات الوضعية من مباريات الأساتذة (null = تعذّر الجلب).
  Future<ExplorerPositionData?> mastersStats(String fen) =>
      _fetch('masters', fen);

  /// إحصائيات الوضعية من مباريات لاعبي Lichess (null = تعذّر الجلب).
  Future<ExplorerPositionData?> lichessStats(String fen) =>
      _fetch('lichess', fen);

  /// يبحث عن النقلة [san] المُلعَبة من الوضعية [fenBefore] في قاعدتي
  /// الأساتذة وLichess. يعيد null إذا تعذّر جلب قاعدة الأساتذة (لا
  /// إنترنت / رفض صلاحية / 429) — وعندها يعود المستدعي للتقدير المحلي.
  Future<BookMoveInfo?> lookupBookMove({
    required String fenBefore,
    required String san,
  }) async {
    final results = await Future.wait<ExplorerPositionData?>([
      _fetch('masters', fenBefore),
      _fetch('lichess', fenBefore),
    ]);

    final masters = results[0];
    final lichess = results[1];

    // قرار "كتاب" يعتمد على قاعدة الأساتذة وحدها. إن فشلت نعيد null
    // ليعود المستدعي للتقدير المحلي بدل اعتبار كل النقلات "ليست كتابًا".
    if (masters == null) return null;

    final wanted = normalizeSan(san);

    final mastersGames = masters.gamesFor(wanted);

    return BookMoveInfo(
      isBook: mastersGames >= minMasterGames,
      mastersGames: mastersGames,
      mastersPositionGames: masters.total,
      lichessGames: lichess?.gamesFor(wanted),
      lichessPositionGames: lichess?.total,
    );
  }
}
