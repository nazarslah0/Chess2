import 'game_review_models.dart';
import 'lichess_data_service.dart' show BookMoveInfo;

/// إصدار بنية بيانات التحليل وخوارزمية التصنيف. ارفعه كلما تغيّرت
/// قواعد التصنيف أو تخطيط البيانات المحفوظة، فلا تُخلط النتائج
/// القديمة بالجديدة: مفتاح الكاش يتضمنه، وأي ملف محفوظ بإصدار آخر
/// يُتجاهل.
const int kAnalysisVersion = 2;

/// نسخة المحرك المسجَّلة مع التحليل.
const String kEngineVersion = 'stockfish19';

int? _asInt(dynamic v) => v is num ? v.toInt() : null;

double? _asDouble(dynamic v) => v is num ? v.toDouble() : null;

List<T> _list<T>(dynamic v, T Function(dynamic) f) =>
    v is List ? <T>[for (final e in v) f(e)] : <T>[];

MoveQuality _qualityFrom(dynamic v) {
  for (final q in MoveQuality.values) {
    if (q.name == v) return q;
  }

  return MoveQuality.good;
}

/// ناتج المحرك لوضعية واحدة (قبل أي نقلة أو بعدها). هذا هو "ما قاله
/// Stockfish" عن الوضعية، وهو مستقل عن النقلة التي لُعبت منها.
class PositionAnalysis {
  final String fen;

  /// بوحدة البيدق، من منظور الأبيض (±100 للمات).
  final double evalPawns;
  final String evalLabel;

  /// أفضل نقلة (UCI) وخط PV بدءًا من هذه الوضعية.
  final String bestUci;
  final List<String> pv;

  /// تقييم ثاني أفضل نقلة (قرن، منظور الأبيض) ونقلتها (UCI) إن
  /// توفرا (MultiPV = 2).
  final int? secondBestCpWhite;
  final String? secondBestUci;

  /// نتيجة Tablebase المضمونة (منظور الأبيض: 1 / 0 / -1) إن توفرت.
  final int? tbWdlWhite;

  const PositionAnalysis({
    required this.fen,
    required this.evalPawns,
    required this.evalLabel,
    required this.bestUci,
    required this.pv,
    this.secondBestCpWhite,
    this.secondBestUci,
    this.tbWdlWhite,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'fen': fen,
        'e': evalPawns,
        'l': evalLabel,
        'b': bestUci,
        'pv': pv,
        'sb': secondBestCpWhite,
        'sbu': secondBestUci,
        'tb': tbWdlWhite,
      };

  static PositionAnalysis fromJson(dynamic j) {
    final m = j as Map;

    return PositionAnalysis(
      fen: m['fen'].toString(),
      evalPawns: _asDouble(m['e']) ?? 0,
      evalLabel: m['l']?.toString() ?? '0.00',
      bestUci: m['b']?.toString() ?? '',
      pv: _list<String>(m['pv'], (e) => e.toString()),
      secondBestCpWhite: _asInt(m['sb']),
      secondBestUci: m['sbu']?.toString(),
      tbWdlWhite: _asInt(m['tb']),
    );
  }
}

/// نتيجة تحليل نقلة واحدة كاملة — المصدر الموحَّد لكل ما يُعرض عن
/// النقلة (قائمة النقلات، الرسم البياني، التقرير، الأسهم والعلامات).
///
/// التقييمات `evaluation*Cp` من منظور اللاعب الذي نفّذ النقلة، بينما
/// `evaluation*WhiteCp` من منظور الأبيض. كلاهما "فعّال": مصحَّح بنتيجة
/// Tablebase المضمونة إن وُجدت (انظر GameAnalysisController.cpAt).
class MoveAnalysisResult {
  final int ply;
  final int moveNumber;
  final String side; // 'w' أو 'b'
  final String san;
  final String uci;
  final String fenBefore;
  final String fenAfter;

  /// بالقرن، منظور اللاعب الذي يلعب (موجب = تحسّن).
  final int evaluationBeforeCp;
  final int evaluationAfterCp;
  final int evaluationLossCp;

