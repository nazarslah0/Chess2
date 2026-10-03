import 'package:chess/chess.dart' as ch;

import 'models.dart';
import 'uci_utils.dart';

/// يحوّل خط PV بصيغة UCI إلى SAN (حتى 6 نقلات) بدءًا من [fen].
/// يتوقف عند أول نقلة غير صالحة أو غير قانونية. المطابقة عبر
/// findLegalMove (from + to + promotion) فلا تختلط الترقيات.
String pvToSan(String fen, List<String> pvUci) {
  final game = ch.Chess();

  if (game.load(fen) == false) return '';

  final sanParts = <String>[];

  for (final uci in pvUci.take(6)) {
    final move = parseUci(uci);

    if (move == null) break;

    final matched = GameState.findLegalMove(
      game,
      move.from,
      move.to,
      move.promotion,
    );

    if (matched == null) break;

    final args = <String, dynamic>{
      'from': move.from,
      'to': move.to,
    };

    if (move.promotion != null) {
      args['promotion'] = move.promotion;
    }

    final san = (matched['san'] ?? '').toString();

    if (game.move(args) == false) break;

    sanParts.add(san.isEmpty ? '${move.from}${move.to}' : san);
  }

  return sanParts.join(' ');
}
