import 'dart:math' as math;

import 'package:flutter/material.dart';

/// تصنيف جودة النقلة، بنفس روح تصنيفات chess.com
/// (الخوارزمية الدقيقة لدى chess.com غير منشورة، هذا تقريب
/// عملي معتمد على فارق التقييم بوحدة القرن — centipawn loss).
enum MoveQuality {
  best,
  excellent,
  good,
  inaccuracy,
  mistake,
  blunder,
  miss,
}

class MoveQualityInfo {
  final String label;
  final Color color;
  final IconData icon;

  const MoveQualityInfo({
    required this.label,
    required this.color,
    required this.icon,
  });
}

const Map<MoveQuality, MoveQualityInfo> moveQualityInfo = {
  MoveQuality.best: MoveQualityInfo(
    label: 'الأفضل',
    color: Color(0xFF2AA876),
    icon: Icons.star_rounded,
  ),
  MoveQuality.excellent: MoveQualityInfo(
    label: 'ممتازة',
    color: Color(0xFF6AAE3E),
    icon: Icons.check_circle_rounded,
  ),
  MoveQuality.good: MoveQualityInfo(
    label: 'جيدة',
    color: Color(0xFF7FB3D5),
    icon: Icons.check_rounded,
  ),
  MoveQuality.inaccuracy: MoveQualityInfo(
    label: 'غير دقيقة',
    color: Color(0xFFE6B800),
    icon: Icons.help_rounded,
  ),
  MoveQuality.mistake: MoveQualityInfo(
    label: 'خطأ',
    color: Color(0xFFE8821A),
    icon: Icons.close_rounded,
  ),
  MoveQuality.blunder: MoveQualityInfo(
    label: 'خطأ فادح',
    color: Color(0xFFD9483D),
    icon: Icons.dangerous_rounded,
  ),
  MoveQuality.miss: MoveQualityInfo(
    label: 'فرصة ضائعة',
    color: Color(0xFFC1521B),
    icon: Icons.visibility_off_rounded,
  ),
};

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

/// يصنّف نقلة بناءً على:
/// - cpBeforeWhite: تقييم الوضعية قبل النقلة (منظور الأبيض)
/// - cpAfterWhite: تقييم الوضعية بعد النقلة (منظور الأبيض)
/// - color: من لعب النقلة ('w' أو 'b')
/// - wasBestMove: هل طابقت النقلة أفضل نقلة اقترحها المحرك
MoveQuality classifyMove({
  required int cpBeforeWhite,
  required int cpAfterWhite,
  required String color,
  required bool wasBestMove,
}) {
  final sign = color == 'w' ? 1 : -1;

  // منظور اللاعب الذي لعب النقلة: قبل = أفضل تقييم ممكن كان
  // متاحًا (لأنه ناتج تحليل المحرك لنفس الوضعية)، بعد = ما
  // آل إليه التقييم فعليًا بعد النقلة المُلعَبة.
  final beforeMover = cpBeforeWhite * sign;
  final afterMover = cpAfterWhite * sign;

  final loss = beforeMover - afterMover;

  // فرصة ضائعة: كانت الوضعية حاسمة لصالح اللاعب (فوز واضح أو
  // كش مات وشيك) وأضاعها بالكامل.
  if (beforeMover >= 400 && afterMover < 100) {
    return MoveQuality.miss;
  }

  if (wasBestMove || loss <= 0) {
    return MoveQuality.best;
  }

  if (loss <= 20) {
    return MoveQuality.excellent;
  }

  if (loss <= 50) {
    return MoveQuality.good;
  }

  if (loss <= 100) {
    return MoveQuality.inaccuracy;
  }

  if (loss <= 250) {
    return MoveQuality.mistake;
  }

  return MoveQuality.blunder;
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
