import 'package:chess/chess.dart' as ch;
import 'package:flutter_test/flutter_test.dart';

import 'package:chess_analyzer/pgn_utils.dart';
import 'package:chess_analyzer/uci_utils.dart';

const String startFen =
    'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

void main() {
  group('PGN → نقلات → FEN', () {
    const pgn = '''
[Event "Test"]
[White "A"]
[Black "B"]
[Result "*"]

1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 *
''';

    test('عدد النقلات والألوان', () {
      final plies = parsePgnMoves(pgn)!;

      expect(plies.length, 6);
      expect(plies.map((p) => p.color).toList(),
          ['w', 'b', 'w', 'b', 'w', 'b']);
      expect(plies.map((p) => p.san).toList(),
          ['e4', 'e5', 'Nf3', 'Nc6', 'Bb5', 'a6']);
    });

    test('from/to صحيحة وتطابق UCI', () {
      final plies = parsePgnMoves(pgn)!;

      expect(plies[0].from, 'e2');
      expect(plies[0].to, 'e4');
      expect(plies[2].from, 'g1');
      expect(plies[2].to, 'f3');
      expect(parseUci('${plies[2].from}${plies[2].to}')!.uci, 'g1f3');
    });

    test('سلسلة FEN متصلة: fenAfter[i] == fenBefore[i+1]', () {
      final plies = parsePgnMoves(pgn)!;

      expect(plies.first.fenBefore, startFen);

      for (var i = 0; i < plies.length - 1; i++) {
        expect(plies[i].fenAfter, plies[i + 1].fenBefore);
      }
    });

    test('الـFEN الأخير يطابق اللعب اليدوي', () {
      final plies = parsePgnMoves(pgn)!;

      final game = ch.Chess();
      for (final san in ['e4', 'e5', 'Nf3', 'Nc6', 'Bb5', 'a6']) {
        game.move(san);
      }

      expect(plies.last.fenAfter, game.fen);
    });
  });

  group('PGN: حالات خاصة', () {
    test('تبييت صغير للأبيض ثم ترقية بالأخذ', () {
      const pgn = '''
[FEN "1r2k2r/P7/8/8/8/8/8/R3K2R w KQ - 0 1"]
[SetUp "1"]

1. O-O Kd7 2. axb8=N+ *
''';

      final plies = parsePgnMoves(pgn)!;

      expect(plies.length, 3);
      expect(plies[0].san, 'O-O');
      expect('${plies[0].from}${plies[0].to}', 'e1g1');
      expect(plies[2].promotion, 'n');
      expect(plies[2].isCapture, isTrue);
    });

    test('PGN غير قانوني يعيد null', () {
      expect(parsePgnMoves('1. e4 e4 *'), isNull);
    });

    test('PGN فارغ يعيد null', () {
      expect(parsePgnMoves(''), isNull);
    });
  });
}
