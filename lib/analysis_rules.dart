import 'analysis_result.dart';
import 'game_review_models.dart';

// ================================================================
// قواعد التحليل النقية (بلا Flutter ولا شبكة): ACPL، اللحظات
// الحرجة، وحكم Tablebase. تعمل على List<MoveAnalysisResult> فقط،
// فتُختبر مباشرة وتستعملها الواجهة والتقرير بدل تكرار الحسابات.
// ================================================================

/// حد التقييم قبل حساب الخسارة (±1000 قرن)، كما تفعل Lichess، كي
/// لا يُفسد المات أو الأفضلية الضخمة متوسط ACPL.
const int kAcplEvalClampCp = 1000;

/// أقصى خسارة تُحسب لنقلة واحدة في ACPL.
const int kAcplMoveCapCp = 1000;

int _clamp(int cp) =>
    cp.clamp(-kAcplEvalClampCp, kAcplEvalClampCp);

/// خسارة النقلة بالقرن لـACPL: من منظور اللاعب الذي نفّذها
/// (لذلك تصح عند تبدّل الدور)، بعد تقييد التقييمين.
///
///   mover = +1 للأبيض، -1 للأسود
///   loss  = max(0, clamp(before*mover) - clamp(after*mover))
int acplLossCp(MoveAnalysisResult m) {
  final sign = m.side == 'w' ? 1 : -1;

  final before = _clamp(m.evaluationBeforeWhiteCp) * sign;
  final after = _clamp(m.evaluationAfterWhiteCp) * sign;

  return (before - after).clamp(0, kAcplMoveCapCp);
}

class AcplStats {
  /// بالقرن. null = لا نقلات.
  final double? white;
  final double? black;

  /// المرحلة ('opening' / 'middlegame' / 'endgame') ← {'w','b'}.
  final Map<String, Map<String, double?>> byPhase;

  const AcplStats({
    required this.white,
    required this.black,
    required this.byPhase,
  });

  double? forSide(String side) => side == 'w' ? white : black;
}

/// Average Centipawn Loss لكل لاعب ولكل مرحلة.
///
/// منظور التقييم: كل خسارة تُحسب من منظور اللاعب الذي نفّذ النقلة
/// (انظر [acplLossCp])، فلا يتأثر الحساب بتبدّل الدور بين الأبيض
/// والأسود.
AcplStats computeAcpl(
  List<MoveAnalysisResult> moves, {
  /// استثناء نقلات الكتاب (تضخّم الدقة ولا تعبّر عن قدرة اللاعب).
  bool excludeBook = false,
}) {
  final sum = <String, double>{'w': 0, 'b': 0};
  final n = <String, int>{'w': 0, 'b': 0};

  const phases = <String>['opening', 'middlegame', 'endgame'];

  final pSum = <String, Map<String, double>>{
    for (final p in phases) p: <String, double>{'w': 0, 'b': 0},
  };
  final pN = <String, Map<String, int>>{
    for (final p in phases) p: <String, int>{'w': 0, 'b': 0},
  };

  for (final m in moves) {
    if (excludeBook && m.classification == MoveQuality.book) continue;

    final loss = acplLossCp(m).toDouble();

    sum[m.side] = sum[m.side]! + loss;
    n[m.side] = n[m.side]! + 1;

    final p = pSum.containsKey(m.phase) ? m.phase : 'middlegame';

    pSum[p]![m.side] = pSum[p]![m.side]! + loss;
    pN[p]![m.side] = pN[p]![m.side]! + 1;
  }

  double? avg(double s, int c) => c > 0 ? s / c : null;

  return AcplStats(
    white: avg(sum['w']!, n['w']!),
    black: avg(sum['b']!, n['b']!),
    byPhase: {
      for (final p in phases)
        p: {
          'w': avg(pSum[p]!['w']!, pN[p]!['w']!),
          'b': avg(pSum[p]!['b']!, pN[p]!['b']!),
        },
    },
  );
}

// ================================================================
// اللحظات الحرجة
// ================================================================

/// إعدادات اكتشاف اللحظات الحرجة (قابلة للضبط).
class CriticalMomentConfig {
  /// أدنى درجة لاعتبار النقلة لحظة حرجة.
  final double minScore;

  /// أدنى خسارة في احتمال الفوز (%) لتُعدّ الخسارة تحوّلًا حاسمًا.
  final double minSwingPct;

  /// أدنى فارق (%) بين أفضل نقلة وثاني أفضل لتُعدّ "النقلة الوحيدة".
  final double minOnlyMovePct;

  /// وزن النقلات في الافتتاح (أقل أهمية).
  final double openingWeight;

  /// وضعية محسومة أصلًا: احتمال الفوز خارج [decidedBelow..decidedAbove]
  /// لا تُعدّ نقلاتها حرجة.
  final double decidedBelow;
  final double decidedAbove;

  const CriticalMomentConfig({
    this.minScore = 15,
    this.minSwingPct = 15,
    this.minOnlyMovePct = 15,
    this.openingWeight = 0.6,
    this.decidedBelow = 8,
    this.decidedAbove = 92,
  });
}

class CriticalMoment {
  final int ply;
  final double score;

  /// 'swing' (تحوّل حاسم بخطأ) / 'only_move' (نقلة وحيدة أُدّيت
  /// بدقة) / 'tablebase' (تغيّر النتيجة المضمونة).
  final String kind;

  const CriticalMoment({
    required this.ply,
    required this.score,
    required this.kind,
  });
}

double _moverWinPct(int whiteCp, String side) {
  final w = winPercentWhite(whiteCp);

  return side == 'w' ? w : 100 - w;
}

