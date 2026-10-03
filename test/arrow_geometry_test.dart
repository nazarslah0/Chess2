import 'package:flutter_test/flutter_test.dart';

import 'package:chess_analyzer/board_geometry.dart';
import 'package:chess_analyzer/uci_utils.dart';

/// (col,row) للمربع المصدر والوجهة لنقلة UCI على رقعة معيّنة.
({({int col, int row}) from, ({int col, int row}) to}) arrowFor(
  String uci, {
  required bool flipped,
}) {
  final m = parseUci(uci)!;

  return (
    from: squareToGrid(m.from, flipped: flipped)!,
    to: squareToGrid(m.to, flipped: flipped)!,
  );
}

void main() {
  group('squareToGrid', () {
    test('الأبيض في الأسفل', () {
      expect(squareToGrid('a1'), (col: 0, row: 7));
      expect(squareToGrid('h1'), (col: 7, row: 7));
      expect(squareToGrid('a8'), (col: 0, row: 0));
      expect(squareToGrid('h8'), (col: 7, row: 0));
      expect(squareToGrid('e4'), (col: 4, row: 4));
    });

    test('الأسود في الأسفل (رقعة مقلوبة)', () {
      expect(squareToGrid('a1', flipped: true), (col: 7, row: 0));
      expect(squareToGrid('h8', flipped: true), (col: 0, row: 7));
      expect(squareToGrid('e4', flipped: true), (col: 3, row: 3));
    });

    test('مربع غير صالح', () {
      expect(squareToGrid(null), isNull);
      expect(squareToGrid('z9'), isNull);
      expect(squareToGrid('e'), isNull);
    });
  });

  group('السهم من UCI: المصدر ثم الوجهة', () {
    const cases = <String>[
      'e2e4',
      'g1f3',
      'e1g1',
      'e1c1',
      'e7e8q',
      'a7a8q',
    ];

    for (final uci in cases) {
      test('$uci — الأبيض في الأسفل', () {
        final a = arrowFor(uci, flipped: false);
        final m = parseUci(uci)!;

        expect(a.from, squareToGrid(m.from));
        expect(a.to, squareToGrid(m.to));
        expect(a.from, isNot(a.to));
      });

      test('$uci — الأسود في الأسفل', () {
        final a = arrowFor(uci, flipped: true);
        final m = parseUci(uci)!;

        expect(a.from, squareToGrid(m.from, flipped: true));
        expect(a.to, squareToGrid(m.to, flipped: true));
      });
    }

    test('e2e4: السهم يتجه للأعلى على رقعة الأبيض', () {
      final a = arrowFor('e2e4', flipped: false);

      expect(a.from.col, a.to.col);
      expect(a.to.row, lessThan(a.from.row)); // e4 أعلى من e2
    });

    test('e2e4: السهم يتجه للأسفل على الرقعة المقلوبة', () {
      final a = arrowFor('e2e4', flipped: true);

      expect(a.from.col, a.to.col);
      expect(a.to.row, greaterThan(a.from.row));
    });

    test('التبييت الصغير: الملك من e1 إلى g1 (يمينًا)', () {
      final a = arrowFor('e1g1', flipped: false);

      expect(a.from, (col: 4, row: 7));
      expect(a.to, (col: 6, row: 7));
    });

    test('التبييت الكبير: الملك من e1 إلى c1 (يسارًا)', () {
      final a = arrowFor('e1c1', flipped: false);

      expect(a.from, (col: 4, row: 7));
      expect(a.to, (col: 2, row: 7));
    });

    test('الترقية: السهم إلى مربع الترقية وليس ما بعده', () {
      final a = arrowFor('a7a8q', flipped: false);

      expect(a.from, (col: 0, row: 1));
      expect(a.to, (col: 0, row: 0));
    });
  });
}
