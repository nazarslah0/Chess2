import 'analysis_result.dart';
import 'analysis_rules.dart';
import 'game_library.dart';
import 'game_review_models.dart';

/// إحصاءات شريحة من المباريات (الكل، أو Blitz، ...).
class StatsSlice {
  int games = 0;
  int wins = 0;
  int losses = 0;
  int draws = 0;
  int analyzed = 0;

  double _lossSum = 0;
  int _moves = 0;
  double _accSum = 0;
  int _accMoves = 0;

  double get winRate => games == 0 ? 0 : wins / games * 100;

  /// null = لا مباريات محللة.
  double? get acpl => _moves == 0 ? null : _lossSum / _moves;
  double? get accuracy => _accMoves == 0 ? null : _accSum / _accMoves;
}

class UserStats {
  final StatsSlice total = StatsSlice();
  final Map<String, StatsSlice> byTimeClass = <String, StatsSlice>{};

  /// تصنيفات نقلات المستخدم.
  final Map<MoveQuality, int> qualities = <MoveQuality, int>{
    for (final q in MoveQuality.values) q: 0,
  };

  /// ACPL حسب المرحلة (opening / middlegame / endgame).
  final Map<String, double?> acplByPhase = <String, double?>{};
}

/// يحسب إحصاءات المستخدم من مبارياته المحفوظة وتحليلاتها (إن وُجدت).
/// تُحسب فقط المباريات التي يُعرف فيها لون المستخدم.
UserStats computeUserStats(
  List<({LibraryGame game, GameAnalysis? analysis})> items,
) {
  final s = UserStats();

  final phaseSum = <String, double>{};
  final phaseN = <String, int>{};

  for (final it in items) {
    final g = it.game;
    final color = g.userColor;

    if (color == null) continue;

    final slices = <StatsSlice>[
      s.total,
      if (g.timeClass.isNotEmpty)
        s.byTimeClass.putIfAbsent(g.timeClass, StatsSlice.new),
    ];

    final out = g.outcome;

    for (final sl in slices) {
      sl.games++;

      if (out == 'win') sl.wins++;
      if (out == 'loss') sl.losses++;
      if (out == 'draw') sl.draws++;
    }

    final a = it.analysis;

    if (a == null) continue;

    final mine = [for (final m in a.moves) if (m.side == color) m];

    if (mine.isEmpty) continue;

    var gameLoss = 0.0;
    var gameAcc = 0.0;

    for (final m in mine) {
      final loss = acplLossCp(m).toDouble();
      gameLoss += loss;

      final wb = winPercentWhite(m.evaluationBeforeWhiteCp);
      final wa = winPercentWhite(m.evaluationAfterWhiteCp);

      gameAcc += moveAccuracy(
        winPercentBeforeMover: color == 'w' ? wb : 100 - wb,
        winPercentAfterMover: color == 'w' ? wa : 100 - wa,
      );

      s.qualities[m.classification] = (s.qualities[m.classification] ?? 0) + 1;

      phaseSum[m.phase] = (phaseSum[m.phase] ?? 0) + loss;
      phaseN[m.phase] = (phaseN[m.phase] ?? 0) + 1;
    }

    for (final sl in slices) {
      sl.analyzed++;
      sl._lossSum += gameLoss;
      sl._moves += mine.length;
      sl._accSum += gameAcc;
      sl._accMoves += mine.length;
    }
  }

  for (final p in const ['opening', 'middlegame', 'endgame']) {
    final n = phaseN[p] ?? 0;

    s.acplByPhase[p] = n == 0 ? null : phaseSum[p]! / n;
  }

  return s;
}
