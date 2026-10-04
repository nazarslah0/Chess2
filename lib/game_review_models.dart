import 'dart:math' as math;

import 'package:flutter/material.dart';

/// تصنيف جودة النقلة، بنفس روح تصنيفات chess.com
/// (الخوارزمية الدقيقة لدى chess.com غير منشورة، هذا تقريب
/// عملي معتمد على الخسارة في احتمال الفوز).
enum MoveQuality {
  brilliant,
  great,
  best,
  excellent,
  good,
  book,
  inaccuracy,
  mistake,
  miss,
  blunder,
}

/// ترتيب عرض التصنيفات في صفحة الإحصائيات (كما في chess.com).
const List<MoveQuality> moveQualityDisplayOrder = [
  MoveQuality.brilliant,
  MoveQuality.great,
  MoveQuality.best,
  MoveQuality.excellent,
  MoveQuality.good,
  MoveQuality.book,
  MoveQuality.inaccuracy,
  MoveQuality.mistake,
  MoveQuality.miss,
  MoveQuality.blunder,
];

class MoveQualityInfo {
  final String label;
  final Color color;
  final IconData icon;

  /// رمز نصي يُرسم داخل دائرة العلامة (مثل !! أو ??). إن كان
  /// null تُستخدم [badgeIcon].
  final String? symbol;
  final IconData? badgeIcon;

  const MoveQualityInfo({
    required this.label,
    required this.color,
    required this.icon,
    this.symbol,
    this.badgeIcon,
  });
}

const Map<MoveQuality, MoveQualityInfo> moveQualityInfo = {
  MoveQuality.brilliant: MoveQualityInfo(
    label: 'مدهشة',
    color: Color(0xFF26C2A3),
    icon: Icons.auto_awesome_rounded,
    symbol: '!!',
  ),
  MoveQuality.great: MoveQualityInfo(
    label: 'رائعة',
    color: Color(0xFF5C8BB0),
    icon: Icons.priority_high_rounded,
    symbol: '!',
  ),
  MoveQuality.best: MoveQualityInfo(
    label: 'أفضل',
    color: Color(0xFF81B64C),
    icon: Icons.star_rounded,
    badgeIcon: Icons.star_rounded,
  ),
  MoveQuality.excellent: MoveQualityInfo(
    label: 'ممتاز',
    color: Color(0xFF96BC4B),
    icon: Icons.thumb_up_alt_rounded,
    badgeIcon: Icons.thumb_up_alt_rounded,
  ),
  MoveQuality.good: MoveQualityInfo(
    label: 'جيد',
    color: Color(0xFFA3B890),
    icon: Icons.check_rounded,
    badgeIcon: Icons.check_rounded,
  ),
  MoveQuality.book: MoveQualityInfo(
    label: 'كتاب',
    color: Color(0xFFA88865),
    icon: Icons.menu_book_rounded,
    badgeIcon: Icons.menu_book_rounded,
  ),
  MoveQuality.inaccuracy: MoveQualityInfo(
    label: 'غير دقيقة',
    color: Color(0xFFF7C631),
    icon: Icons.help_rounded,
    symbol: '?!',
  ),
  MoveQuality.mistake: MoveQualityInfo(
    label: 'خطأ',
    color: Color(0xFFE58F2A),
    icon: Icons.close_rounded,
    symbol: '?',
  ),
  MoveQuality.miss: MoveQualityInfo(
    label: 'فرصة ضائعة',
    color: Color(0xFFEE6055),
    icon: Icons.visibility_off_rounded,
    badgeIcon: Icons.close_rounded,
  ),
  MoveQuality.blunder: MoveQualityInfo(
    label: 'خطأ فادح',
    color: Color(0xFFCA3431),
    icon: Icons.dangerous_rounded,
    symbol: '??',
  ),
};

/// دائرة ملوّنة تحمل علامة جودة النقلة (!! ، ! ، نجمة ، ؟ ...)،
/// تُستخدم على زاوية القطعة في الرقعة وفي صفحة الإحصائيات.
class QualityBadge extends StatelessWidget {
  final MoveQuality quality;
  final double size;

