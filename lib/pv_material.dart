import 'package:chess/chess.dart' as ch;
import 'uci_utils.dart';

// ================================================================
// محاكاة المادة على خط Stockfish الرئيسي (PV)
//
// فكرة التضحية الحقيقية: نلعب النقلة ثم أول 4-6 نقلات من PV ونقيس
// المادة. إن بقي اللاعب خاسرًا للمادة في نهاية الخط (مع بقاء التقييم
// جيدًا) فهي تضحية فعلية. أما التبادلات التي تعود فيها المادة متساوية
// فليست تضحية.
// ================================================================

const Map<String, int> _fenValues = {
  'p': 1,
  'n': 3,
  'b': 3,
  'r': 5,
  'q': 9,
};

/// ميزان المادة (الأبيض - الأسود) من جزء توزيع القطع في FEN.
int materialBalanceWhite(String fen) {
  final placement = fen.trim().split(' ').first;

  var total = 0;

  for (final unit in placement.codeUnits) {
    final c = String.fromCharCode(unit);
    final lower = c.toLowerCase();
    final value = _fenValues[lower];

    if (value == null) continue;

    total += (c == lower) ? -value : value;
  }

  return total;
}

int _pieceCount(String fen) {
  final placement = fen.trim().split(' ').first;

  var count = 0;

  for (final unit in placement.codeUnits) {
    final isUpper = unit >= 65 && unit <= 90;
    final isLower = unit >= 97 && unit <= 122;

    if (isUpper || isLower) count++;
  }

  return count;
}

class PvMaterialResult {
  /// المادة التي خسرها لاعب النقلة مقارنةً ببداية الخط (موجب =
  /// تضحية بمادة، سالب = ربح مادة).
  final int deficit;

  /// عدد الأنصاف نقلات التي لُعبت فعلًا (النقلة نفسها + PV).
  final int pliesPlayed;

  /// هل انتهى الخط بنقلة هادئة (ليست أخذ قطعة)؟ إن لم يكن، فالمادة
  /// في نهايته قد تكون في منتصف تبادل ولا يُعتمد عليها.
  final bool quiet;

  const PvMaterialResult({
    required this.deficit,
    required this.pliesPlayed,
    required this.quiet,
  });
}

/// يلعب النقلة [from]→[to] من [fenBefore] ثم [pvAfterUci] (خط
/// Stockfish الرئيسي من الوضعية بعد النقلة) حتى [basePlies] نصف نقلة،
/// ويمدّه حتى [maxExtra] إضافية إن كان آخر نقلة أخذ قطعة (لإكمال
/// التبادل). يعيد null إن تعذّر تطبيق النقلة.
PvMaterialResult? simulatePvMaterial({
  required String fenBefore,
  required String from,
  required String to,
  String? promotion,
  required String moverColor,
  required List<String> pvAfterUci,
  int basePlies = 6,
  int maxExtra = 2,
}) {
  try {
    final game = ch.Chess();

    if (game.load(fenBefore) == false) return null;

    final sign = moverColor == 'w' ? 1 : -1;
    final start = sign * materialBalanceWhite(fenBefore);

    bool applyMove(String f, String t, String? promo) {
      final args = <String, dynamic>{'from': f, 'to': t};

      if (promo != null && promo.isNotEmpty) {
        args['promotion'] = promo.toLowerCase();
      }

      return game.move(args) != false;
    }

    var countBefore = _pieceCount(game.fen);

    if (!applyMove(from, to, promotion)) return null;

    var lastWasCapture = _pieceCount(game.fen) < countBefore;
    var played = 1;
    var idx = 0;

    final limit = basePlies + maxExtra;

    while (idx < pvAfterUci.length && played < limit) {
      // بعد الحد الأساسي نكمل فقط إذا كان التبادل لا يزال مفتوحًا.
      if (played >= basePlies && !lastWasCapture) break;

      final pvMove = parseUci(pvAfterUci[idx]);

      if (pvMove == null) break;

      countBefore = _pieceCount(game.fen);

      final ok = applyMove(
        pvMove.from,
        pvMove.to,
        pvMove.promotion,
      );

      if (!ok) break;

      lastWasCapture = _pieceCount(game.fen) < countBefore;
      played++;
      idx++;
    }

    final end = sign * materialBalanceWhite(game.fen);

    return PvMaterialResult(
      deficit: start - end,
      pliesPlayed: played,
      quiet: !lastWasCapture,
    );
  } catch (_) {
    return null;
  }
}
