import 'package:chess/chess.dart' as ch;
import 'package:flutter_test/flutter_test.dart';

import 'package:chess_analyzer/models.dart';
import 'package:chess_analyzer/uci_utils.dart';

/// UCI → نقلة قانونية → رقعة → SAN.
({String san, String fen}) play(String fen, String uci) {
  final move = parseUci(uci)!;

  final game = ch.Chess();
  expect(game.load(fen), isNot(false), reason: 'FEN غير صالح');

  final legal = GameState.findLegalMove(
    game,
    move.from,
    move.to,
    move.promotion,
  );

  expect(legal, isNotNull, reason: '$uci ليست نقلة قانونية');

  final args = <String, dynamic>{'from': move.from, 'to': move.to};

  if (move.promotion != null) args['promotion'] = move.promotion;

  expect(game.move(args), isNot(false));

  return (san: legal!['san'].toString(), fen: game.fen);
}

String placement(String fen) => fen.split(' ').first;

void main() {
  const castleWhite = 'r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1';
  const castleBlack = 'r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 0 1';

  group('التبييت', () {
    test('e1g1 (أبيض صغير)', () {
      final r = play(castleWhite, 'e1g1');

      expect(r.san, 'O-O');
      expect(placement(r.fen), 'r3k2r/8/8/8/8/8/8/R4RK1');
    });

    test('e1c1 (أبيض كبير)', () {
      final r = play(castleWhite, 'e1c1');

      expect(r.san, 'O-O-O');
      expect(placement(r.fen), 'r3k2r/8/8/8/8/8/8/2KR3R');
    });

    test('e8g8 (أسود صغير)', () {
      final r = play(castleBlack, 'e8g8');

      expect(r.san, 'O-O');
      expect(placement(r.fen), 'r4rk1/8/8/8/8/8/8/R3K2R');
    });

    test('e8c8 (أسود كبير)', () {
      final r = play(castleBlack, 'e8c8');

      expect(r.san, 'O-O-O');
      expect(placement(r.fen), '2kr3r/8/8/8/8/8/8/R3K2R');
    });
  });

  group('الترقية', () {
    const fen = '4k3/P6P/8/8/8/8/8/4K3 w - - 0 1';

    for (final file in ['a', 'h']) {
      for (final piece in ['q', 'r', 'b', 'n']) {
        test('${file}7${file}8$piece', () {
          final r = play(fen, '${file}7${file}8$piece');

          expect(
            r.san.startsWith('${file}8=${piece.toUpperCase()}'),
            isTrue,
            reason: r.san,
          );

          // القطعة المرقّاة على مربع الترقية في الوضعية الناتجة.
          final rank8 = placement(r.fen).split('/').first;
          final expected = piece.toUpperCase();

          expect(rank8.contains(expected), isTrue, reason: rank8);
        });
      }
    }

    test('ترقية سوداء: a2a1n', () {
      final r = play('4k3/8/8/8/8/8/p6p/4K3 b - - 0 1', 'a2a1n');

      expect(r.san.startsWith('a1=N'), isTrue, reason: r.san);
    });
  });

  group('نقلة غير قانونية', () {
    test('findLegalMove يعيد null', () {
      final game = ch.Chess();

      expect(
        GameState.findLegalMove(game, 'e2', 'e5', null),
        isNull,
      );
    });
  });
}