  const QualityBadge({
    super.key,
    required this.quality,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final info = moveQualityInfo[quality]!;

    final Widget content = info.badgeIcon != null
        ? Icon(
            info.badgeIcon,
            color: Colors.white,
            size: size * 0.64,
          )
        : Padding(
            padding: EdgeInsets.all(size * 0.12),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                info.symbol ?? '',
                textDirection: TextDirection.ltr,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  height: 1,
                  fontSize: 100,
                ),
              ),
            ),
          );

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: info.color,
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: content,
    );
  }
}

/// eval بوحدة القرن (centipawns) من منظور الأبيض دائمًا.
/// الكش مات يُمثَّل بقيمة كبيرة موجبة/سالبة (فوز/خسارة أكيدة).
int cpFromWhitePerspective(
  double evalPawns,
  String evalLabel,
) {
  if (evalLabel.startsWith('M')) {
    return evalLabel.startsWith('M-')
        ? -100000
        : 100000;
  }

  return (evalPawns * 100).round();
}

/// عتبات تصنيف النقلات، منفصلة عن تقييم المحرك كي يمكن ضبطها
/// مستقبلًا دون المساس بالحساب. القيم الافتراضية قريبة من المنشور
/// عن chess.com: ممتاز ≤2% ، جيد ≤5% ، غير دقيقة ≤10% ، خطأ ≤20% ،
/// وما فوق ذلك خطأ فادح (كلها خسارة في احتمال الفوز %).
class ClassificationThresholds {
  final double excellentMaxLoss;
  final double goodMaxLoss;
  final double inaccuracyMaxLoss;
  final double mistakeMaxLoss;

  /// فرصة ضائعة: كان اللاعب أعلى من [missBeforeCp] ونزل تحت
  /// [missAfterCp].
  final int missBeforeCp;
  final int missAfterCp;

  /// وضعية "خاسرة أصلًا": احتمال فوز اللاعب قبل النقلة ≤ هذه القيمة.
  /// لا يُصنَّف فيها خطأ/خطأ فادح (بحد أقصى "غير دقيقة")، لأن كل
  /// النقلات تقريبًا سيئة بنفس القدر.
  final double alreadyLostWinPct;

  const ClassificationThresholds({
    this.excellentMaxLoss = 2,
    this.goodMaxLoss = 5,
    this.inaccuracyMaxLoss = 10,
    this.mistakeMaxLoss = 20,
    this.missBeforeCp = 400,
    this.missAfterCp = 100,
    this.alreadyLostWinPct = 15,
  });
}

const ClassificationThresholds kDefaultThresholds =
    ClassificationThresholds();

/// يصنّف نقلة بناءً على الخسارة في احتمال الفوز (win%) من منظور
/// اللاعب الذي لعبها — وليس على سنتيبون مجرّد، لأن خسارة 100
/// سنتيبون في وضعية متكافئة خطأ كبير، بينما في وضعية فائزة
/// بعشرة بيادق لا تغيّر شيئًا.
///
/// - cpBeforeWhite: تقييم الوضعية قبل النقلة (منظور الأبيض)
/// - cpAfterWhite: تقييم الوضعية بعد النقلة (منظور الأبيض)
/// - color: من لعب النقلة ('w' أو 'b')
/// - wasBestMove: هل طابقت النقلة أفضل نقلة اقترحها المحرك
/// - onlyLegalMove: النقلة الوحيدة القانونية (إجبارية) => best دائمًا
MoveQuality classifyMove({
  required int cpBeforeWhite,
  required int cpAfterWhite,
  required String color,
  required bool wasBestMove,
  bool onlyLegalMove = false,
  ClassificationThresholds thresholds = kDefaultThresholds,
}) {
  // نقلة إجبارية لا يمكن أن تكون خطأ.
  if (onlyLegalMove) {
    return MoveQuality.best;
  }

  final sign = color == 'w' ? 1 : -1;

  final beforeMover = cpBeforeWhite * sign;
  final afterMover = cpAfterWhite * sign;

  // فرصة ضائعة: كانت الوضعية حاسمة لصالح اللاعب (فوز واضح أو
  // كش مات وشيك) وأضاعها بالكامل.
  if (beforeMover >= thresholds.missBeforeCp &&
      afterMover < thresholds.missAfterCp) {
    return MoveQuality.miss;
  }

  final wpBefore = winPercentWhite(cpBeforeWhite);
  final wpAfter = winPercentWhite(cpAfterWhite);

  final winLoss = color == 'w'
      ? wpBefore - wpAfter
      : wpAfter - wpBefore;

  if (wasBestMove || winLoss <= 0) {
    return MoveQuality.best;
  }

  final moverWinBefore = color == 'w' ? wpBefore : 100 - wpBefore;

  MoveQuality q;

  if (winLoss <= thresholds.excellentMaxLoss) {
    q = MoveQuality.excellent;
  } else if (winLoss <= thresholds.goodMaxLoss) {
    q = MoveQuality.good;
  } else if (winLoss <= thresholds.inaccuracyMaxLoss) {
    q = MoveQuality.inaccuracy;
  } else if (winLoss <= thresholds.mistakeMaxLoss) {
    q = MoveQuality.mistake;
  } else {
    q = MoveQuality.blunder;
  }

  // خاسر أصلًا: لا نصنّف كل نقلة سيئة "خطأ فادح".
  if (moverWinBefore <= thresholds.alreadyLostWinPct &&
      (q == MoveQuality.mistake || q == MoveQuality.blunder)) {
    return MoveQuality.inaccuracy;
  }

  return q;
}