  /// نفس التقييمين من منظور الأبيض.
  final int evaluationBeforeWhiteCp;
  final int evaluationAfterWhiteCp;

  final String bestMoveSan;
  final String bestMoveUci;

  /// النقلات التالية المقترحة من المحرك (UCI) بدءًا من هذه
  /// الوضعية، إن توفرت.
  final List<String> principalVariationUci;

  final MoveQuality classification;
  final String phase; // opening / middlegame / endgame

  /// مجموع قيم القطع (بدون بيادق/ملوك) قبل/بعد النقلة.
  final int materialBefore;
  final int materialAfter;

  final bool isCritical;
  final bool isBestMove;
  final bool isBrilliant;
  final bool isMistake;
  final bool isBlunder;
  final bool isMissedOpportunity;
  final bool isGreat;

  /// درجة حرجة النقلة ونوعها ('swing' / 'only_move' / 'tablebase')،
  /// يُحسبان بعد اكتمال التحليل (انظر analysis_rules.dart).
  final double criticalScore;
  final String? criticalKind;

  /// حكم Tablebase على النقلة: lostWin / missedWin / blunder / best /
  /// gain، أو null.
  final String? tablebaseVerdict;

  /// الفارق بين أفضل نقلة وثاني أفضل (قرن، منظور اللاعب).
  final int? bestMoveGapCp;

  /// نتيجة Tablebase المضمونة قبل/بعد النقلة (منظور الأبيض).
  final int? tablebaseWdlBeforeWhite;
  final int? tablebaseWdlAfterWhite;

  /// إحصائيات الكتاب (Opening Explorer).
  final BookMoveInfo? bookInfo;

  /// Maia: احتمال أن يجد لاعب بهذا التصنيف النقلة المُلعَبة / أفضل
  /// نقلة Stockfish، وأرجح نقلة عند Maia، وتصنيف Maia المستخدم.
  final double? maiaProbability;
  final double? maiaBestProbability;
  final String? maiaTopUci;
  final int? maiaBucket;

  const MoveAnalysisResult({
    required this.ply,
    required this.moveNumber,
    required this.side,
    required this.san,
    required this.uci,
    required this.fenBefore,
    required this.fenAfter,
    required this.evaluationBeforeCp,
    required this.evaluationAfterCp,
    required this.evaluationLossCp,
    required this.bestMoveSan,
    required this.bestMoveUci,
    required this.principalVariationUci,
    required this.classification,
    required this.phase,
    required this.materialBefore,
    required this.materialAfter,
    required this.isCritical,
    required this.isBestMove,
    required this.isBrilliant,
    required this.isMistake,
    required this.isBlunder,
    required this.isMissedOpportunity,
    this.isGreat = false,
    this.criticalScore = 0,
    this.criticalKind,
    this.tablebaseVerdict,
    this.evaluationBeforeWhiteCp = 0,
    this.evaluationAfterWhiteCp = 0,
    this.bestMoveGapCp,
    this.tablebaseWdlBeforeWhite,
    this.tablebaseWdlAfterWhite,
    this.bookInfo,
    this.maiaProbability,
    this.maiaBestProbability,
    this.maiaTopUci,
    this.maiaBucket,
  });

