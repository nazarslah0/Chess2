import 'package:flutter_test/flutter_test.dart';

import 'package:chess_analyzer/game_review_models.dart';
import 'package:chess_analyzer/lichess_data_service.dart';

void main() {
  group('classifyMove (منظور الأبيض)', () {
    MoveQuality c(int before, int after, {bool best = false}) =>
        classifyMove(
          cpBeforeWhite: before,
          cpAfterWhite: after,
          color: 'w',
          wasBestMove: best,
        );

    test('Best: نقلة المحرك الأولى', () {
      expect(c(0, -300, best: true), MoveQuality.best);
    });

    test('Best: لا خسارة في احتمال الفوز', () {
      expect(c(0, 0), MoveQuality.best);
      expect(c(0, 50), MoveQuality.best);
    });

    test('Excellent', () => expect(c(0, -15), MoveQuality.excellent));
    test('Good', () => expect(c(0, -50), MoveQuality.good));
    test('Inaccuracy', () => expect(c(0, -100), MoveQuality.inaccuracy));
    test('Mistake', () => expect(c(0, -200), MoveQuality.mistake));
    test('Blunder', () => expect(c(0, -400), MoveQuality.blunder));

    test('Miss: فوز واضح ضاع بالكامل', () {
      expect(c(500, 50), MoveQuality.miss);
    });
  });

  group('classifyMove (منظور الأسود)', () {
    MoveQuality c(int before, int after) => classifyMove(
          cpBeforeWhite: before,
          cpAfterWhite: after,
          color: 'b',
          wasBestMove: false,
        );

    test('خسارة الأسود = ارتفاع تقييم الأبيض', () {
      expect(c(0, 15), MoveQuality.excellent);
      expect(c(0, 50), MoveQuality.good);
      expect(c(0, 100), MoveQuality.inaccuracy);
      expect(c(0, 200), MoveQuality.mistake);
      expect(c(0, 400), MoveQuality.blunder);
    });

    test('تحسّن تقييم الأسود => Best', () {
      expect(c(0, -100), MoveQuality.best);
    });

    test('Miss للأسود', () {
      expect(c(-500, -50), MoveQuality.miss);
    });
  });

  group('تصنيف: نقلة إجبارية، خاسر أصلًا، عتبات قابلة للضبط', () {
    test('نقلة إجبارية = best مهما كان التقييم', () {
      expect(
        classifyMove(
          cpBeforeWhite: 0,
          cpAfterWhite: -900,
          color: 'w',
          wasBestMove: false,
          onlyLegalMove: true,
        ),
        MoveQuality.best,
      );
    });

    test('وضعية خاسرة أصلًا: لا mistake/blunder', () {
      // -480 للأبيض: احتمال فوزه ~14.6% (خاسر أصلًا). النزول إلى
      // -1000 يخسر ~12% من احتمال الفوز = "خطأ" في وضعية متكافئة.
      final q = classifyMove(
        cpBeforeWhite: -480,
        cpAfterWhite: -1000,
        color: 'w',
        wasBestMove: false,
      );

      expect(q, MoveQuality.inaccuracy);

      // نفس الخسارة تقريبًا في وضعية أفضل تبقى خطأ.
      expect(
        classifyMove(
          cpBeforeWhite: 0,
          cpAfterWhite: -250,
          color: 'w',
          wasBestMove: false,
        ),
        MoveQuality.mistake,
      );
    });

    test('نفس الخسارة في وضعية متكافئة = خطأ فادح', () {
      expect(
        classifyMove(
          cpBeforeWhite: 0,
          cpAfterWhite: -500,
          color: 'w',
          wasBestMove: false,
        ),
        MoveQuality.blunder,
      );
    });

    test('العتبات قابلة للضبط دون تغيير الحساب', () {
      const strict = ClassificationThresholds(
        excellentMaxLoss: 0.5,
        goodMaxLoss: 1,
        inaccuracyMaxLoss: 2,
        mistakeMaxLoss: 4,
      );

      // خسارة ~4.59% في win%: good افتراضيًا، لكن mistake مع الصارمة؟
      // (> mistakeMaxLoss=4) => blunder.
      expect(
        classifyMove(
          cpBeforeWhite: 0,
          cpAfterWhite: -50,
          color: 'w',
          wasBestMove: false,
        ),
        MoveQuality.good,
      );

      expect(
        classifyMove(
          cpBeforeWhite: 0,
          cpAfterWhite: -50,
          color: 'w',
          wasBestMove: false,
          thresholds: strict,
        ),
        MoveQuality.blunder,
      );
    });
  });

  group('Brilliant: عدة شروط معًا', () {
    bool brilliant({
      MoveQuality q = MoveQuality.best,
      bool sacrifice = true,
      int cp = 0,
      bool only = false,
      String piece = 'N',
      int? gap = 120,
      bool recapture = false,
      bool tactical = false,
      bool holds = true,
    }) =>
        isBrilliantCandidate(
          baseQuality: q,
          isSacrifice: sacrifice,
          cpBeforeMover: cp,
          onlyLegalMove: only,
          movingPieceType: piece,
          secondBestGapCp: gap,
          isObviousRecapture: recapture,
          isTacticalIdea: tactical,
          positionHoldsAfter: holds,
        );

    test('تضحية + أفضل نقلة + فجوة كافية', () {
      expect(brilliant(), isTrue);
    });

    test('أفضل نقلة بدون تضحية ليست Brilliant', () {
      expect(brilliant(sacrifice: false), isFalse);
    });

    test('ليست أفضل نقلة', () {
      expect(brilliant(q: MoveQuality.good), isFalse);
    });

    test('نقلة إجبارية', () {
      expect(brilliant(only: true), isFalse);
    });

    test('استرداد بديهي', () {
      expect(brilliant(recapture: true), isFalse);
    });

    test('وضعية محسومة أصلًا', () {
      expect(brilliant(cp: 800), isFalse);
      expect(brilliant(cp: -800), isFalse);
    });

    test('الوضعية تنهار بعد النقلة', () {
      expect(brilliant(holds: false), isFalse);
    });

    test('فجوة صغيرة أو مجهولة', () {
      expect(brilliant(gap: 30), isFalse);
      expect(brilliant(gap: null), isFalse);
    });

    test('فكرة تكتيكية بلا تضحية تتطلب فجوة كبيرة جدًا', () {
      expect(brilliant(sacrifice: false, tactical: true, gap: 120), isFalse);
      expect(brilliant(sacrifice: false, tactical: true, gap: 200), isTrue);
    });

    test('البيدق والملك لا يكونان Brilliant', () {
      expect(brilliant(piece: 'P'), isFalse);
      expect(brilliant(piece: 'K'), isFalse);
    });
  });

  group('Tablebase: نتيجة مضمونة', () {
    MoveQuality tb(
      String color,
      int before,
      int after, {
      MoveQuality q = MoveQuality.best,
    }) =>
        applyTablebaseClassification(
          quality: q,
          color: color,
          wdlBeforeWhite: before,
          wdlAfterWhite: after,
        );

    test('Win → Draw = فرصة ضائعة', () {
      expect(tb('w', 1, 0), MoveQuality.miss);
      expect(tb('b', -1, 0), MoveQuality.miss);
    });

    test('Win → Loss = خطأ فادح', () {
      expect(tb('w', 1, -1), MoveQuality.blunder);
      expect(tb('b', -1, 1), MoveQuality.blunder);
    });

    test('Draw → Loss = خطأ فادح', () {
      expect(tb('w', 0, -1), MoveQuality.blunder);
      expect(tb('b', 0, 1), MoveQuality.blunder);
    });

    test('Draw → Win (خطأ الخصم) لا يُعاقَب', () {
      expect(tb('w', 0, 1), MoveQuality.best);
      expect(tb('b', 0, -1), MoveQuality.best);
    });

    test('النتيجة لم تتغير: لا mistake/blunder/miss', () {
      for (final q in [
        MoveQuality.mistake,
        MoveQuality.blunder,
        MoveQuality.miss,
      ]) {
        expect(tb('w', 1, 1, q: q), MoveQuality.inaccuracy);
        expect(tb('w', 0, 0, q: q), MoveQuality.inaccuracy);
        expect(tb('w', -1, -1, q: q), MoveQuality.inaccuracy);
      }
    });

    test('النتيجة لم تتغير: التصنيفات الجيدة تبقى', () {
      expect(tb('w', 1, 1, q: MoveQuality.good), MoveQuality.good);
      expect(tb('w', 1, 1, q: MoveQuality.best), MoveQuality.best);
    });
  });

  group('Tablebase: تحويل category إلى منظور الأبيض', () {
    const whiteToMove = '8/8/8/8/8/8/8/K6k w - - 0 1';
    const blackToMove = '8/8/8/8/8/8/8/K6k b - - 0 1';

    test('الأبيض صاحب الدور', () {
      expect(
        TablebaseService.whiteWdlFromCategory('win', whiteToMove),
        1,
      );
      expect(
        TablebaseService.whiteWdlFromCategory('draw', whiteToMove),
        0,
      );
      expect(
        TablebaseService.whiteWdlFromCategory('loss', whiteToMove),
        -1,
      );
    });

    test('الأسود صاحب الدور: تُعكس النتيجة', () {
      expect(
        TablebaseService.whiteWdlFromCategory('win', blackToMove),
        -1,
      );
      expect(
        TablebaseService.whiteWdlFromCategory('loss', blackToMove),
        1,
      );
      expect(
        TablebaseService.whiteWdlFromCategory('draw', blackToMove),
        0,
      );
    });

    test('فوز/خسارة مشروطة بقاعدة الـ50 نقلة = تعادل', () {
      expect(
        TablebaseService.whiteWdlFromCategory('cursed-win', whiteToMove),
        0,
      );
      expect(
        TablebaseService.whiteWdlFromCategory('blessed-loss', blackToMove),
        0,
      );
    });

    test('نتائج غير حاسمة => null', () {
      for (final cat in ['unknown', 'maybe-win', 'maybe-loss', null]) {
        expect(
          TablebaseService.whiteWdlFromCategory(cat, whiteToMove),
          isNull,
        );
      }
    });
  });

  group('Tablebase: أهلية الوضعية', () {
    test('7 قطع أو أقل بلا تبييت', () {
      expect(
        TablebaseService.isEligible('8/8/8/8/8/8/8/K6k w - - 0 1'),
        isTrue,
      );
    });

    test('أكثر من 7 قطع', () {
      expect(
        TablebaseService.isEligible(
          'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w - - 0 1',
        ),
        isFalse,
      );
    });

    test('حقوق التبييت تمنع الاستعلام', () {
      expect(
        TablebaseService.isEligible('4k3/8/8/8/8/8/8/R3K3 w Q - 0 1'),
        isFalse,
      );
    });
  });
}