/// يطبّق نتيجة Tablebase المضمونة (من منظور الأبيض: 1 / 0 / -1)
/// على تصنيف النقلة:
///  - فوز ← تعادل: "فرصة ضائعة" (miss).
///  - فوز/تعادل ← خسارة: "خطأ فادح" (blunder).
///  - النتيجة لم تتغير: لا تُصنَّف النقلة miss/mistake/blunder مهما
///    بدا تقدير المحرك، بحد أقصى "غير دقيقة".
MoveQuality applyTablebaseClassification({
  required MoveQuality quality,
  required String color,
  required int wdlBeforeWhite,
  required int wdlAfterWhite,
}) {
  final sign = color == 'w' ? 1 : -1;

  final before = wdlBeforeWhite * sign;
  final after = wdlAfterWhite * sign;

  if (after < before) {
    if (after == -1) return MoveQuality.blunder;

    return MoveQuality.miss;
  }

  if (after == before &&
      (quality == MoveQuality.mistake ||
          quality == MoveQuality.blunder ||
          quality == MoveQuality.miss)) {
    return MoveQuality.inaccuracy;
  }

  return quality;
}

// ================================================================
// تقدير نسبة الدقة (Accuracy) بأسلوب قريب مما تعرضه chess.com،
// عبر تحويل التقييم إلى "احتمال فوز" ثم قياس الفارق بعد كل نقلة.
// هذه معادلة تقريبية معروفة (يستخدم مجتمع الشطرنج نسخة مشابهة
// منها) وليست خوارزمية chess.com الرسمية غير المنشورة.
// ================================================================

/// يحوّل تقييمًا بمنظور الأبيض (سنتيبون) إلى احتمال فوز الأبيض
/// (0-100).
double winPercentWhite(int cpWhite) {
  if (cpWhite >= 100000) return 100.0;
  if (cpWhite <= -100000) return 0.0;

  final capped = cpWhite.clamp(-1000, 1000);

  return 50 +
      50 *
          (2 /
                  (1 +
                      math.exp(
                        -0.00368208 * capped,
                      )) -
              1);
}

/// دقة نقلة واحدة (0-100) بناءً على احتمال الفوز قبل/بعد
/// النقلة من منظور اللاعب الذي لعبها.
double moveAccuracy({
  required double winPercentBeforeMover,
  required double winPercentAfterMover,
}) {
  final winLoss = (winPercentBeforeMover -
          winPercentAfterMover)
      .clamp(0, 100);

  final raw =
      103.1668 * math.exp(-0.04354 * winLoss) -
          3.1669;

  return raw.clamp(0, 100);
}

// ================================================================
// دقة المباراة — طريقة صارمة وعادلة
// ================================================================
//
// المتوسط الحسابي البسيط يخفي الأخطاء الكبيرة: خطأ فادح واحد
// بين 40 نقلة جيدة لا يكاد يغيّر المتوسط، فتظهر دقة عالية لا
// يستحقها اللاعب. لذلك نستخدم الطريقة المنشورة في Lichess:
//
//  1) دقة كل نقلة من الخسارة في احتمال الفوز (معادلة أعلاه).
//  2) متوسط مرجَّح بتقلّب الوضعية: النقلات في اللحظات الحادّة
//     التي يتأرجح فيها التقييم تزن أكثر من النقلات الهادئة.
//  3) متوسط توافقي (harmonic) يعاقب النقلات الضعيفة بشدة.
//  4) الدقة النهائية = معدّل (2) و(3).
//
// لا نضيف أي مكافأة للنقلات (لا "bonus") ولا نعطي دقة كاملة
// لنقلات الكتاب، فلا ترتفع النسبة إلا إذا كان اللعب جيدًا فعلًا.

