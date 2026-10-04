import 'package:chess/chess.dart' as ch;

/// نتيجة فحص خط تضحية: نلعب النقلة ثم نتابع الخط (أفضل لعب للمحرك أو
/// ما حدث فعليًا في المباراة) ونقيس المادة من منظور اللاعب.
class SacrificeLineResult {
  /// المادة (بيادق=1، حصان/فيل=3، رخ=5، وزير=9) من منظور اللاعب قبل
  /// النقلة.
  final int baseBalance;

  /// أدنى رصيد مادي وصل إليه اللاعب خلال أول [sacrificeWindow] نقلات.
  final int minBalance;

  /// الرصيد المادي في نهاية الخط (عند أول وضعية هادئة).
  final int finalBalance;

  /// هل انتهى الخط بمات للاعب؟
  final bool mate;

  /// عدد الأنصاف نقلات المُحاكاة فعليًا (يشمل النقلة المُلعَبة).
  final int pliesSimulated;

  const SacrificeLineResult({
    required this.baseBalance,
    required this.minBalance,
    required this.finalBalance,
    required this.mate,
    required this.pliesSimulated,
  });

  /// أكبر عجز مادي مرّ به اللاعب (>= 2 يعني تضحية بقطعة أو أكثر
  /// فعلًا، لا مجرد بيدق).
  int get maxDeficit => baseBalance - minBalance;

  /// الربح/الخسارة الصافية في نهاية الخط مقارنة ببداية النقلة.
  int get netGain => finalBalance - baseBalance;

  /// تضحية حقيقية: خسر اللاعب (مؤقتًا) ما يعادل حصانًا/فيلًا أو أكثر
  /// مقابل بيدق على الأقل.
  bool get isSacrifice => maxDeficit >= 2;

  /// استرجع المادة مع زيادة (أو انتهى الخط بمات).
  bool get recoveredWithSurplus => isSacrifice && (mate || netGain >= 1);
}

const Map<String, int> _kValues = <String, int>{
  'p': 1,
  'n': 3,
  'b': 3,
  'r': 5,
  'q': 9,
};

/// رصيد المادة من منظور [moverColor] ('w' أو 'b') لوضعية FEN.
int materialBalanceFromFen(String fen, String moverColor) {
  final board = fen.split(' ').first;

  var white = 0;
  var black = 0;

  for (final unit in board.codeUnits) {
    final c = String.fromCharCode(unit);
    final lower = c.toLowerCase();
    final v = _kValues[lower];

    if (v == null) continue;

    if (c == lower) {
      black += v;
    } else {
      white += v;
    }
  }

  return moverColor == 'w' ? white - black : black - white;
}

bool _isCheckmate(ch.Chess g) {
  try {
    return (g as dynamic).in_checkmate == true;
  } catch (_) {}

  try {
    return (g as dynamic).inCheckmate == true;
  } catch (_) {}

  return false;
}

Map<String, String>? _uciToMoveMap(String uci) {
  final u = uci.trim().toLowerCase();

  if (u.length < 4) return null;

  final from = u.substring(0, 2);
  final to = u.substring(2, 4);

  final ok = RegExp(r'^[a-h][1-8]$');

  if (!ok.hasMatch(from) || !ok.hasMatch(to)) return null;

  final m = <String, String>{'from': from, 'to': to};

  if (u.length >= 5) m['promotion'] = u.substring(4, 5);

  return m;
}

/// يلعب [lineUci] (أول عنصر = نقلة اللاعب نفسها، ثم الرد، وهكذا) من
/// [fenBefore] ويحسب المادة.
///
/// - [sacrificeWindow]: عدد الأنصاف نقلات التي نبحث فيها عن عجز مادي
///   (4 = النقلة + 3 أنصاف بعدها).
/// - [maxPlies]: أقصى طول نُحاكيه. بعد نافذة التضحية نتابع حتى أول
///   وضعية هادئة (آخر نقلة ليست أخذًا) كي لا نقيس في منتصف تبادل.
///
/// يعيد null إن تعذّرت المحاكاة أو كان الخط أقصر من اللازم للحكم.
SacrificeLineResult? analyzeSacrificeLine({
  required String fenBefore,
  required String moverColor,
  required List<String> lineUci,
  int sacrificeWindow = 4,
  int maxPlies = 8,
}) {
  if (lineUci.isEmpty) return null;

  try {
    final g = ch.Chess();

    if (g.load(fenBefore) == false) return null;

    final base = materialBalanceFromFen(fenBefore, moverColor);

    var minBal = base;
    var lastBal = base;
    var mate = false;
    var played = 0;

    final limit = lineUci.length < maxPlies ? lineUci.length : maxPlies;

    for (var k = 0; k < limit; k++) {
      final mv = _uciToMoveMap(lineUci[k]);

      if (mv == null) break;

      final before = materialBalanceFromFen(g.fen, moverColor);

      final ok = g.move(mv);

      if (!ok) break;

      played++;

      final bal = materialBalanceFromFen(g.fen, moverColor);

      final wasCapture = bal != before;

      lastBal = bal;

      if (played <= sacrificeWindow && bal < minBal) minBal = bal;

      // k زوجي = نقلة اللاعب، فرديّ = رد الخصم.
      if (k.isEven && _isCheckmate(g)) {
        mate = true;
        break;
      }

      // بعد نافذة التضحية: نتوقف عند أول وضعية هادئة.
      if (played >= sacrificeWindow && !wasCapture) break;
    }

    // نحتاج على الأقل: النقلة + رد + نقلة لنحكم (إلا عند المات).
    if (!mate && played < 3) return null;

    return SacrificeLineResult(
      baseBalance: base,
      minBalance: minBal,
      finalBalance: lastBal,
      mate: mate,
      pliesSimulated: played,
    );
  } catch (_) {
    return null;
  }
}
