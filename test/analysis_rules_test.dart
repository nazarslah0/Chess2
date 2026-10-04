import 'package:flutter_test/flutter_test.dart';

import 'package:chess_analyzer/analysis_result.dart';
import 'package:chess_analyzer/analysis_rules.dart';
import 'package:chess_analyzer/game_review_models.dart';

/// نقلة اصطناعية لاختبار القواعد. التقييمات بمنظور الأبيض.
MoveAnalysisResult mv(
  int ply, {
  required int beforeWhite,
  required int afterWhite,
  MoveQuality q = MoveQuality.good,
  String phase = 'middlegame',
  bool best = false,
  int? gap,
  int materialBefore = 30,
  int materialAfter = 30,
  int? tbBefore,
  int? tbAfter,
}) {
  final side = ply.isEven ? 'w' : 'b';
  final sign = side == 'w' ? 1 : -1;

  return MoveAnalysisResult(
    ply: ply,
    moveNumber: ply ~/ 2 + 1,
    side: side,
    san: 'x',
    uci: 'a2a3',
    fenBefore: 'f$ply',
    fenAfter: 'f${ply + 1}',
    evaluationBeforeCp: beforeWhite * sign,
    evaluationAfterCp: afterWhite * sign,
    evaluationLossCp: (beforeWhite - afterWhite) * sign,
    evaluationBeforeWhiteCp: beforeWhite,
    evaluationAfterWhiteCp: afterWhite,
    bestMoveSan: '',
    bestMoveUci: '',
    principalVariationUci: const [],
    classification: q,
    phase: phase,
    materialBefore: materialBefore,
    materialAfter: materialAfter,
    isCritical: false,
    isBestMove: best,
    isBrilliant: false,
    isMistake: q == MoveQuality.mistake,
    isBlunder: q == MoveQuality.blunder,
    isMissedOpportunity: q == MoveQuality.miss,
    bestMoveGapCp: gap,
    tablebaseWdlBeforeWhite: tbBefore,
    tablebaseWdlAfterWhite: tbAfter,
  );
}