class MoveAccuracyData {
  /// دقة كل نقلة (0-100).
  final List<double> accuracy;

  /// وزن كل نقلة حسب تقلّب الوضعية حولها.
  final List<double> weight;

  const MoveAccuracyData({
    required this.accuracy,
    required this.weight,
  });
}

double _stdDev(List<double> values) {
  if (values.isEmpty) return 0;

  final mean =
      values.reduce((a, b) => a + b) / values.length;

  var sum = 0.0;

  for (final v in values) {
    sum += (v - mean) * (v - mean);
  }

  return math.sqrt(sum / values.length);
}

/// [cpWhite] تقييمات الوضعيات (منظور الأبيض) بطول عدد النقلات + 1،
/// و[sides] لون من لعب كل نقلة ('w' أو 'b').
MoveAccuracyData computeMoveAccuracyData({
  required List<int> cpWhite,
  required List<String> sides,
}) {
  final n = sides.length;

  if (n == 0 || cpWhite.length < n + 1) {
    return const MoveAccuracyData(
      accuracy: <double>[],
      weight: <double>[],
    );
  }

  final wp = <double>[
    for (var i = 0; i <= n; i++) winPercentWhite(cpWhite[i]),
  ];

  final windowSize = (wp.length ~/ 10).clamp(2, 8);

  double w(List<double> window) =>
      _stdDev(window).clamp(0.5, 12.0).toDouble();

  final weights = <double>[];

  final firstWindow = wp.sublist(
    0,
    math.min(windowSize, wp.length),
  );

  for (var i = 0; i < windowSize - 2; i++) {
    weights.add(w(firstWindow));
  }

  for (var i = 0; i + windowSize <= wp.length; i++) {
    weights.add(w(wp.sublist(i, i + windowSize)));
  }

  while (weights.length < n) {
    weights.add(1.0);
  }

  final accuracy = <double>[];

  for (var i = 0; i < n; i++) {
    final white = sides[i] == 'w';

    final before = white ? wp[i] : 100 - wp[i];
    final after = white ? wp[i + 1] : 100 - wp[i + 1];

    accuracy.add(
      moveAccuracy(
        winPercentBeforeMover: before,
        winPercentAfterMover: after,
      ),
    );
  }

  return MoveAccuracyData(
    accuracy: accuracy,
    weight: weights.sublist(0, n),
  );
}

/// يجمع دقة مجموعة نقلات (لاعب واحد أو مرحلة) في رقم واحد.
double combineAccuracy(
  MoveAccuracyData data,
  Iterable<int> indices,
) {
  var weightedSum = 0.0;
  var weightTotal = 0.0;
  var inverseSum = 0.0;
  var count = 0;

  for (final i in indices) {
    if (i < 0 || i >= data.accuracy.length) continue;

    final acc = data.accuracy[i];
    final wt = data.weight[i];

    weightedSum += acc * wt;
    weightTotal += wt;

    // حدّ أدنى 1 لتفادي القسمة على صفر في النقلات الكارثية.
    inverseSum += 1.0 / math.max(acc, 1.0);

    count++;
  }

  if (count == 0 || weightTotal <= 0) return 0;

  final weighted = weightedSum / weightTotal;
  final harmonic = count / inverseSum;

  return ((weighted + harmonic) / 2).clamp(0.0, 100.0).toDouble();
}

// ================================================================
// كشف تقريبي لنقلات "رائعة!!" (Brilliant)
// ================================================================
//
// هذه ليست خوارزمية chess.com الرسمية (غير منشورة)، بل تقريب
// شائع لنفس الفكرة: النقلة هي أفضل نقلة حسب المحرك، وتبدو
// وكأنها تضحي بقطعة (الخصم يستطيع أكلها في الحال بربح مادي
// ظاهري)، لكن المحرك يؤكد أنها لا تزال الأفضل رغم ذلك — وأن
// الوضعية لم تكن فائزة أصلًا بشكل ساحق قبل النقلة.
const Map<String, int> pieceValues = {
  'P': 1,
  'N': 3,
  'B': 3,
  'R': 5,
  'Q': 9,
  'K': 0,
};