  MoveAnalysisResult copyWith({
    bool? isCritical,
    double? criticalScore,
    String? criticalKind,
  }) =>
      MoveAnalysisResult(
        ply: ply,
        moveNumber: moveNumber,
        side: side,
        san: san,
        uci: uci,
        fenBefore: fenBefore,
        fenAfter: fenAfter,
        evaluationBeforeCp: evaluationBeforeCp,
        evaluationAfterCp: evaluationAfterCp,
        evaluationLossCp: evaluationLossCp,
        evaluationBeforeWhiteCp: evaluationBeforeWhiteCp,
        evaluationAfterWhiteCp: evaluationAfterWhiteCp,
        bestMoveSan: bestMoveSan,
        bestMoveUci: bestMoveUci,
        principalVariationUci: principalVariationUci,
        classification: classification,
        phase: phase,
        materialBefore: materialBefore,
        materialAfter: materialAfter,
        isCritical: isCritical ?? this.isCritical,
        isBestMove: isBestMove,
        isBrilliant: isBrilliant,
        isMistake: isMistake,
        isBlunder: isBlunder,
        isMissedOpportunity: isMissedOpportunity,
        isGreat: isGreat,
        criticalScore: criticalScore ?? this.criticalScore,
        criticalKind: criticalKind ?? this.criticalKind,
        tablebaseVerdict: tablebaseVerdict,
        bestMoveGapCp: bestMoveGapCp,
        tablebaseWdlBeforeWhite: tablebaseWdlBeforeWhite,
        tablebaseWdlAfterWhite: tablebaseWdlAfterWhite,
        bookInfo: bookInfo,
        maiaProbability: maiaProbability,
        maiaBestProbability: maiaBestProbability,
        maiaTopUci: maiaTopUci,
        maiaBucket: maiaBucket,
      );

  /// نتيجة Tablebase بعد النقلة من منظور اللاعب الذي نفّذها:
  /// 'win' / 'draw' / 'loss'، أو null إن لم تتوفر.
  String? get tablebaseOutcomeForMover {
    final w = tablebaseWdlAfterWhite;

    if (w == null) return null;

    final v = side == 'w' ? w : -w;

    return v > 0 ? 'win' : (v < 0 ? 'loss' : 'draw');
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'ply': ply,
        'mn': moveNumber,
        'side': side,
        'san': san,
        'uci': uci,
        'fb': fenBefore,
        'fa': fenAfter,
        'eb': evaluationBeforeCp,
        'ea': evaluationAfterCp,
        'loss': evaluationLossCp,
        'ebw': evaluationBeforeWhiteCp,
        'eaw': evaluationAfterWhiteCp,
        'bsan': bestMoveSan,
        'buci': bestMoveUci,
        'pv': principalVariationUci,
        'q': classification.name,
        'phase': phase,
        'mb': materialBefore,
        'ma': materialAfter,
        'crit': isCritical,
        'best': isBestMove,
        'great': isGreat,
        'cs': criticalScore,
        'ck': criticalKind,
        'tbv': tablebaseVerdict,
        'gap': bestMoveGapCp,
        'tbb': tablebaseWdlBeforeWhite,
        'tba': tablebaseWdlAfterWhite,
        'book': bookInfo?.toJson(),
        'mp': maiaProbability,
        'mbp': maiaBestProbability,
        'mtop': maiaTopUci,
        'mbk': maiaBucket,
      };

  static MoveAnalysisResult fromJson(dynamic j) {
    final m = j as Map;

    final q = _qualityFrom(m['q']);

    return MoveAnalysisResult(
      ply: _asInt(m['ply']) ?? 0,
      moveNumber: _asInt(m['mn']) ?? 1,
      side: m['side']?.toString() ?? 'w',
      san: m['san']?.toString() ?? '',
      uci: m['uci']?.toString() ?? '',
      fenBefore: m['fb']?.toString() ?? '',
      fenAfter: m['fa']?.toString() ?? '',
      evaluationBeforeCp: _asInt(m['eb']) ?? 0,
      evaluationAfterCp: _asInt(m['ea']) ?? 0,
      evaluationLossCp: _asInt(m['loss']) ?? 0,
      evaluationBeforeWhiteCp: _asInt(m['ebw']) ?? 0,
      evaluationAfterWhiteCp: _asInt(m['eaw']) ?? 0,
      bestMoveSan: m['bsan']?.toString() ?? '',
      bestMoveUci: m['buci']?.toString() ?? '',
      principalVariationUci:
          _list<String>(m['pv'], (e) => e.toString()),
      classification: q,
      phase: m['phase']?.toString() ?? 'middlegame',
      materialBefore: _asInt(m['mb']) ?? 0,
      materialAfter: _asInt(m['ma']) ?? 0,
      isCritical: m['crit'] == true,
      isBestMove: m['best'] == true,
      isBrilliant: q == MoveQuality.brilliant,
      isMistake: q == MoveQuality.mistake,
      isBlunder: q == MoveQuality.blunder,
      isMissedOpportunity: q == MoveQuality.miss,
      isGreat: m['great'] == true || q == MoveQuality.great,
      criticalScore: _asDouble(m['cs']) ?? 0,
      criticalKind: m['ck']?.toString(),
      tablebaseVerdict: m['tbv']?.toString(),
      bestMoveGapCp: _asInt(m['gap']),
      tablebaseWdlBeforeWhite: _asInt(m['tbb']),
      tablebaseWdlAfterWhite: _asInt(m['tba']),
      bookInfo: BookMoveInfo.fromJson(m['book']),
      maiaProbability: _asDouble(m['mp']),
      maiaBestProbability: _asDouble(m['mbp']),
      maiaTopUci: m['mtop']?.toString(),
      maiaBucket: _asInt(m['mbk']),
    );
  }
}

/// بيانات المباراة المحفوظة مع تحليلها.
class SavedGame {
  final String pgn;
  final String white;
  final String black;
  final String result;
  final String date;