/// يكتشف اللحظات الحرجة اعتمادًا على عدة عوامل معًا:
///  - خسارة احتمال الفوز (التحوّل في التقييم)،
///  - الفارق بين أفضل نقلة وثانيها ("النقلة الوحيدة")،
///  - شدة الخطأ (تصنيف النقلة)،
///  - أهمية تكتيكية (تغيّر المادة)،
///  - مرحلة اللعبة،
///  - هل الوضعية محسومة أصلًا،
///  - تغيّر نتيجة Tablebase المضمونة.
///
/// ليست كل نقلة "خطأ" حرجة تلقائيًا: يلزم تحوّل حاسم في وضعية لم
/// تُحسم بعد، أو نقلة وحيدة، أو تغيّر في النتيجة المضمونة.
List<CriticalMoment> detectCriticalMoments(
  List<MoveAnalysisResult> moves, {
  CriticalMomentConfig config = const CriticalMomentConfig(),
}) {
  final out = <CriticalMoment>[];

  for (final m in moves) {
    final before = _moverWinPct(m.evaluationBeforeWhiteCp, m.side);
    final after = _moverWinPct(m.evaluationAfterWhiteCp, m.side);

    final loss = before - after; // خسارة اللاعب (موجب = خسر)

    // وزن "الوضعية لم تُحسم": 1 داخل النطاق، ويتناقص إلى 0 عند
    // الاقتراب من 0% أو 100%.
    double undecided;

    if (before <= config.decidedBelow ||
        before >= config.decidedAbove) {
      undecided = 0;
    } else {
      undecided = 1;
    }

    final phaseW = m.phase == 'opening' ? config.openingWeight : 1.0;

    // ---------- Tablebase ----------
    final tbB = m.tablebaseWdlBeforeWhite;
    final tbA = m.tablebaseWdlAfterWhite;

    if (tbB != null && tbA != null) {
      final s = m.side == 'w' ? 1 : -1;

      if (tbA * s != tbB * s) {
        out.add(
          CriticalMoment(
            ply: m.ply,
            score: 40 + (tbA * s < tbB * s ? 10 : 0),
            kind: 'tablebase',
          ),
        );

        continue;
      }
    }

    if (undecided == 0) continue;

    // ---------- تحوّل حاسم بخطأ ----------
    final isError = m.classification == MoveQuality.mistake ||
        m.classification == MoveQuality.blunder ||
        m.classification == MoveQuality.miss;

    double swingScore = 0;

    if (isError && loss >= config.minSwingPct) {
      swingScore = loss;

      // أهمية تكتيكية: تغيّر مادة غير البيادق.
      final materialShift =
          (m.materialAfter - m.materialBefore).abs();

      if (materialShift >= 3) swingScore += 5;

      swingScore *= phaseW;
    }

    // ---------- نقلة وحيدة أُدّيت بدقة ----------
    double onlyMoveScore = 0;

    final gap = m.bestMoveGapCp;

    if (gap != null && m.isBestMove && !isError) {
      final sign = m.side == 'w' ? 1 : -1;

      final bestCp = m.evaluationBeforeWhiteCp * sign;

      final wpBest = _moverWinPct(bestCp * sign, m.side);
      final wpSecond = _moverWinPct((bestCp - gap) * sign, m.side);

      final onlyMove = wpBest - wpSecond;

      if (onlyMove >= config.minOnlyMovePct) {
        onlyMoveScore = onlyMove * 0.8 * phaseW;
      }
    }

    if (swingScore >= config.minScore &&
        swingScore >= onlyMoveScore) {
      out.add(
        CriticalMoment(ply: m.ply, score: swingScore, kind: 'swing'),
      );
    } else if (onlyMoveScore >= config.minScore) {
      out.add(
        CriticalMoment(
          ply: m.ply,
          score: onlyMoveScore,
          kind: 'only_move',
        ),
      );
    }
  }

  out.sort((a, b) => b.score.compareTo(a.score));

  return out;
}

/// يعيد قائمة النتائج نفسها مع تعبئة isCritical / criticalScore /
/// criticalKind.
List<MoveAnalysisResult> markCriticalMoments(
  List<MoveAnalysisResult> moves, {
  CriticalMomentConfig config = const CriticalMomentConfig(),
}) {
  final byPly = <int, CriticalMoment>{
    for (final c in detectCriticalMoments(moves, config: config))
      c.ply: c,
  };

  return <MoveAnalysisResult>[
    for (final m in moves)
      byPly.containsKey(m.ply)
          ? m.copyWith(
              isCritical: true,
              criticalScore: byPly[m.ply]!.score,
              criticalKind: byPly[m.ply]!.kind,
            )
          : m.copyWith(isCritical: false),
  ];
}

// ================================================================
// حكم Tablebase
// ================================================================

/// حكم Tablebase على النقلة (من منظور اللاعب الذي نفّذها). قيم نصية
/// ثابتة تُحفظ في JSON:
///  - 'lostWin'   فوز → خسارة
///  - 'missedWin' فوز → تعادل
///  - 'blunder'   تعادل → خسارة
///  - 'best'      النتيجة المضمونة لم تتغير (نقلة Tablebase جيدة)
///  - 'gain'      تحسّنت النتيجة (خطأ الخصم السابق)
///  - null        لا بيانات
String? tablebaseVerdict({
  required String side,
  required int? wdlBeforeWhite,
  required int? wdlAfterWhite,
}) {
  if (wdlBeforeWhite == null || wdlAfterWhite == null) return null;

  final s = side == 'w' ? 1 : -1;

  final before = wdlBeforeWhite * s;
  final after = wdlAfterWhite * s;

  if (after == before) return 'best';

  if (after > before) return 'gain';

  if (before == 1 && after == -1) return 'lostWin';

  if (before == 1 && after == 0) return 'missedWin';

  return 'blunder'; // تعادل → خسارة
}