void main() {
  group('ACPL: منظور اللاعب الذي نفّذ النقلة', () {
    test('خسارة الأبيض = هبوط تقييم الأبيض', () {
      expect(acplLossCp(mv(0, beforeWhite: 50, afterWhite: -50)), 100);
    });

    test('خسارة الأسود = ارتفاع تقييم الأبيض', () {
      expect(acplLossCp(mv(1, beforeWhite: 0, afterWhite: 80)), 80);
    });

    test('تحسّن اللاعب لا يُحتسب خسارة', () {
      expect(acplLossCp(mv(0, beforeWhite: 0, afterWhite: 60)), 0);
      expect(acplLossCp(mv(1, beforeWhite: 0, afterWhite: -60)), 0);
    });

    test('المات لا يفسد المتوسط: تقييد ±1000', () {
      // 0 → مات للخصم: الخسارة تُقيَّد بـ1000 وليست 100000.
      expect(
        acplLossCp(mv(0, beforeWhite: 0, afterWhite: -100000)),
        1000,
      );

      // أفضلية ضخمة قبل النقلة تُقيَّد أيضًا.
      expect(
        acplLossCp(mv(0, beforeWhite: 100000, afterWhite: 900)),
        100,
      );
    });

    test('computeAcpl: متوسط لكل لاعب مع تبدّل الدور', () {
      final moves = [
        mv(0, beforeWhite: 0, afterWhite: -100), // أبيض يخسر 100
        mv(1, beforeWhite: -100, afterWhite: -100), // أسود 0
        mv(2, beforeWhite: -100, afterWhite: -300), // أبيض 200
        mv(3, beforeWhite: -300, afterWhite: -200), // أسود يخسر 100
      ];

      final a = computeAcpl(moves);

      expect(a.white, 150); // (100 + 200) / 2
      expect(a.black, 50); // (0 + 100) / 2
      expect(a.forSide('w'), 150);
    });

    test('ACPL لكل مرحلة', () {
      final moves = [
        mv(0, beforeWhite: 0, afterWhite: -40, phase: 'opening'),
        mv(1, beforeWhite: -40, afterWhite: -40, phase: 'opening'),
        mv(2, beforeWhite: -40, afterWhite: -240, phase: 'middlegame'),
        mv(3, beforeWhite: -240, afterWhite: -240, phase: 'endgame'),
      ];

      final a = computeAcpl(moves);

      expect(a.byPhase['opening']!['w'], 40);
      expect(a.byPhase['middlegame']!['w'], 200);
      expect(a.byPhase['endgame']!['b'], 0);
      expect(a.byPhase['endgame']!['w'], isNull);
    });

    test('بدون نقلات => null', () {
      final a = computeAcpl(const []);

      expect(a.white, isNull);
      expect(a.black, isNull);
    });

    test('استثناء الكتاب اختياري', () {
      final moves = [
        mv(0,
            beforeWhite: 0,
            afterWhite: 0,
            q: MoveQuality.book),
        mv(2, beforeWhite: 0, afterWhite: -100),
      ];

      expect(computeAcpl(moves).white, 50);
      expect(computeAcpl(moves, excludeBook: true).white, 100);
    });
  });

  group('اللحظات الحرجة', () {
    test('خطأ فادح في وضعية متكافئة = لحظة حرجة (swing)', () {
      final moves = [
        mv(0,
            beforeWhite: 0,
            afterWhite: -400,
            q: MoveQuality.blunder),
      ];

      final c = detectCriticalMoments(moves);

      expect(c.length, 1);
      expect(c.single.kind, 'swing');
      expect(c.single.ply, 0);
    });

    test('ليس كل خطأ حرجًا: خطأ صغير لا يُعدّ', () {
      final moves = [
        mv(0,
            beforeWhite: 0,
            afterWhite: -110,
            q: MoveQuality.mistake),
      ];

      // خسارة ~10% < 15% => ليست حرجة.
      expect(detectCriticalMoments(moves), isEmpty);
    });

    test('وضعية محسومة أصلًا: لا لحظة حرجة', () {
      final moves = [
        mv(0,
            beforeWhite: -1500,
            afterWhite: -2500,
            q: MoveQuality.blunder),
      ];

      expect(detectCriticalMoments(moves), isEmpty);
    });

    test('غير الأخطاء بلا فجوة لا تُعدّ', () {
      final moves = [
        mv(0, beforeWhite: 0, afterWhite: 5, best: true),
      ];

      expect(detectCriticalMoments(moves), isEmpty);
    });

    test('نقلة وحيدة أُدّيت بدقة = حرجة (only_move)', () {
      final moves = [
        mv(0,
            beforeWhite: 0,
            afterWhite: 0,
            q: MoveQuality.best,
            best: true,
            gap: 300),
      ];

      final c = detectCriticalMoments(moves);

      expect(c.length, 1);
      expect(c.single.kind, 'only_move');
    });

    test('فجوة صغيرة لا تكفي لنقلة وحيدة', () {
      final moves = [
        mv(0,
            beforeWhite: 0,
            afterWhite: 0,
            q: MoveQuality.best,
            best: true,
            gap: 20),
      ];

      expect(detectCriticalMoments(moves), isEmpty);
    });

    test('تغيّر نتيجة Tablebase = حرجة (tablebase)', () {
      final moves = [
        mv(0,
            beforeWhite: 300,
            afterWhite: 0,
            q: MoveQuality.miss,
            tbBefore: 1,
            tbAfter: 0),
      ];

      final c = detectCriticalMoments(moves);

      expect(c.single.kind, 'tablebase');
    });

    test('Tablebase بلا تغيّر في النتيجة لا يجعلها حرجة', () {
      final moves = [
        mv(0,
            beforeWhite: 0,
            afterWhite: 0,
            tbBefore: 0,
            tbAfter: 0),
      ];

      expect(detectCriticalMoments(moves), isEmpty);
    });

    test('الافتتاح أقل وزنًا من الوسط', () {
      final mid = detectCriticalMoments([
        mv(0,
            beforeWhite: 0,
            afterWhite: -400,
            q: MoveQuality.blunder),
      ]).single.score;

      final opening = detectCriticalMoments([
        mv(0,
            beforeWhite: 0,
            afterWhite: -400,
            q: MoveQuality.blunder,
            phase: 'opening'),
      ]).single.score;

      expect(opening, lessThan(mid));
    });

    test('الترتيب تنازليًا حسب الدرجة، وmarkCriticalMoments تعلّم', () {
      final moves = [
        mv(0,
            beforeWhite: 0,
            afterWhite: -250,
            q: MoveQuality.mistake),
        mv(1,
            beforeWhite: -250,
            afterWhite: 150,
            q: MoveQuality.blunder),
        mv(2, beforeWhite: 150, afterWhite: 150),
      ];

      final c = detectCriticalMoments(moves);

      expect(c.length, greaterThanOrEqualTo(2));
      expect(c.first.score, greaterThanOrEqualTo(c.last.score));

      final marked = markCriticalMoments(moves);

      expect(marked[0].isCritical, isTrue);
      expect(marked[1].isCritical, isTrue);
      expect(marked[2].isCritical, isFalse);
      expect(marked[0].criticalKind, 'swing');
      expect(marked[0].criticalScore, greaterThan(0));
      // النتائج الأصلية لم تتغير (غير قابلة للتعديل).
      expect(moves[0].isCritical, isFalse);
    });
  });

  group('حكم Tablebase', () {
    String? v(String side, int? b, int? a) =>
        tablebaseVerdict(side: side, wdlBeforeWhite: b, wdlAfterWhite: a);

    test('Win → Loss = lostWin', () {
      expect(v('w', 1, -1), 'lostWin');
      expect(v('b', -1, 1), 'lostWin');
    });

    test('Win → Draw = missedWin', () {
      expect(v('w', 1, 0), 'missedWin');
      expect(v('b', -1, 0), 'missedWin');
    });

    test('Draw → Loss = blunder', () {
      expect(v('w', 0, -1), 'blunder');
      expect(v('b', 0, 1), 'blunder');
    });

    test('Draw → Win = gain', () {
      expect(v('w', 0, 1), 'gain');
      expect(v('b', 0, -1), 'gain');
    });

    test('النتيجة لم تتغير = best', () {
      expect(v('w', 1, 1), 'best');
      expect(v('w', 0, 0), 'best');
      expect(v('b', -1, -1), 'best');
    });

    test('بلا بيانات = null', () {
      expect(v('w', null, 0), isNull);
      expect(v('w', 0, null), isNull);
    });
  });
}
