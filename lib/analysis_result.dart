import 'game_review_models.dart';

/// نتيجة تحليل نقلة واحدة كاملة — نموذج مركزي يجمع كل ما
/// يحتاجه أي استهلاك لاحق لبيانات التحليل (تقرير المباراة،
/// الرسم البياني، ولاحقًا Personal Chess Coach) في مكان واحد،
/// بدل تفرّق البيانات بين مصفوفات متوازية.
///
/// ملاحظة صريحة عن حالة الدمج الحالية: شاشة GameAnalysisScreen
/// لا تزال تبني تحليلها داخليًا عبر مصفوفات متوازية (evalPawns،
/// bestUci، qualities...) لأسباب تتعلق بالأداء أثناء التنقل
/// الفوري بين النقلات (مصفوفات مفهرسة مباشرة أسرع من إعادة
/// بناء كائنات في كل ضغطة). هذا النموذج هو "منظور موحّد"
/// (view) يُبنى من تلك المصفوفات بعد اكتمال التحليل عبر
/// GameAnalysisScreenX._buildAnalysisResults()، لا بديل داخلي
/// كامل عنها بعد. إعادة هيكلة المصفوفات الداخلية بالكامل لتستخدم
/// هذا النموذج مباشرة خطوة لاحقة آمنة، لكنها لم تُنفَّذ الآن
/// لتفادي المخاطرة بكسر شاشة التحليل الحالية بلا بيئة Flutter
/// للتحقق.
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

  final String bestMoveSan;
  final String bestMoveUci;

  /// النقلات التالية المقترحة من المحرك (UCI) بدءًا من هذه
  /// الوضعية، إن توفرت.
  final List<String> principalVariationUci;

  final MoveQuality classification;
  final String phase; // opening / middlegame / endgame

  /// مجموع قيم القطع (بدون بيادق/ملوك) قبل/بعد النقلة — مؤشر
  /// خفيف على تغيّر المادة، وليس حساب مادة دقيقًا بالكامل.
  final int materialBefore;
  final int materialAfter;

  final bool isCritical;
  final bool isBestMove;
  final bool isBrilliant;
  final bool isMistake;
  final bool isBlunder;
  final bool isMissedOpportunity;

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
  });
}
