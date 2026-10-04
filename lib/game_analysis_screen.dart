import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'analysis_controller.dart';
import 'analysis_result.dart';
import 'analysis_rules.dart';
import 'app_settings.dart';
import 'board_widget.dart';
import 'game_review_models.dart';
import 'lichess_data_service.dart';
import 'models.dart';
import 'pgn_utils.dart';
import 'pv_utils.dart';
import 'uci_utils.dart';

/// شاشة تحليل مباراة واحدة — **مصدر واحد للتحليل** تُستخدم من
/// Chess.com ومن Lichess ومن PGN مُلصَق يدويًا على حدٍّ سواء.
/// كل ما تحتاجه هو نص PGN، وتسميات اختيارية لعرضها في الترويسة.
class GameAnalysisScreen extends StatefulWidget {
  final String pgn;
  final String? whiteLabel;
  final String? blackLabel;
  final String? resultLabel;
  final String sourceLabel;

  const GameAnalysisScreen({
    super.key,
    required this.pgn,
    this.whiteLabel,
    this.blackLabel,
    this.resultLabel,
    this.sourceLabel = '',
  });

  @override
  State<GameAnalysisScreen> createState() =>
      _GameAnalysisScreenState();
}

class _GameAnalysisScreenState
    extends State<GameAnalysisScreen>
    with SingleTickerProviderStateMixin {
  // ============================================================
  // خط التحليل كله في GameAnalysisController (انظر
  // analysis_controller.dart)؛ الواجهة تقرأ حالته فقط.
  // ============================================================

  late final GameAnalysisController _c = GameAnalysisController(
    pgn: widget.pgn,
    whiteLabel: widget.whiteLabel,
    blackLabel: widget.blackLabel,
  );

  String? get _parseError => _c.parseError;
  List<PgnPly> get _plies => _c.plies;
  List<String> get _fens => _c.fens;
  Map<String, String> get _headers => _c.headers;
  List<double> get _evalPawns => _c.evalPawns;
  List<String> get _evalLabels => _c.evalLabels;
  List<String> get _bestUci => _c.bestUci;
  List<List<String>> get _pvUci => _c.pvUci;
  List<MoveQuality> get _qualities => _c.qualities;
  List<bool> get _isBestEngineMove => _c.isBestEngineMove;
  List<int?> get _moveGapCp => _c.moveGapCp;
  List<int?> get _tbWdlWhite => _c.tbWdlWhite;
  List<BookMoveInfo?> get _bookInfo => _c.bookInfo;
  List<double?> get _maiaProb => _c.maiaProb;
  List<int?> get _maiaBucket => _c.maiaBucket;
  List<double?> get _maiaBestProb => _c.maiaBestProb;
  List<String?> get _maiaTopUci => _c.maiaTopUci;
  int get _puzzlesAdded => _c.puzzlesAdded;
  bool get _analyzing => _c.analyzing;
  bool get _cancelled => _c.cancelled;
  bool get _servedFromCache => _c.servedFromCache;
  double get _progress => _c.progress;
  int get _analyzedCount => _c.analyzedCount;

  int _cpAt(int i) => _c.cpAt(i);
  String _plyUci(int i) => _c.plyUci(i);
  int _lossAt(int i) => _c.lossAt(i);
  double _accuracyAt(int i) => _c.accuracyAt(i);
  String _phaseOf(int plyIndex) => _c.phaseOf(plyIndex);
  void _cancelAnalysis() => _c.cancel();

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();

    _c.addListener(_onControllerChanged);

    if (_c.parseError != null) return;

    _boardState.loadFen(_c.fens.first);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _c.start();
    });
  }

  final GameState _boardState = GameState();

  late final TabController _tabController =
      TabController(length: 5, vsync: this);

  int _currentIndex = 0;

  // خيارات العرض (قائمة الخيارات).
  bool _showArrows = true;
  bool _showEval = true;
  bool _showCoords = true;
  bool _showBadges = true;

  // false = نعرض شاشة التحليل ثم صفحة الإحصائيات؛ true = المراجعة
  // على الرقعة (الأسهم والعلامات لا تظهر قبل ذلك أبدًا).
  bool _reviewStarted = false;

  // شريط النقلات الأفقي + نافذة المراجعة.
  final ScrollController _stripCtrl = ScrollController();
  final Map<int, GlobalKey> _stripKeys = <int, GlobalKey>{};
  final ValueNotifier<int> _sheetTick = ValueNotifier<int>(0);
  bool _sheetOpen = false;
  @override
  void setState(VoidCallback fn) {
    super.setState(fn);

    // يُحدّث محتوى نافذة المراجعة المفتوحة أثناء التحليل.
    _sheetTick.value++;
  }

  @override
  void dispose() {
    _c.removeListener(_onControllerChanged);
    _c.dispose();
    _boardState.dispose();
    _tabController.dispose();
    _stripCtrl.dispose();
    _sheetTick.dispose();
    super.dispose();
  }

  String get _whiteName =>
      widget.whiteLabel ?? _headers['White'] ?? 'أبيض';

  String get _blackName =>
      widget.blackLabel ?? _headers['Black'] ?? 'أسود';

  String get _resultText =>
      widget.resultLabel ?? _headers['Result'] ?? '';

  // ------------------------------------------------------------
  // الأداء مقابل المتوقع (Maia)
  // ------------------------------------------------------------

  /// لكل لاعب: عدد النقلات التي وجد فيها أفضل نقلة عند Stockfish مقابل
  /// ما يتوقعه Maia من لاعب بتصنيفه (مجموع احتمالات أفضل نقلة).
  /// النتيجة: n, actual, expected, variance, bucket — أو null إن لم
  /// تتوفر بيانات كافية (< 8 نقلات).
  Map<String, double>? _maiaPerformance(String color) {
    var n = 0;
    var actual = 0;
    var expected = 0.0;
    var variance = 0.0;
    int? bucket;

    for (var i = 0; i < _plies.length; i++) {
      if (_plies[i].color != color) continue;

      final bp = i < _maiaBestProb.length ? _maiaBestProb[i] : null;

      if (bp == null) continue;

      final best = _pvUci[i].isNotEmpty ? _pvUci[i].first : '';

      n++;
      expected += bp;
      variance += bp * (1 - bp);

      if (isSameUciMove(best, _plyUci(i))) actual++;

      bucket ??= _maiaBucket[i];
    }

    if (n < 8 || bucket == null) return null;

    return <String, double>{
      'n': n.toDouble(),
      'actual': actual.toDouble(),
      'expected': expected,
      'variance': variance,
      'bucket': bucket.toDouble(),
    };
  }

  Widget _buildPerformanceCard() {
    final w = _maiaPerformance('w');
    final b = _maiaPerformance('b');

    if (w == null && b == null) return const SizedBox.shrink();

    Widget row(String name, Map<String, double> m) {
      final actual = m['actual']!;
      final expected = m['expected']!;
      final variance = m['variance']!;
      final bucket = m['bucket']!.toInt();

      final z = variance > 0.5
          ? (actual - expected) / math.sqrt(variance)
          : 0.0;

      String verdict;
      Color color;

      if (z >= 1) {
        verdict = 'أعلى من مستوى $bucket';
        color = Colors.green;
      } else if (z <= -1) {
        verdict = 'أقل من مستوى $bucket';
        color = Colors.orange;
      } else {
        verdict = 'ضمن المتوقع لمستوى $bucket';
        color = Colors.white70;
      }

      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Text(
              'وجد ${actual.toInt()} من ${m['n']!.toInt()} أفضل نقلة؛ '
              'المتوقع ${expected.toStringAsFixed(1)}',
              style: const TextStyle(fontSize: 13),
            ),
            Text(
              verdict,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'الأداء مقابل المتوقع (Maia)',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          if (w != null) row(_whiteName, w),
          if (b != null) row(_blackName, b),
          const SizedBox(height: 8),
          Text(
            'يقارن عدد أفضل نقلات Stockfish التي وجدتها بما يجده لاعب '
            'بنفس التصنيف عادةً.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
          if (_puzzlesAdded > 0) ...[
            const SizedBox(height: 6),
            Text(
              'أُضيف $_puzzlesAdded تمرين من هذه المباراة إلى «تمارين '
              'من مبارياتك».',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  String? _maiaNoteAt(int k) {
    if (k < 0 || k >= _maiaProb.length) return null;

    final prob = _maiaProb[k];
    final bucket = _maiaBucket[k];

    if (prob == null || bucket == null) return null;

    String pct(double p) {
      final v = p * 100;

      return v < 1 ? 'أقل من 1' : v.toStringAsFixed(0);
    }

    final q = k < _qualities.length ? _qualities[k] : null;

    final bad = q == MoveQuality.inaccuracy ||
        q == MoveQuality.mistake ||
        q == MoveQuality.blunder ||
        q == MoveQuality.miss;

    if (!bad) {
      return 'Maia $bucket: يجد هذه النقلة ${pct(prob)}% من اللاعبين '
          'بهذا التصنيف';
    }

    String? kind;

    if (prob >= 0.25 || _maiaTopUci[k] == _plyUci(k)) {
      kind = 'خطأ شائع عند هذا المستوى';
    } else if (prob < 0.05) {
      kind = 'زلة غير معتادة، غالبًا تسرّع أو غفلة';
    }

    final bestProb = _maiaBestProb[k];

    return 'Maia $bucket: '
        '${kind != null ? '$kind — ' : ''}'
        'يلعبها ${pct(prob)}% من لاعبي هذا المستوى'
        '${bestProb != null && bestProb < 0.3 ? '، وأفضل نقلة لا يجدها إلا ${pct(bestProb)}%' : ''}';
  }

  String? _tbNoteAt(int k) {
    if (k < 0 ||
        k >= _plies.length ||
        k + 1 >= _tbWdlWhite.length) {
      return null;
    }

    final after = _tbWdlWhite[k + 1];

    if (after == null) return null;

    final sign = _plies[k].color == 'w' ? 1 : -1;

    String name(int v) =>
        v > 0 ? 'فوز' : (v < 0 ? 'خسارة' : 'تعادل');

    final ma = after * sign;
    final beforeRaw = _tbWdlWhite[k];

    if (beforeRaw == null) {
      return 'Tablebase: النتيجة بعد النقلة مضمونة — ${name(ma)}';
    }

    final mb = beforeRaw * sign;

    if (mb == ma) {
      return 'Tablebase: النتيجة لم تتغير (${name(mb)} مضمون)';
    }

    return 'Tablebase: ${name(mb)} ← ${name(ma)} (نتيجة مضمونة)';
  }

  String? _bookNoteAt(int k) {
    if (k < 0 || k >= _bookInfo.length) return null;

    final info = _bookInfo[k];

    if (info == null) return null;

    final parts = <String>[];

    if (info.mastersGames > 0) {
      final pct = info.mastersPercent;

      parts.add(
        'لُعبت في ${info.mastersGames} مباراة أساتذة'
        '${pct != null ? ' (${pct.toStringAsFixed(0)}%)' : ''}',
      );
    }

    final lp = info.lichessPercent;

    if (lp != null && (info.lichessGames ?? 0) > 0) {
      parts.add(
        'يلعبها ${lp.toStringAsFixed(0)}% من لاعبي Lichess',
      );
    }

    if (parts.isEmpty) return null;

    return '${info.isBook ? 'كتاب: ' : ''}${parts.join(' · ')}';
  }

  /// لاحقة تقليدية (?, ??, ?!, !!) تُضاف لنص SAN، بنفس أسلوب
  /// الأمثلة المرفقة في الطلب.
  String _sanSuffix(MoveQuality q) {
    switch (q) {
      case MoveQuality.brilliant:
        return '!!';
      case MoveQuality.great:
        return '!';
      case MoveQuality.inaccuracy:
        return '?!';
      case MoveQuality.mistake:
      case MoveQuality.miss:
        return '?';
      case MoveQuality.blunder:
        return '??';
      default:
        return '';
    }
  }

  // ============================================================
  // التنقل بين النقلات
  // ============================================================

  void _goTo(int index) {
    if (_fens.isEmpty) {
      return;
    }

    final clamped = index.clamp(0, _fens.length - 1);

    setState(() {
      _currentIndex = clamped;
    });

    _boardState.loadFen(_fens[clamped]);

    _scrollStripToCurrent();
  }

  /// ينتقل إلى النقلة رقم [index] ويحوّل التبويب إلى "نظرة
  /// عامة" حتى تظهر الرقعة والسهم مباشرة (يُستخدم من تبويبي
  /// الأخطاء واللحظات الحرجة).
  void _jumpAndShowBoard(int index) {
    _goTo(index);

    if (_sheetOpen && mounted) {
      _sheetOpen = false;
      Navigator.of(context).pop();
    }
  }

  /// السهم يُبنى مباشرة من UCI (من → إلى) عبر طبقة UCI الموحدة،
  /// وليس من SAN أو من نص معروض. يعيد null إن كان UCI غير صالح.
  BoardArrow? _decodeArrow(String uci, Color color) {
    final move = parseUci(uci);

    if (move == null) return null;

    return BoardArrow(
      from: move.from,
      to: move.to,
      color: color,
    );
  }

  /// سهم واحد فقط: أفضل نقلة يقترحها المحرك. لا نرسم أبدًا سهم
  /// النقلة التي لُعبت، ولا نرسم شيئًا قبل الضغط على "متابعة
  /// المراجعة".
  List<BoardArrow> _arrowsForCurrent() {
    if (!_reviewStarted ||
        _plies.isEmpty ||
        _fens.isEmpty) {
      return const <BoardArrow>[];
    }

    final k = _currentIndex - 1;

    // الوضعية الابتدائية: أفضل نقلة للأبيض.
    final idx = _currentIndex == 0 ? 0 : k;

    if (_currentIndex > 0) {
      if (k >= _qualities.length ||
          k >= _isBestEngineMove.length) {
        return const <BoardArrow>[];
      }

      // لعب الأفضل أو نقلة كتاب: لا حاجة لسهم.
      if (_isBestEngineMove[k] ||
          _qualities[k] == MoveQuality.book) {
        return const <BoardArrow>[];
      }
    }

    if (idx >= _bestUci.length) {
      return const <BoardArrow>[];
    }

    final arrow = _decodeArrow(
      _bestUci[idx],
      const Color(0xFF81B64C).withValues(alpha: 0.9),
    );

    return arrow == null ? const <BoardArrow>[] : <BoardArrow>[arrow];
  }

  /// علامة جودة النقلة فوق القطعة المتحركة (الزاوية العلوية
  /// اليمنى) — بعد بدء المراجعة فقط.
  List<BoardBadge> _badgesForCurrent() {
    if (!_reviewStarted || !_showBadges || _currentIndex <= 0) {
      return const <BoardBadge>[];
    }

    final k = _currentIndex - 1;

    if (k >= _qualities.length || k >= _plies.length) {
      return const <BoardBadge>[];
    }

    return [
      BoardBadge(
        square: _plies[k].to,
        quality: _qualities[k],
      ),
    ];
  }

  /// دقة كل نقلة ووزنها (تقلّب الوضعية) للنقلات المحلَّلة فعليًا.
  MoveAccuracyData get _accData {
    final m = _qualities.length;

    if (m == 0 || _evalPawns.length < m + 1) {
      return const MoveAccuracyData(
        accuracy: <double>[],
        weight: <double>[],
      );
    }

    return computeMoveAccuracyData(
      cpWhite: [
        for (var i = 0; i <= m; i++)
          _cpAt(i),
      ],
      sides: [
        for (var i = 0; i < m; i++) _plies[i].color,
      ],
    );
  }

  /// دقة المباراة لكل لاعب بالطريقة الصارمة (متوسط مرجَّح +
  /// متوافق) — انظر computeMoveAccuracyData في game_review_models.
  Map<String, double> get _accuracyBySide {
    if (_qualities.isEmpty) {
      return {'w': 0, 'b': 0};
    }

    final data = _accData;

    return {
      'w': combineAccuracy(data, [
        for (var i = 0; i < _qualities.length; i++)
          if (_plies[i].color == 'w') i,
      ]),
      'b': combineAccuracy(data, [
        for (var i = 0; i < _qualities.length; i++)
          if (_plies[i].color == 'b') i,
      ]),
    };
  }

  /// Average Centipawn Loss لكل لاعب — متوسط خسارة التقييم
  /// الفعلية بوحدة القرن لكل نقلة لعبها، محسوبة من نتائج
  /// Stockfish المخزَّنة مباشرة (وليست مُخترَعة). قيمة أقل
  /// = لعب أدق. null يعني عدم توفر بيانات كافية بعد.
  Map<String, double?> get _acplBySide {
    final results = _c.results;

    if (results.isEmpty) {
      return {'w': null, 'b': null};
    }

    // الحساب في analysis_rules.dart: من منظور اللاعب الذي نفّذ النقلة،
    // مع تقييد التقييم ±1000 قرن كي لا يفسد المات المتوسط.
    final acpl = computeAcpl(results);

    return {
      'w': acpl.white == null ? null : acpl.white! / 100,
      'b': acpl.black == null ? null : acpl.black! / 100,
    };
  }

  /// متوسط الدقة لكل لاعب في كل مرحلة من مراحل اللعبة.
  Map<String, Map<String, double>> get _accuracyByPhase {
    final sums = {
      'opening': {'w': 0.0, 'b': 0.0},
      'middlegame': {'w': 0.0, 'b': 0.0},
      'endgame': {'w': 0.0, 'b': 0.0},
    };

    final counts = {
      'opening': {'w': 0, 'b': 0},
      'middlegame': {'w': 0, 'b': 0},
      'endgame': {'w': 0, 'b': 0},
    };

    for (var i = 0; i < _qualities.length; i++) {
      final phase = _phaseOf(i);
      final color = _plies[i].color;
      final acc = _accuracyAt(i);

      sums[phase]![color] =
          (sums[phase]![color] ?? 0) + acc;
      counts[phase]![color] =
          (counts[phase]![color] ?? 0) + 1;
    }

    final result = <String, Map<String, double>>{};

    for (final phase in sums.keys) {
      result[phase] = {
        for (final color in ['w', 'b'])
          color: (counts[phase]![color] ?? 0) > 0
              ? sums[phase]![color]! /
                  counts[phase]![color]!
              : 0,
      };
    }

    return result;
  }

  Map<MoveQuality, int> get _qualityCounts {
    final counts = <MoveQuality, int>{};

    for (final q in _qualities) {
      counts[q] = (counts[q] ?? 0) + 1;
    }

    return counts;
  }

  /// نفس العدّ لكن مقسّم لكل لاعب — مطلوب لقسم "إحصائيات
  /// الأبيض والأسود" في تقرير المباراة.
  Map<String, Map<MoveQuality, int>> get _qualityCountsBySide {
    final result = {
      'w': <MoveQuality, int>{},
      'b': <MoveQuality, int>{},
    };

    for (var i = 0; i < _qualities.length; i++) {
      final color = _plies[i].color;
      final q = _qualities[i];
      result[color]![q] = (result[color]![q] ?? 0) + 1;
    }

    return result;
  }

  /// نقلة "رائعة!!" الأبرز في المباراة (أكبر قيمة تضحية)، أو
  /// null إن لم توجد أي نقلة رائعة — لا نخترع "أفضل نقلة"
  /// بديلة بلا معيار حقيقي يميّزها عن عشرات النقلات "الأفضل".
  /// نقلة "رائعة!!" الأبرز في المباراة، منفصلة تمامًا عن
  /// "أفضل نقلة Engine" — قد توجد إحداهما بدون الأخرى.
  int? get _brilliantMoveIndex {
    int? best;
    var bestScore = -1;

    for (var i = 0; i < _qualities.length; i++) {
      if (_qualities[i] != MoveQuality.brilliant) continue;

      try {
        final boardBefore = GameState.parseBoard(
          _plies[i].fenBefore.split(' ').first,
        );

        final movingPiece =
            boardBefore[_plies[i].from];

        final movingValue = movingPiece != null &&
                movingPiece.length == 2
            ? (pieceValues[movingPiece[1]] ?? 0)
            : 0;

        if (movingValue > bestScore) {
          bestScore = movingValue;
          best = i;
        }
      } catch (_) {}
    }

    return best;
  }

  /// "أفضل نقلة في المباراة" (Best Engine Move) — معيار
  /// مختلف تمامًا عن Brilliant: من بين كل النقلات التي
  /// طابقت bestUci الخاص بـ Stockfish تمامًا (from/to/
  /// promotion)، نختار الوضعية التي كان فيها الفارق عن ثاني
  /// أفضل نقلة أكبر ما يمكن — أي الموضع الذي كان فيه إيجاد
  /// هذه النقلة بالذات الأكثر أهمية وحسمًا، بدل اختيار
  /// عشوائي من بين عشرات النقلات "الأفضل" في مباراة جيدة.
  int? get _bestEngineMoveIndex {
    int? best;
    var bestGap = -1 << 30;

    for (var i = 0; i < _isBestEngineMove.length; i++) {
      if (!_isBestEngineMove[i]) continue;

      final gap = _moveGapCp[i];

      if (gap != null && gap > bestGap) {
        bestGap = gap;
        best = i;
      }
    }

    return best;
  }

  /// أسوأ نقلة في المباراة = أكبر خسارة تقييم مُسجَّلة فعليًا.
  int? get _worstMoveIndex {
    if (_qualities.isEmpty) return null;

    int? worst;
    var worstLoss = -1 << 30;

    for (var i = 0; i < _qualities.length; i++) {
      final loss = _lossAt(i);

      if (loss > worstLoss) {
        worstLoss = loss;
        worst = i;
      }
    }

    return worstLoss > 0 ? worst : null;
  }

  /// الفرص الضائعة: فقط النقلات المصنّفة فعليًا miss بناءً على
  /// معيار محسوب (انهيار أفضلية حاسمة)، وليس تخمينًا.
  List<int> get _missedOpportunityIndices {
    final result = <int>[];

    for (var i = 0; i < _qualities.length; i++) {
      if (_qualities[i] == MoveQuality.miss) {
        result.add(i);
      }
    }

    return result;
  }

  /// نص ملخّص المباراة — مبني بالكامل من أرقام محسوبة فعليًا
  /// (قالب نصي، وليس توليدًا بالذكاء الاصطناعي).
  String get _gameSummaryText {
    if (_qualities.isEmpty) return '';

    final acc = _accuracyBySide;
    final worst = _worstMoveIndex;

    final parts = <String>[];

    parts.add(
      'دقة $_whiteName ${(acc['w'] ?? 0).toStringAsFixed(0)}%'
      ' مقابل دقة $_blackName'
      ' ${(acc['b'] ?? 0).toStringAsFixed(0)}%.',
    );

    if (worst != null) {
      final ply = _plies[worst];
      final moveNumber = (worst ~/ 2) + 1;
      final mover =
          ply.color == 'w' ? _whiteName : _blackName;
      final lossPawns =
          (_lossAt(worst) / 100).toStringAsFixed(1);

      parts.add(
        'أكبر خطأ في المباراة كان من $mover عند النقلة'
        ' $moveNumber'
        '${ply.color == 'w' ? '.' : '...'} '
        '${ply.san}${_sanSuffix(_qualities[worst])}'
        ' (خسارة تقييم $lossPawns بيدق تقريبًا).',
      );
    }

    final missed = _missedOpportunityIndices;

    if (missed.isNotEmpty) {
      parts.add(
        'هناك ${missed.length} فرصة/فرص لم تُستغل بالكامل'
        ' خلال المباراة.',
      );
    }

    return parts.join(' ');
  }

  /// أكبر اللحظات الحرجة (أخطاء/فرص ضائعة) مرتبة تنازليًا حسب
  /// حجم خسارة التقييم.
  List<_CriticalMoment> get _criticalMoments {
    final moments = <_CriticalMoment>[
      for (final m in _c.results)
        if (m.isCritical)
          _CriticalMoment(
            plyIndex: m.ply,
            quality: m.classification,
            lossCp: m.evaluationLossCp.clamp(0, 1000),
            score: m.criticalScore,
            kind: m.criticalKind ?? 'swing',
          ),
    ];

    moments.sort((a, b) => b.score.compareTo(a.score));

    return moments;
  }

  // ============================================================
  // Build
  // ============================================================

  // ============================================================
  // واجهة بأسلوب تطبيق Chess.com — شاشة واحدة
  // ============================================================

  static const Color _bg = Color(0xFF312E2B);
  static const Color _panel = Color(0xFF262522);
  static const Color _green = Color(0xFF81B64C);

  ThemeData _darkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorSchemeSeed: _green,
      scaffoldBackgroundColor: _bg,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_parseError != null) {
      return Theme(
        data: _darkTheme(),
        child: Scaffold(
          appBar: AppBar(
            title: const Text('تحليل المباراة'),
          ),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                _parseError!,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    }

    if (!_reviewStarted) {
      return Theme(
        data: _darkTheme(),
        child: Scaffold(
          backgroundColor: _bg,
          body: SafeArea(
            child: _analyzing
                ? _buildAnalyzingView()
                : _buildSummaryView(),
          ),
        ),
      );
    }

    final topColor = _boardState.flipped ? 'w' : 'b';
    final bottomColor = _boardState.flipped ? 'b' : 'w';

    return Theme(
      data: _darkTheme(),
      child: Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, c) {
              // الأجزاء الثابتة: الشريط العلوي + النقلات + التقييم
              // + لاعبان + الشريط السفلي + حد أدنى للمعلومات.
              const fixed = 52 + 46 + 16 + 120 + 78 + 70;

              final side = math.min(
                c.maxWidth,
                math.max(180.0, c.maxHeight - fixed),
              );

              return Column(
                children: [
                  _buildTopBar(),
                  _buildMoveStrip(),
                  if (_showEval) _buildEvalStrip(),
                  _buildPlayerBar(topColor),
                  Center(
                    child: SizedBox(
                      width: side,
                      height: side,
                      child: _buildBoard(),
                    ),
                  ),
                  _buildPlayerBar(bottomColor),
                  Expanded(child: _buildInfoPanel()),
                  _buildBottomBar(),
                ],
              );
            },
          ),
        ),
      ),
    );
  }


  // ============================================================
  // مرحلة 1: التحليل  →  مرحلة 2: صفحة الإحصائيات  →  المراجعة
  // ============================================================

  void _startReview({int index = 0}) {
    setState(() {
      _reviewStarted = true;
    });

    _goTo(index);
  }

  Widget _buildStageTopBar(String title) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(
              Icons.arrow_back_rounded,
              textDirection: TextDirection.ltr,
              color: Colors.white70,
              size: 30,
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  /// أثناء التحليل: الرقعة بلا أسهم ولا علامات + شريط تقدّم.
  Widget _buildAnalyzingView() {
    return LayoutBuilder(
      builder: (context, c) {
        final side = math.min(
          c.maxWidth - 32,
          math.max(160.0, c.maxHeight - 260),
        );

        return Column(
          children: [
            _buildStageTopBar('مراجعة المباراة'),
            const Spacer(),
            SizedBox(
              width: side,
              height: side,
              child: _buildBoard(),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: LinearProgressIndicator(
                value: _progress,
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
                color: _green,
                backgroundColor: const Color(0xFF3A3937),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'جارٍ تحليل المباراة... '
              '$_analyzedCount من ${_fens.length}'
              ' (${(_progress * 100).round()}%)',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
            TextButton(
              onPressed: _cancelAnalysis,
              child: const Text('إلغاء التحليل'),
            ),
            const Spacer(),
          ],
        );
      },
    );
  }

  /// صفحة الإحصائيات بعد انتهاء التحليل (على طراز chess.com):
  /// رسم التقييم، الدقة، وعدد النقلات من كل تصنيف لكل لاعب.
  Widget _buildSummaryView() {
    final acc = _accuracyBySide;
    final counts = _qualityCountsBySide;

    final accW = acc['w'] ?? 0;
    final accB = acc['b'] ?? 0;

    final result = _headers['Result'] ?? '';
    final whiteWon = result == '1-0';
    final blackWon = result == '0-1';

    Widget cell(Widget child) => Center(child: child);

    Widget row({
      required Widget label,
      required Widget black,
      required Widget mid,
      required Widget white,
    }) {
      // RTL: أول عنصر في أقصى اليمين → (العنوان، الأسود، الوسط، الأبيض).
      return Row(
        children: [
          Expanded(flex: 7, child: label),
          Expanded(flex: 3, child: black),
          Expanded(flex: 3, child: mid),
          Expanded(flex: 3, child: white),
        ],
      );
    }

    Widget labelText(String s) => Text(
          s,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        );

    Widget playerHead({
      required String name,
      required String color,
      required bool winner,
    }) {
      final isWhite = color == 'w';

      return Column(
        children: [
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textDirection: TextDirection.ltr,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: 76,
            height: 76,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: isWhite
                  ? const Color(0xFFE8E8E8)
                  : const Color(0xFF5A5856),
              borderRadius: BorderRadius.circular(6),
              border: winner
                  ? Border.all(color: _green, width: 3)
                  : null,
            ),
            child: Image.asset(
              chessComPieceTheme.assetPath(color, 'P'),
              fit: BoxFit.contain,
            ),
          ),
        ],
      );
    }

    Widget accBox(double value, bool higher) {
      return Container(
        width: 92,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: higher
              ? const Color(0xFFF0F0F0)
              : const Color(0xFF454341),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          value.toStringAsFixed(1),
          textDirection: TextDirection.ltr,
          style: TextStyle(
            color: higher
                ? const Color(0xFF262522)
                : Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }

    final whiteHigher = accW > accB;
    final blackHigher = accB > accW;

    return Column(
      children: [
        _buildStageTopBar('مراجعة المباراة'),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              children: [
                // ---------------- رسم التقييم ----------------
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    height: 104,
                    width: double.infinity,
                    child: LayoutBuilder(
                      builder: (context, c) {
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapUp: (d) {
                            if (_fens.length < 2 || c.maxWidth <= 0) {
                              return;
                            }

                            final idx = (d.localPosition.dx /
                                    c.maxWidth *
                                    (_fens.length - 1))
                                .round()
                                .clamp(0, _fens.length - 1);

                            _startReview(index: idx);
                          },
                          child: CustomPaint(
                            painter: _SummaryGraphPainter(
                              evalPawns: _evalPawns,
                              qualities: _qualities,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // ---------------- اللاعبان ----------------
                row(
                  label: labelText('اللاعبَين'),
                  black: cell(
                    playerHead(
                      name: _blackName,
                      color: 'b',
                      winner: blackWon,
                    ),
                  ),
                  mid: const SizedBox(),
                  white: cell(
                    playerHead(
                      name: _whiteName,
                      color: 'w',
                      winner: whiteWon,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // ---------------- الدقة ----------------
                row(
                  label: labelText('الدقة'),
                  black: cell(accBox(accB, blackHigher)),
                  mid: const SizedBox(),
                  white: cell(accBox(accW, whiteHigher)),
                ),
                const SizedBox(height: 16),
                const Divider(color: Color(0xFF45433F), height: 1),
                const SizedBox(height: 8),

                // ---------------- عدد النقلات لكل تصنيف ----------------
                for (final q in moveQualityDisplayOrder)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: row(
                      label: labelText(moveQualityInfo[q]!.label),
                      black: cell(
                        Text(
                          '${counts['b']![q] ?? 0}',
                          style: TextStyle(
                            color: moveQualityInfo[q]!.color,
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      mid: cell(QualityBadge(quality: q, size: 34)),
                      white: cell(
                        Text(
                          '${counts['w']![q] ?? 0}',
                          style: TextStyle(
                            color: moveQualityInfo[q]!.color,
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),

                if (_cancelled)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      'تم إلغاء التحليل عند النقلة $_analyzedCount'
                      ' من ${_fens.length}، فالإحصائيات تخص النقلات'
                      ' المحلَّلة فقط.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.orange.shade300,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),

        // ---------------- متابعة المراجعة ----------------
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
          child: Material(
            color: _green,
            borderRadius: BorderRadius.circular(10),
            elevation: 3,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: _startReview,
              child: const SizedBox(
                width: double.infinity,
                height: 60,
                child: Center(
                  child: Text(
                    'متابعة المراجعة',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: 52,
      color: _bg,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(
              Icons.arrow_back_rounded,
              textDirection: TextDirection.ltr,
              color: Colors.white70,
              size: 30,
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                widget.sourceLabel.isEmpty
                    ? 'تحليل المباراة'
                    : widget.sourceLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 48,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _resultText,
                textDirection: TextDirection.ltr,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- شريط النقلات الأفقي ----------------

  void _scrollStripToCurrent() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      if (_currentIndex <= 0) {
        if (_stripCtrl.hasClients) {
          _stripCtrl.animateTo(
            0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
          );
        }
        return;
      }

      final ctx = _stripKeys[_currentIndex]?.currentContext;

      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.5,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Widget _buildMoveStrip() {
    final items = <Widget>[];

    for (var i = 0; i < _plies.length; i += 2) {
      items.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            '.${(i ~/ 2) + 1}',
            textDirection: TextDirection.ltr,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 15,
            ),
          ),
        ),
      );

      items.add(_stripMove(i));

      if (i + 1 < _plies.length) {
        items.add(_stripMove(i + 1));
      }
    }

    return Container(
      height: 46,
      color: _panel,
      child: SingleChildScrollView(
        controller: _stripCtrl,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(children: items),
      ),
    );
  }

  Widget _stripMove(int k) {
    final ply = _plies[k];
    final selected = _currentIndex == k + 1;
    final key = _stripKeys.putIfAbsent(k + 1, () => GlobalKey());

    final q = k < _qualities.length ? _qualities[k] : null;

    Color textColor = Colors.white;

    if (q == MoveQuality.brilliant ||
        q == MoveQuality.blunder ||
        q == MoveQuality.mistake ||
        q == MoveQuality.miss ||
        q == MoveQuality.inaccuracy) {
      textColor = moveQualityInfo[q]!.color;
    }

    final first = ply.san.isEmpty ? '' : ply.san[0];
    final hasFigurine = 'KQRBN'.contains(first) && first.isNotEmpty;

    return GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onTap: () => _goTo(k + 1),
      child: Container(
        margin: const EdgeInsets.symmetric(
          horizontal: 2,
          vertical: 7,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF5A5856)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasFigurine) ...[
                Image.asset(
                  chessComPieceTheme.assetPath(ply.color, first),
                  width: 20,
                  height: 20,
                ),
                const SizedBox(width: 2),
              ],
              Text(
                hasFigurine ? ply.san.substring(1) : ply.san,
                style: TextStyle(
                  color: textColor,
                  fontSize: 17,
                  fontWeight: selected
                      ? FontWeight.w800
                      : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------- شريط التقييم الأفقي ----------------

  Widget _buildEvalStrip() {
    final hasEval = _evalPawns.isNotEmpty;

    final pawns = hasEval ? _evalPawns[_currentIndex] : 0.0;
    final label = hasEval ? _evalLabels[_currentIndex] : '0.00';

    final frac = ((pawns.clamp(-8.0, 8.0) + 8.0) / 16.0)
        .clamp(0.0, 1.0)
        .toDouble();

    final whiteBetter = frac >= 0.5;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        height: 16,
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(color: const Color(0xFF403D39)),
            ),
            Positioned.fill(
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: frac,
                child: Container(color: Colors.white),
              ),
            ),
            Positioned.fill(
              child: Align(
                alignment: whiteBetter
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: whiteBetter
                          ? const Color(0xFF2B2B2B)
                          : Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- الرقعة ----------------

  Widget _buildBoard() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // سحب يمين/يسار للتنقل بين النقلات.
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity;

        if (v == null) return;

        if (v < -150) {
          _goTo(_currentIndex + 1);
        } else if (v > 150) {
          _goTo(_currentIndex - 1);
        }
      },
      child: BoardWidget(
        state: _boardState,
        boardTheme: AppSettings.instance.boardTheme,
        pieceTheme: AppSettings.instance.pieceTheme,
        onTap: (_) {},
        arrows: _showArrows
            ? _arrowsForCurrent()
            : const <BoardArrow>[],
        badges: _badgesForCurrent(),
        showCoordinates: _showCoords,
        interactive: false,
      ),
    );
  }

  // ---------------- شريط اللاعب ----------------

  Widget _buildPlayerBar(String color) {
    final isWhite = color == 'w';

    final name = isWhite ? _whiteName : _blackName;
    final elo = _headers[isWhite ? 'WhiteElo' : 'BlackElo'];

    final fenParts = _fens[_currentIndex].split(' ');
    final toMove = fenParts.length > 1 ? fenParts[1] : 'w';
    final active = toMove == color;

    final acc = _qualities.isNotEmpty
        ? _accuracyBySide[color]
        : null;

    final title = (elo != null && elo.isNotEmpty && elo != '?')
        ? '($elo) $name'
        : name;

    return Container(
      color: _bg,
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 8,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: isWhite
                  ? const Color(0xFFE8E8E8)
                  : const Color(0xFF5A5856),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Image.asset(
              chessComPieceTheme.assetPath(color, 'P'),
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 92,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active
                  ? const Color(0xFF1F1E1C)
                  : const Color(0xFF5F5E5C),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  acc == null ? '—' : acc.toStringAsFixed(1),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Text(
                  'الدقة',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- لوحة المعلومات تحت الرقعة ----------------

  Widget _buildInfoPanel() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        children: [
          if (_analyzing) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    'جارٍ تحليل المباراة... '
                    '$_analyzedCount من ${_fens.length}'
                    ' (${(_progress * 100).round()}%)',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _cancelAnalysis,
                  child: const Text('إلغاء'),
                ),
              ],
            ),
            LinearProgressIndicator(
              value: _progress,
              color: _green,
              backgroundColor: const Color(0xFF3A3937),
            ),
            const SizedBox(height: 8),
          ],
          if (_cancelled)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'تم إلغاء التحليل عند النقلة $_analyzedCount'
                ' من ${_fens.length}. النتائج قبل هذه النقطة'
                ' محفوظة، والباقي غير محلَّل.',
                style: TextStyle(
                  color: Colors.orange.shade300,
                  fontSize: 12,
                ),
              ),
            ),
          if (_servedFromCache && !_analyzing)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.bolt_rounded,
                    size: 16,
                    color: Colors.green.shade300,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'نتائج محفوظة من تحليل سابق لهذه المباراة.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.green.shade300,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (!_analyzing && _plies.isNotEmpty)
            _buildCurrentMoveInfo(),
        ],
      ),
    );
  }

  // ---------------- الشريط السفلي ----------------

  Widget _buildBottomBar() {
    final atStart = _currentIndex <= 0;
    final atEnd = _currentIndex >= _fens.length - 1;

    return Container(
      color: _bg,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: _BarButton(
              icon: Icons.format_list_bulleted_rounded,
              label: 'الخيارات',
              onTap: _openOptions,
            ),
          ),
          Expanded(
            child: Center(
              child: Material(
                color: _green,
                borderRadius: BorderRadius.circular(14),
                elevation: 3,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _openReview,
                  child: const SizedBox(
                    width: 70,
                    height: 58,
                    child: Icon(
                      Icons.star_rounded,
                      color: Colors.white,
                      size: 38,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: _BarButton(
              icon: Icons.chevron_left_rounded,
              label: 'رجوع',
              enabled: !atStart,
              repeat: true,
              onTap: () => _goTo(_currentIndex - 1),
            ),
          ),
          Expanded(
            child: _BarButton(
              icon: Icons.chevron_right_rounded,
              label: 'تقدّم',
              enabled: !atEnd,
              repeat: true,
              onTap: () => _goTo(_currentIndex + 1),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- قائمة الخيارات ----------------

  void _openOptions() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _panel,
      builder: (ctx) {
        return Theme(
          data: _darkTheme(),
          child: StatefulBuilder(
            builder: (ctx, setSheet) {
              return SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 8),
                    ListTile(
                      leading: const Icon(Icons.swap_vert_rounded),
                      title: const Text('قلب الرقعة'),
                      onTap: () {
                        Navigator.pop(ctx);
                        setState(() {
                          _boardState.flipBoard();
                        });
                      },
                    ),
                    SwitchListTile(
                      secondary:
                          const Icon(Icons.arrow_right_alt_rounded),
                      title: const Text('إظهار الأسهم'),
                      value: _showArrows,
                      onChanged: (v) {
                        setSheet(() {});
                        setState(() {
                          _showArrows = v;
                        });
                      },
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.stars_rounded),
                      title: const Text('إظهار علامات النقلات'),
                      value: _showBadges,
                      onChanged: (v) {
                        setSheet(() {});
                        setState(() {
                          _showBadges = v;
                        });
                      },
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.align_vertical_center),
                      title: const Text('إظهار شريط التقييم'),
                      value: _showEval,
                      onChanged: (v) {
                        setSheet(() {});
                        setState(() {
                          _showEval = v;
                        });
                      },
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.grid_on_rounded),
                      title: const Text('إظهار إحداثيات الرقعة'),
                      value: _showCoords,
                      onChanged: (v) {
                        setSheet(() {});
                        setState(() {
                          _showCoords = v;
                        });
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.copy_rounded),
                      title: const Text('نسخ PGN'),
                      onTap: () {
                        Clipboard.setData(
                          ClipboardData(text: widget.pgn),
                        );
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('تم نسخ PGN'),
                          ),
                        );
                      },
                    ),
                    if (_analyzing)
                      ListTile(
                        leading: const Icon(Icons.cancel_outlined),
                        title: const Text('إلغاء التحليل'),
                        onTap: () {
                          Navigator.pop(ctx);
                          _cancelAnalysis();
                        },
                      ),
                    const SizedBox(height: 8),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  // ---------------- مراجعة المباراة (النجمة الخضراء) ----------------

  Future<void> _openReview() async {
    _sheetOpen = true;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(16),
        ),
      ),
      builder: (ctx) {
        final h = MediaQuery.of(ctx).size.height * 0.88;

        return Theme(
          data: _darkTheme(),
          child: ListenableBuilder(
            listenable: _sheetTick,
            builder: (ctx, _) {
              return SizedBox(
                height: h,
                child: Column(
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    TabBar(
                      controller: _tabController,
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      labelColor: _green,
                      unselectedLabelColor: Colors.white70,
                      indicatorColor: _green,
                      tabs: const [
                        Tab(text: 'ملخص'),
                        Tab(text: 'تقرير المباراة'),
                        Tab(text: 'النقلات'),
                        Tab(text: 'الأخطاء'),
                        Tab(text: 'اللحظات الحرجة'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildSummaryTab(),
                          _buildReportTab(),
                          _buildMovesTab(),
                          _buildMistakesTab(),
                          _buildCriticalMomentsTab(),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );

    _sheetOpen = false;
  }

  Widget _buildSummaryTab() {
    if (_analyzing || _qualities.isEmpty) {
      return Center(
        child: Text(
          _analyzing
              ? 'جارٍ تحليل المباراة...'
              : 'لا توجد نتائج تحليل بعد.',
          style: const TextStyle(color: Colors.white70),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _buildAccuracySummary(),
        const SizedBox(height: 12),
        _buildPerformanceCard(),
        if (_maiaPerformance('w') != null ||
            _maiaPerformance('b') != null)
          const SizedBox(height: 12),
        _buildPhaseSummary(),
      ],
    );
  }

  // ------------------------------------------------------------
  // تبويب: نظرة عامة
  // ------------------------------------------------------------

  Widget _buildCurrentMoveInfo() {
    if (_currentIndex == 0) {
      final pv = _pvUci.isNotEmpty
          ? pvToSan(_fens[0], _pvUci[0])
          : '';

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            const Text(
              'الوضعية الابتدائية',
              style: TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            if (pv.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'الخط المقترح: $pv',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                ),
              ),
            ],
          ],
        ),
      );
    }

    final k = _currentIndex - 1;

    if (k >= _qualities.length || k >= _plies.length) {
      return const SizedBox();
    }

    final ply = _plies[k];
    final q = _qualities[k];
    final info = moveQualityInfo[q]!;
    final loss = _lossAt(k);
    final moveNumber = (k ~/ 2) + 1;

    final bestUci = k < _bestUci.length
        ? _bestUci[k]
        : '';

    final bestSan = parseUci(bestUci) != null
        ? pvToSan(_fens[k], [bestUci])
        : '';

    final pv = k < _pvUci.length
        ? pvToSan(_fens[k], _pvUci[k])
        : '';

    final isBestOrBrilliant =
        (k < _isBestEngineMove.length && _isBestEngineMove[k]) ||
        q == MoveQuality.best ||
        q == MoveQuality.brilliant ||
        q == MoveQuality.great ||
        q == MoveQuality.book;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: info.color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: info.color.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Text(
            'النقلة الحالية:  $moveNumber'
            '${ply.color == 'w' ? '.' : '...'} '
            '${ply.san}${_sanSuffix(q)}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                info.icon,
                size: 16,
                color: info.color,
              ),
              const SizedBox(width: 4),
              Text(
                info.label,
                style: TextStyle(
                  color: info.color,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                'خسارة تقييم: '
                '${(loss / 100).toStringAsFixed(2)}',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          if (_bookNoteAt(k) != null) ...[
            const SizedBox(height: 6),
            Text(
              _bookNoteAt(k)!,
              style: TextStyle(
                color: moveQualityInfo[MoveQuality.book]!.color,
                fontSize: 12,
              ),
            ),
          ],
          if (_maiaNoteAt(k) != null) ...[
            const SizedBox(height: 6),
            Text(
              _maiaNoteAt(k)!,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
              ),
            ),
          ],
          if (_tbNoteAt(k) != null) ...[
            const SizedBox(height: 6),
            Text(
              _tbNoteAt(k)!,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
              ),
            ),
          ],
          if (!isBestOrBrilliant &&
              bestSan.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'أفضل نقلة: $bestSan',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (pv.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'الخط الرئيسي: $pv',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAccuracySummary() {
    final acc = _accuracyBySide;
    final acpl = _acplBySide;

    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: 14,
        horizontal: 10,
      ),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment:
                MainAxisAlignment.spaceAround,
            children: [
              _accuracyChip(
                _whiteName,
                acc['w'] ?? 0,
                acpl['w'],
              ),
              _accuracyChip(
                _blackName,
                acc['b'] ?? 0,
                acpl['b'],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'دقة Chess2 — مقياس خاص بالتطبيق، ليس مطابقًا'
            ' لدقة Chess.com',
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _accuracyChip(
    String label,
    double acc,
    double? acpl,
  ) {
    return Column(
      children: [
        Text(
          '${acc.toStringAsFixed(1)}%',
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'دقة Chess2 — $label',
          style: TextStyle(
            fontSize: 12,
            color: Colors.white60,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'ACPL: ${acpl == null ? 'N/A' : acpl.toStringAsFixed(0)}',
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade500,
          ),
        ),
      ],
    );
  }

  Widget _buildPhaseSummary() {
    final byPhase = _accuracyByPhase;

    Widget row(String label, String key) {
      final w = byPhase[key]!['w']!;
      final b = byPhase[key]!['b']!;

      return Padding(
        padding: const EdgeInsets.symmetric(
          vertical: 4,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 90,
              child: Text(label),
            ),
            Expanded(
              child: Text(
                '$_whiteName ${w.toStringAsFixed(0)}%'
                '   •   '
                '$_blackName ${b.toStringAsFixed(0)}%',
                style: TextStyle(
                  color: Colors.white70,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          const Text(
            'مراحل المباراة',
            style: TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          row('الافتتاح', 'opening'),
          row('وسط اللعبة', 'middlegame'),
          row('النهايات', 'endgame'),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  // تبويب: تقرير المباراة
  // ------------------------------------------------------------
  //
  // ملاحظة تصميم مهمة: هذا تبويب ضمن نفس شاشة GameAnalysisScreen
  // (وليس شاشة منفصلة يُنتقل إليها عبر Navigator) عن قصد — لأن
  // فتح شاشة GameAnalysisScreen جديدة يعني إعادة تحليل المباراة
  // بالكامل عبر Stockfish من جديد (initState يبدأ التحليل مباشرة).
  // بما أن التبويب يشارك نفس الـ State الذي يحمل نتائج التحليل
  // المحفوظة أصلًا، فإن "الانتقال إلى النقلة" من التقرير لا يحتاج
  // أكثر من تبديل التبويب + تحديث _currentIndex — بلا أي تحليل
  // إضافي، تمامًا كما يتطلب القسم 14 من الطلب.

  Map<String, _PhaseStat> get _phaseStatsFull {
    final result = <String, _PhaseStat>{};

    for (final phase in [
      'opening',
      'middlegame',
      'endgame',
    ]) {
      var moveCount = 0;
      var errorCount = 0;
      final phaseIdx = <int>[];
      final accData = _accData;

      for (var i = 0; i < _qualities.length; i++) {
        if (_phaseOf(i) != phase) continue;

        moveCount++;
        phaseIdx.add(i);

        final q = _qualities[i];

        if (q == MoveQuality.mistake ||
            q == MoveQuality.blunder ||
            q == MoveQuality.miss) {
          errorCount++;
        }
      }

      result[phase] = _PhaseStat(
        moveCount: moveCount,
        accuracy: moveCount > 0
            ? combineAccuracy(accData, phaseIdx)
            : 0,
        errorCount: errorCount,
      );
    }

    return result;
  }

  Widget _buildReportTab() {
    if (_analyzing) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            'التقرير يظهر بعد اكتمال تحليل المباراة...\n'
            '${(_progress * 100).round()}%',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_plies.isEmpty) {
      return const Center(
        child: Text('لا توجد بيانات كافية للتقرير.'),
      );
    }

    final acc = _accuracyBySide;
    final acplBySide = _acplBySide;
    final countsBySide = _qualityCountsBySide;
    final bestEngineIdx = _bestEngineMoveIndex;
    final brilliantIdx = _brilliantMoveIndex;
    final worstIdx = _worstMoveIndex;
    final missed = _missedOpportunityIndices;
    final opening = _headers['Opening'];
    final eco = _headers['ECO'];

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // --------------------------------------------------
        // معلومات المباراة
        // --------------------------------------------------
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              const Text(
                'تقرير المباراة',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text('الأبيض: $_whiteName'),
              Text('الأسود: $_blackName'),
              if (_resultText.isNotEmpty)
                Text('النتيجة: $_resultText'),
              Text('عدد النقلات: ${_plies.length}'),
              if (opening != null)
                Text('الافتتاح: $opening'
                    '${eco != null ? ' ($eco)' : ''}')
              else if (eco != null)
                Text('رمز الافتتاح (ECO): $eco'),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // --------------------------------------------------
        // ملخص المباراة
        // --------------------------------------------------
        if (_gameSummaryText.isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .primary
                  .withValues(alpha: 0.06),
              borderRadius:
                  BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                const Text(
                  'ملخص المباراة',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(_gameSummaryText),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // --------------------------------------------------
        // إحصائيات الأبيض والأسود
        // --------------------------------------------------
        const Text(
          'إحصائيات اللاعبين',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _playerStatsCard(
                _whiteName,
                acc['w'] ?? 0,
                acplBySide['w'],
                countsBySide['w']!,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _playerStatsCard(
                _blackName,
                acc['b'] ?? 0,
                acplBySide['b'],
                countsBySide['b']!,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // --------------------------------------------------
        // الرسم البياني للتقييم
        // --------------------------------------------------
        const Text(
          'تقييم المباراة',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        _EvalGraph(
          evalPawns: _evalPawns,
          qualities: _qualities,
          moves: _c.results,
          currentIndex: _currentIndex,
          onSelect: (i) => _jumpAndShowBoard(i),
        ),
        const SizedBox(height: 8),
        _buildGraphMoveInfo(),
        const SizedBox(height: 16),

        // --------------------------------------------------
        // أفضل نقلة (Best Engine Move) وأسوأ نقلة
        // --------------------------------------------------
        // ملاحظة: "أفضل نقلة" هنا تعني النقلة المطابقة فعليًا
        // لـ bestUci الخاص بـ Stockfish — وليست بالضرورة
        // النقلة المصنّفة "رائعة!!" (Brilliant قسم منفصل
        // تمامًا تحته، يظهر فقط إن وُجد فعلًا).
        Row(
          children: [
            Expanded(
              child: _bestWorstCard(
                title: 'أفضل نقلة',
                icon: Icons.star_rounded,
                color: const Color(0xFF2AA876),
                plyIndex: bestEngineIdx,
                emptyText:
                    'لم يتم تحديد أفضل نقلة بارزة في'
                    ' هذه المباراة.',
                buttonText: 'عرض النقلة',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _bestWorstCard(
                title: 'أسوأ نقلة',
                icon: Icons.dangerous_rounded,
                color: const Color(0xFFD9483D),
                plyIndex: worstIdx,
                emptyText:
                    'لا توجد أخطاء كبيرة في هذه'
                    ' المباراة.',
                buttonText: 'عرض على الرقعة',
              ),
            ),
          ],
        ),
        if (brilliantIdx != null) ...[
          const SizedBox(height: 10),
          _bestWorstCard(
            title: 'نقلة مدهشة!! (Brilliant)',
            icon: Icons.auto_awesome_rounded,
            color: const Color(0xFF1BADA6),
            plyIndex: brilliantIdx,
            emptyText: '',
            buttonText: 'عرض النقلة',
          ),
        ],
        const SizedBox(height: 16),

        // --------------------------------------------------
        // أهم الأخطاء (أعلى خسارة تقييم)
        // --------------------------------------------------
        const Text(
          'أهم الأخطاء',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (_criticalMoments.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(
              vertical: 8,
            ),
            child: Text('لا توجد أخطاء بارزة تُذكر.'),
          )
        else
          for (final m in _criticalMoments.take(5))
            _mistakeTile(m.plyIndex),
        const SizedBox(height: 16),

        // --------------------------------------------------
        // الفرص الضائعة
        // --------------------------------------------------
        const Text(
          'الفرص الضائعة',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (missed.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(
              vertical: 8,
            ),
            child: Text(
              'لا توجد فرص ضائعة واضحة حسب تحليل'
              ' Stockfish.',
            ),
          )
        else
          for (final i in missed) _mistakeTile(i),
        const SizedBox(height: 16),

        // --------------------------------------------------
        // مراحل المباراة
        // --------------------------------------------------
        const Text(
          'مراحل المباراة',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        _phaseDetailCard('الافتتاح', 'opening'),
        const SizedBox(height: 8),
        _phaseDetailCard('وسط اللعبة', 'middlegame'),
        const SizedBox(height: 8),
        _phaseDetailCard('النهايات', 'endgame'),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _playerStatsCard(
    String name,
    double accuracy,
    double? acpl,
    Map<MoveQuality, int> counts,
  ) {
    Widget row(MoveQuality q) {
      final info = moveQualityInfo[q]!;
      final count = counts[q] ?? 0;

      return Padding(
        padding: const EdgeInsets.symmetric(
          vertical: 2,
        ),
        child: Row(
          children: [
            Icon(info.icon, size: 14, color: info.color),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                info.label,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            Text(
              '$count',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${accuracy.toStringAsFixed(1)}%',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Text(
            'دقة Chess2',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'ACPL: ${acpl == null ? 'N/A' : acpl.toStringAsFixed(0)}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Divider(height: 14),
          for (final q in moveQualityDisplayOrder) row(q),
        ],
      ),
    );
  }

  Widget _bestWorstCard({
    required String title,
    required IconData icon,
    required Color color,
    required int? plyIndex,
    required String emptyText,
    required String buttonText,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 4),
              Text(
                title,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (plyIndex == null)
            Text(
              emptyText,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white70,
              ),
            )
          else ...[
            Text(
              '${(plyIndex ~/ 2) + 1}'
              '${_plies[plyIndex].color == 'w' ? '.' : '...'} '
              '${_plies[plyIndex].san}'
              '${_sanSuffix(_qualities[plyIndex])}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'خسارة تقييم: '
              '${(_lossAt(plyIndex) / 100).toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 34,
              child: OutlinedButton(
                onPressed: () => _jumpAndShowBoard(
                  plyIndex + 1,
                ),
                child: Text(buttonText),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// تفاصيل النقلة المحددة على الرسم البياني (من
  /// `List<MoveAnalysisResult>` نفسها التي تقرأها بقية الواجهة).
  Widget _buildGraphMoveInfo() {
    final results = _c.results;
    final k = _currentIndex - 1;

    if (results.isEmpty || k < 0 || k >= results.length) {
      return Text(
        'اضغط على الرسم لاختيار نقلة.',
        style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
      );
    }

    final r = results[k];
    final info = moveQualityInfo[r.classification]!;

    String loss(int cp) => (cp.clamp(0, 1000) / 100).toStringAsFixed(2);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: r.isCritical
            ? Border.all(color: Colors.amber.withValues(alpha: 0.6))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'النقلة ${r.moveNumber}${r.side == 'w' ? '.' : '...'} '
            '${r.san}  •  ${info.label}'
            '${r.isCritical ? '  •  لحظة حرجة' : ''}',
            style: TextStyle(
              color: info.color,
              fontWeight: FontWeight.bold,
            ),
            textDirection: TextDirection.ltr,
          ),
          const SizedBox(height: 4),
          Text(
            'التقييم قبل: ${_evalLabels[k]}   بعد: ${_evalLabels[k + 1]}   '
            'الخسارة: ${loss(r.evaluationLossCp)}',
            style: const TextStyle(fontSize: 12),
          ),
          if (r.bestMoveSan.isNotEmpty && !r.isBestMove)
            Text(
              'الأفضل: ${r.bestMoveSan}',
              style: const TextStyle(fontSize: 12),
              textDirection: TextDirection.ltr,
            ),
        ],
      ),
    );
  }

  /// ACPL لكل لاعب في مرحلة معيّنة (بوحدة البيدق)، أو null.
  String? _phaseAcplText(String phaseKey) {
    if (_c.results.isEmpty) return null;

    final p = computeAcpl(_c.results).byPhase[phaseKey];

    if (p == null) return null;

    String f(double? v) => v == null ? '—' : (v / 100).toStringAsFixed(2);

    if (p['w'] == null && p['b'] == null) return null;

    return 'ACPL ⚪${f(p['w'])} ⚫${f(p['b'])}';
  }

  Widget _phaseDetailCard(String label, String phaseKey) {
    final stat = _phaseStatsFull[phaseKey]!;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(
              '${stat.moveCount} نقلة',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  'دقة ${stat.accuracy.toStringAsFixed(0)}%',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_phaseAcplText(phaseKey) != null)
                  Text(
                    _phaseAcplText(phaseKey)!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Text(
              'أخطاء: ${stat.errorCount}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: stat.errorCount > 0
                    ? const Color(0xFFD9483D)
                    : Colors.white70,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  // تبويب: النقلات
  // ------------------------------------------------------------

  Widget _buildMovesTab() {
    if (_plies.isEmpty) {
      return const Center(
        child: Text('لا توجد نقلات.'),
      );
    }

    final rows = <Widget>[];

    for (var i = 0; i < _plies.length; i += 2) {
      final whiteP = _plies[i];
      final whiteQ =
          _qualities.length > i ? _qualities[i] : null;

      final hasBlack = i + 1 < _plies.length;
      final blackP = hasBlack ? _plies[i + 1] : null;
      final blackQ =
          hasBlack && _qualities.length > i + 1
              ? _qualities[i + 1]
              : null;

      rows.add(
        Row(
          children: [
            SizedBox(
              width: 32,
              child: Text(
                '${(i ~/ 2) + 1}.',
                style: TextStyle(
                  color: Colors.white60,
                ),
              ),
            ),
            Expanded(
              child: _moveChip(
                whiteP.san,
                whiteQ,
                () => _jumpAndShowBoard(
                  i + 1,
                ),
                isCurrent: _currentIndex == i + 1,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: blackP == null
                  ? const SizedBox()
                  : _moveChip(
                      blackP.san,
                      blackQ,
                      () => _jumpAndShowBoard(
                        i + 2,
                      ),
                      isCurrent:
                          _currentIndex == i + 2,
                    ),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: rows,
    );
  }

  Widget _moveChip(
    String san,
    MoveQuality? q,
    VoidCallback onTap, {
    bool isCurrent = false,
  }) {
    final info =
        q != null ? moveQualityInfo[q] : null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        margin: const EdgeInsets.symmetric(
          vertical: 2,
        ),
        padding: const EdgeInsets.symmetric(
          vertical: 6,
          horizontal: 8,
        ),
        decoration: BoxDecoration(
          color: isCurrent
              ? Theme.of(context)
                  .colorScheme
                  .primary
                  .withValues(alpha: 0.15)
              : (info?.color.withValues(alpha: 0.10) ??
                  Colors.transparent),
          borderRadius: BorderRadius.circular(6),
          border: isCurrent
              ? Border.all(
                  color: Theme.of(context)
                      .colorScheme
                      .primary,
                  width: 1.2,
                )
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (info != null) ...[
              Icon(
                info.icon,
                size: 14,
                color: info.color,
              ),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                '$san'
                '${q != null ? _sanSuffix(q) : ''}',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // تبويب: الأخطاء
  // ------------------------------------------------------------

  Widget _buildMistakesTab() {
    if (_analyzing) {
      return const Center(
        child: Text('التحليل جارٍ...'),
      );
    }

    final counts = _qualityCounts;

    final flagged = <int>[];

    for (var i = 0; i < _qualities.length; i++) {
      final q = _qualities[i];

      if (q == MoveQuality.inaccuracy ||
          q == MoveQuality.mistake ||
          q == MoveQuality.blunder ||
          q == MoveQuality.miss) {
        flagged.add(i);
      }
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final q in [
              MoveQuality.brilliant,
              MoveQuality.best,
              MoveQuality.inaccuracy,
              MoveQuality.mistake,
              MoveQuality.blunder,
              MoveQuality.miss,
            ])
              if ((counts[q] ?? 0) > 0)
                Chip(
                  avatar: Icon(
                    moveQualityInfo[q]!.icon,
                    size: 16,
                    color: moveQualityInfo[q]!.color,
                  ),
                  label: Text(
                    '${moveQualityInfo[q]!.label}:'
                    ' ${counts[q]}',
                  ),
                ),
          ],
        ),
        const SizedBox(height: 12),
        if (flagged.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(
              vertical: 24,
            ),
            child: Text(
              'لا توجد أخطاء أو عدم دقة تُذكر — أداء ممتاز!',
              textAlign: TextAlign.center,
            ),
          )
        else
          for (final i in flagged)
            _mistakeTile(i),
      ],
    );
  }

  Widget _mistakeTile(int i) {
    final ply = _plies[i];
    final q = _qualities[i];
    final info = moveQualityInfo[q]!;
    final loss = _lossAt(i);
    final moveNumber = (i ~/ 2) + 1;

    final bestUci = i < _bestUci.length
        ? _bestUci[i]
        : '';

    return Card(
      margin: const EdgeInsets.symmetric(
        vertical: 4,
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              info.color.withValues(alpha: 0.15),
          child: Icon(info.icon, color: info.color),
        ),
        title: Text(
          'النقلة $moveNumber'
          '${ply.color == 'w' ? '.' : '...'} '
          '${ply.san}${_sanSuffix(q)}',
        ),
        subtitle: Text(
          '${info.label} • خسارة تقييم'
          ' ${(loss / 100).toStringAsFixed(2)}'
          '${parseUci(bestUci) != null ? ' • الأفضل: '
              '${parseUci(bestUci)!.from}'
              '${parseUci(bestUci)!.to}' : ''}',
        ),
        onTap: () =>
            _jumpAndShowBoard(i + 1),
      ),
    );
  }

  // ------------------------------------------------------------
  // تبويب: اللحظات الحرجة
  // ------------------------------------------------------------

  Widget _buildCriticalMomentsTab() {
    if (_analyzing) {
      return const Center(
        child: Text('التحليل جارٍ...'),
      );
    }

    final moments = _criticalMoments;

    if (moments.isEmpty) {
      return const Center(
        child: Text(
          'لا توجد لحظات حرجة بارزة في هذه المباراة.',
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: moments.length,
      itemBuilder: (context, index) {
        final m = moments[index];
        final ply = _plies[m.plyIndex];
        final info = moveQualityInfo[m.quality]!;
        final moveNumber = (m.plyIndex ~/ 2) + 1;

        return Card(
          margin: const EdgeInsets.symmetric(
            vertical: 4,
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor:
                  info.color.withValues(alpha: 0.15),
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  color: info.color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(
              'النقلة $moveNumber'
              '${ply.color == 'w' ? '.' : '...'} '
              '${ply.san}${_sanSuffix(m.quality)}',
            ),
            subtitle: Text(
              m.kind == 'only_move'
                  ? '${info.label} • نقلة وحيدة أُدّيت بدقة'
                  : (m.kind == 'tablebase'
                      ? '${info.label} • تغيّرت النتيجة المضمونة '
                          '(Tablebase)'
                      : '${info.label} • خسارة تقييم'
                          ' ${(m.lossCp / 100).toStringAsFixed(2)}'),
            ),
            onTap: () => _jumpAndShowBoard(
              m.plyIndex + 1,
            ),
          ),
        );
      },
    );
  }
}

// ================================================================
// شريط التقييم الجانبي
// ================================================================

// ================================================================
// نتيجة تقييم وضعية واحدة / لحظة حرجة
// ================================================================

class _CriticalMoment {
  final int plyIndex;
  final MoveQuality quality;
  final int lossCp;
  final double score;

  /// swing / only_move / tablebase
  final String kind;

  const _CriticalMoment({
    required this.plyIndex,
    required this.quality,
    required this.lossCp,
    this.score = 0,
    this.kind = 'swing',
  });
}

class _PhaseStat {
  final int moveCount;
  final double accuracy;
  final int errorCount;

  const _PhaseStat({
    required this.moveCount,
    required this.accuracy,
    required this.errorCount,
  });
}

// ================================================================
// الرسم البياني للتقييم — مرسوم يدويًا (CustomPainter) بدون أي
// مكتبة خارجية، مع دعم الضغط لأقرب نقطة نقلة كما طُلب صراحة.
// ================================================================

class _EvalGraph extends StatelessWidget {
  final List<double> evalPawns;
  final List<MoveQuality> qualities;
  final List<MoveAnalysisResult> moves;
  final int currentIndex;
  final void Function(int index) onSelect;

  const _EvalGraph({
    required this.evalPawns,
    required this.qualities,
    required this.moves,
    required this.currentIndex,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (evalPawns.length < 2) {
      return const SizedBox(
        height: 120,
        child: Center(
          child: Text('لا توجد بيانات كافية للرسم.'),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        const height = 140.0;

        void handleTap(Offset local) {
          final dx = local.dx.clamp(0, width);

          final idx = width <= 0
              ? 0
              : (dx / width * (evalPawns.length - 1))
                  .round()
                  .clamp(0, evalPawns.length - 1);

          onSelect(idx);
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) =>
              handleTap(d.localPosition),
          onHorizontalDragUpdate: (d) =>
              handleTap(d.localPosition),
          child: CustomPaint(
            size: Size(width, height),
            painter: _EvalGraphPainter(
              evalPawns: evalPawns,
              qualities: qualities,
              moves: moves,
              currentIndex: currentIndex,
            ),
          ),
        );
      },
    );
  }
}

class _EvalGraphPainter extends CustomPainter {
  final List<double> evalPawns;
  final List<MoveQuality> qualities;
  final List<MoveAnalysisResult> moves;
  final int currentIndex;

  const _EvalGraphPainter({
    required this.evalPawns,
    required this.qualities,
    required this.moves,
    required this.currentIndex,
  });

  static const double _cap = 5.0;

  double _xAt(int i, int n, double width) =>
      n <= 1 ? 0 : (i / (n - 1)) * width;

  double _yAt(double pawns, double height) {
    final clamped = pawns.clamp(-_cap, _cap);
    final mid = height / 2;
    return mid - (clamped / _cap) * mid;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final n = evalPawns.length;

    if (n < 2) return;

    final mid = size.height / 2;

    // الخلفية: نصف فاتح (أبيض أفضل) ونصف غامق (أسود أفضل).
    final whiteBg = Paint()
      ..color = Colors.grey.withValues(alpha: 0.08);
    final blackBg = Paint()
      ..color = Colors.grey.withValues(alpha: 0.18);

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, mid),
      whiteBg,
    );
    canvas.drawRect(
      Rect.fromLTWH(0, mid, size.width, mid),
      blackBg,
    );

    final zeroPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.5)
      ..strokeWidth = 1;

    canvas.drawLine(
      Offset(0, mid),
      Offset(size.width, mid),
      zeroPaint,
    );

    // خط التقييم.
    final path = Path();

    path.moveTo(
      _xAt(0, n, size.width),
      _yAt(evalPawns[0], size.height),
    );

    for (var i = 1; i < n; i++) {
      path.lineTo(
        _xAt(i, n, size.width),
        _yAt(evalPawns[i], size.height),
      );
    }

    final linePaint = Paint()
      ..color = Colors.indigo
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawPath(path, linePaint);

    // نقاط ملوّنة عند الأخطاء/الفرص الضائعة.
    for (var i = 0; i < qualities.length; i++) {
      final q = qualities[i];

      if (q == MoveQuality.blunder ||
          q == MoveQuality.mistake ||
          q == MoveQuality.miss) {
        final color = moveQualityInfo[q]!.color;

        canvas.drawCircle(
          Offset(
            _xAt(i + 1, n, size.width),
            _yAt(evalPawns[i + 1], size.height),
          ),
          3.5,
          Paint()..color = color,
        );
      }
    }

    // علامات إضافية من List<MoveAnalysisResult>: رائعة / مدهشة
    // بنقطة، واللحظات الحرجة بحلقة ذهبية.
    for (final m in moves) {
      final idx = m.ply + 1;

      if (idx >= n || idx >= evalPawns.length) continue;

      final center = Offset(
        _xAt(idx, n, size.width),
        _yAt(evalPawns[idx], size.height),
      );

      if (m.classification == MoveQuality.brilliant ||
          m.classification == MoveQuality.great) {
        canvas.drawCircle(
          center,
          3.5,
          Paint()..color = moveQualityInfo[m.classification]!.color,
        );
      }

      if (m.isCritical) {
        canvas.drawCircle(
          center,
          6.5,
          Paint()
            ..color = Colors.amber
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6,
        );
      }
    }

    // مؤشر الموضع الحالي.
    if (currentIndex >= 0 && currentIndex < n) {
      final x = _xAt(currentIndex, n, size.width);

      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = Colors.red.withValues(alpha: 0.4)
          ..strokeWidth = 1,
      );

      canvas.drawCircle(
        Offset(
          x,
          _yAt(evalPawns[currentIndex], size.height),
        ),
        4.5,
        Paint()..color = Colors.red,
      );
    }
  }

  @override
  bool shouldRepaint(
    covariant _EvalGraphPainter oldDelegate,
  ) {
    return oldDelegate.currentIndex != currentIndex ||
        oldDelegate.evalPawns != evalPawns ||
        oldDelegate.qualities != qualities ||
        oldDelegate.moves != moves;
  }
}


/// زر الشريط السفلي (أيقونة + عنوان) مع تكرار عند الضغط المطوّل.
class _BarButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;
  final bool repeat;

  const _BarButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.repeat = false,
  });

  @override
  State<_BarButton> createState() => _BarButtonState();
}

class _BarButtonState extends State<_BarButton> {
  Timer? _timer;

  void _start() {
    if (!widget.repeat) return;

    _timer?.cancel();

    _timer = Timer.periodic(
      const Duration(milliseconds: 200),
      (_) {
        if (!widget.enabled) {
          _stop();
          return;
        }

        widget.onTap();
      },
    );
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.enabled
        ? Colors.white.withValues(alpha: 0.85)
        : Colors.white.withValues(alpha: 0.25);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.enabled ? widget.onTap : null,
      onLongPressStart: (_) {
        if (!widget.enabled) return;
        widget.onTap();
        _start();
      },
      onLongPressEnd: (_) => _stop(),
      onLongPressCancel: _stop,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(widget.icon, size: 38, color: color),
            const SizedBox(height: 2),
            Text(
              widget.label,
              style: TextStyle(color: color, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}


/// رسم التقييم في صفحة الإحصائيات: خلفية داكنة، والمنطقة تحت الخط
/// بيضاء (كلما ارتفع الخط كان الأبيض أفضل)، ونقاط ملوّنة عند
/// الأخطاء والخطأ الفادح والفرص الضائعة.
class _SummaryGraphPainter extends CustomPainter {
  final List<double> evalPawns;
  final List<MoveQuality> qualities;

  const _SummaryGraphPainter({
    required this.evalPawns,
    required this.qualities,
  });

  static const double _cap = 5.0;

  double _x(int i, int n, double w) =>
      n <= 1 ? 0 : (i / (n - 1)) * w;

  double _y(double pawns, double h) {
    final c = pawns.clamp(-_cap, _cap).toDouble();
    final mid = h / 2;
    return mid - (c / _cap) * mid;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final n = evalPawns.length;

    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF454341),
    );

    if (n < 2) return;

    final path = Path()..moveTo(0, _y(evalPawns[0], size.height));

    for (var i = 1; i < n; i++) {
      path.lineTo(
        _x(i, n, size.width),
        _y(evalPawns[i], size.height),
      );
    }

    path
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      path,
      Paint()..color = const Color(0xFFF0F0F0),
    );

    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      Paint()
        ..color = const Color(0xFF9A9895)
        ..strokeWidth = 1,
    );

    for (var i = 0; i < qualities.length && i + 1 < n; i++) {
      final q = qualities[i];

      if (q == MoveQuality.blunder ||
          q == MoveQuality.mistake ||
          q == MoveQuality.miss) {
        canvas.drawCircle(
          Offset(
            _x(i + 1, n, size.width),
            _y(evalPawns[i + 1], size.height),
          ),
          5,
          Paint()..color = moveQualityInfo[q]!.color,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SummaryGraphPainter old) {
    return old.evalPawns != evalPawns ||
        old.qualities != qualities;
  }
}