/// يقرر هل نرفع تصنيف نقلة (أُثبتت أصلًا كأفضل نقلة) إلى
/// "رائعة!!" بناءً على وجود تضحية حقيقية وظروف مناسبة.
bool isBrilliantCandidate({
  required MoveQuality baseQuality,
  required bool isSacrifice,
  required int cpBeforeMover,
  required bool onlyLegalMove,
  required String movingPieceType, // 'P','N','B','R','Q','K'
  // الفارق بالقرن بين أفضل نقلة وثاني أفضل نقلة (منظور
  // اللاعب الذي يلعب). null يعني أن البيانات غير متوفرة
  // (مثلاً multiPV لم يُرجع خطًا ثانيًا) — في هذه الحالة لا
  // نصنّف "رائعة" أبدًا، تماشيًا مع: "إذا لم تكن البيانات
  // كافية، لا تصنف النقلة Brilliant".
  required int? secondBestGapCp,
  // نقلة أخذ مباشر لقطعة أُخذت للتو (استرداد بديهي): لا تُعدّ
  // رائعة مهما كان.
  bool isObviousRecapture = false,
  // نقلة هادئة بفكرة تكتيكية واضحة (يربح اللاعب مادة بالقوة في خط
  // المحرك) كبديل عن التضحية.
  bool isTacticalIdea = false,
  // بعد النقلة: هل ما زال اللاعب في وضع جيد (ليس خاسرًا)؟
  bool positionHoldsAfter = true,
}) {
  if (baseQuality != MoveQuality.best) {
    return false;
  }

  if (onlyLegalMove || isObviousRecapture) {
    return false;
  }

  if (movingPieceType == 'K') {
    return false;
  }

  // وضعية محسومة أصلًا (فوز مضمون تقريبًا أو خسارة): لا قيمة
  // لـ"رائعة" فيها.
  if (cpBeforeMover.abs() >= 600) {
    return false;
  }

  if (!positionHoldsAfter) {
    return false;
  }

  // لا بيانات كافية عن ثاني أفضل نقلة => لا تصنيف Brilliant.
  if (secondBestGapCp == null) {
    return false;
  }

  if (isSacrifice) {
    // يجب أن تكون هذه النقلة أفضل بوضوح من البديل التالي — أي أنها
    // لم تكن مجرد واحدة من عدة خيارات متكافئة، بل الحل الوحيد
    // القوي فعلًا في هذه الوضعية.
    return secondBestGapCp >= 80 &&
        movingPieceType != 'P';
  }

  // بدون تضحية: تُقبل فقط فكرة تكتيكية واضحة بفارق كبير جدًا عن
  // البديل التالي.
  if (isTacticalIdea) {
    return secondBestGapCp >= 150 && movingPieceType != 'P';
  }

  return false;
}


/// "رائعة!" (Great): أفضل نقلة، وفي وضعية لم تُحسم بعد، وأفضل
/// بوضوح من البديل التالي (النقلة القوية الوحيدة تقريبًا)، وليست
/// النقلة القانونية الوحيدة. عند غياب بيانات ثاني أفضل نقلة لا
/// نصنّف "رائعة" أبدًا.
bool isGreatCandidate({
  required int cpBeforeWhite,
  required int? secondBestCpWhite,
  required String color,
  required bool onlyLegalMove,
}) {
  if (onlyLegalMove || secondBestCpWhite == null) {
    return false;
  }

  final wpBest = winPercentWhite(cpBeforeWhite);
  final wpSecond = winPercentWhite(secondBestCpWhite);

  final moverBest = color == 'w' ? wpBest : 100 - wpBest;
  final moverSecond = color == 'w' ? wpSecond : 100 - wpSecond;

  // وضعية محسومة (فائزة أو خاسرة بالكامل): لا معنى لـ"الوحيدة".
  if (moverBest < 8 || moverBest > 92) {
    return false;
  }

  return (moverBest - moverSecond) >= 15;
}