  const SavedGame({
    required this.pgn,
    required this.white,
    required this.black,
    required this.result,
    required this.date,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'pgn': pgn,
        'white': white,
        'black': black,
        'result': result,
        'date': date,
      };

  static SavedGame fromJson(dynamic j) {
    final m = j as Map;

    return SavedGame(
      pgn: m['pgn']?.toString() ?? '',
      white: m['white']?.toString() ?? '',
      black: m['black']?.toString() ?? '',
      result: m['result']?.toString() ?? '',
      date: m['date']?.toString() ?? '',
    );
  }
}

/// تحليل مباراة كاملة: وضعياتها (ناتج المحرك) ونقلاتها (التصنيف
/// وكل ما يخص النقلة). هذا هو الشكل الموحَّد الذي يُحفظ ويُحمَّل
/// ويقرؤه الجميع: مراجعة المباراة، التقرير، الرسم البياني، قائمة
/// النقلات، الرقعة والأسهم.
class GameAnalysis {
  final int analysisVersion;
  final String engineVersion;
  final int depth;
  final int multiPv;
  final String settingsKey;
  final int createdAt;

  /// n + 1 وضعية (الابتدائية + بعد كل نقلة).
  final List<PositionAnalysis> positions;

  /// n نقلة.
  final List<MoveAnalysisResult> moves;

  /// هل كان Opening Explorer متاحًا وقت التحليل (يحدد طريقة
  /// تصنيف "كتاب").
  final bool explorerAvailable;

  const GameAnalysis({
    required this.analysisVersion,
    required this.engineVersion,
    required this.depth,
    required this.multiPv,
    required this.settingsKey,
    required this.createdAt,
    required this.positions,
    required this.moves,
    required this.explorerAvailable,
  });

  bool get isConsistent => positions.length == moves.length + 1;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'v': analysisVersion,
        'engine': engineVersion,
        'depth': depth,
        'mpv': multiPv,
        'settings': settingsKey,
        'created': createdAt,
        'explorer': explorerAvailable,
        'positions': [for (final p in positions) p.toJson()],
        'moves': [for (final m in moves) m.toJson()],
      };

  static GameAnalysis fromJson(dynamic j) {
    final m = j as Map;

    return GameAnalysis(
      analysisVersion: _asInt(m['v']) ?? 0,
      engineVersion: m['engine']?.toString() ?? '',
      depth: _asInt(m['depth']) ?? 0,
      multiPv: _asInt(m['mpv']) ?? 1,
      settingsKey: m['settings']?.toString() ?? '',
      createdAt: _asInt(m['created']) ?? 0,
      explorerAvailable: m['explorer'] == true,
      positions: _list<PositionAnalysis>(
        m['positions'],
        PositionAnalysis.fromJson,
      ),
      moves: _list<MoveAnalysisResult>(
        m['moves'],
        MoveAnalysisResult.fromJson,
      ),
    );
  }
}
