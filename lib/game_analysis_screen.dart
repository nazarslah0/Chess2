import 'dart:async';

import 'package:chess/chess.dart' as ch;
import 'package:flutter/material.dart';

import 'models.dart';
import 'engine_service.dart';
import 'board_widget.dart';
import 'pgn_utils.dart';
import 'game_review_models.dart';

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
  final EngineService _engine = EngineService();
  final GameState _boardState = GameState();

  late final TabController _tabController =
      TabController(length: 4, vsync: this);

  String? _parseError;

  List<PgnPly> _plies = <PgnPly>[];
  List<String> _fens = <String>[];
  List<double> _evalPawns = <double>[];
  List<String> _evalLabels = <String>[];
  List<String> _bestUci = <String>[];
  List<MoveQuality> _qualities = <MoveQuality>[];

  Map<String, String> _headers = <String, String>{};

  int _currentIndex = 0;

  bool _analyzing = false;
  double _progress = 0;

  final double _depth = 14;

  int _requestToken = 0;

  @override
  void initState() {
    super.initState();

    _headers = extractPgnHeaders(widget.pgn);

    final plies = parsePgnMoves(widget.pgn);

    if (plies == null || plies.isEmpty) {
      _parseError =
          'تعذر قراءة نقلات هذه المباراة (PGN غير مدعوم).';
      return;
    }

    _plies = plies;

    _fens = <String>[
      plies.first.fenBefore,
      for (final p in plies) p.fenAfter,
    ];

    _evalPawns =
        List<double>.filled(_fens.length, 0.0);
    _evalLabels =
        List<String>.filled(_fens.length, '0.00');
    _bestUci = List<String>.filled(_fens.length, '');

    _boardState.loadFen(_fens.first);

    _engine.init();

    _analyzing = true;

    final myToken = ++_requestToken;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runAnalysis(myToken);
    });
  }

  @override
  void dispose() {
    _engine.dispose();
    _boardState.dispose();
    _tabController.dispose();
    super.dispose();
  }

  String get _whiteName =>
      widget.whiteLabel ?? _headers['White'] ?? 'أبيض';

  String get _blackName =>
      widget.blackLabel ?? _headers['Black'] ?? 'أسود';

  String get _resultText =>
      widget.resultLabel ?? _headers['Result'] ?? '';

  // ============================================================
  // التحليل الكامل للمباراة
  // ============================================================

  Future<_Eval> _evaluatePosition(String fen) {
    final completer = Completer<_Eval>();

    double lastPawns = 0;
    String lastLabel = '0.00';

    _engine.onInfo = (multipv, line) {
      if (multipv == 1) {
        lastPawns = line.evalPawns;
        lastLabel = line.evalLabel;
      }
    };

    _engine.onBestMove = (uci) {
      if (!completer.isCompleted) {
        completer.complete(
          _Eval(lastPawns, lastLabel, uci),
        );
      }
    };

    _engine.analyze(
      fen,
      depth: _depth.round(),
      multiPv: 1,
    );

    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () =>
          _Eval(lastPawns, lastLabel, ''),
    );
  }

  Future<void> _runAnalysis(int token) async {
    if (!_engine.ready) {
      await _engine.init();

      var waited = 0;
      while (!_engine.ready && waited < 8000) {
        await Future.delayed(
          const Duration(milliseconds: 200),
        );
        waited += 200;
      }
    }

    for (var i = 0; i < _fens.length; i++) {
      if (!mounted || token != _requestToken) {
        return;
      }

      final r = await _evaluatePosition(_fens[i]);

      if (!mounted || token != _requestToken) {
        return;
      }

      _evalPawns[i] = r.pawns;
      _evalLabels[i] = r.label;
      _bestUci[i] = r.bestUci;

      setState(() {
        _progress = (i + 1) / _fens.length;
      });
    }

    final qualities = <MoveQuality>[];

    for (var i = 0; i < _plies.length; i++) {
      final p = _plies[i];

      final cpBefore = cpFromWhitePerspective(
        _evalPawns[i],
        _evalLabels[i],
      );

      final cpAfter = cpFromWhitePerspective(
        _evalPawns[i + 1],
        _evalLabels[i + 1],
      );

      final bestUci = _bestUci[i];
      final playedUci = '${p.from}${p.to}';

      final wasBest = bestUci.isNotEmpty &&
          bestUci.startsWith(playedUci);

      var quality = classifyMove(
        cpBeforeWhite: cpBefore,
        cpAfterWhite: cpAfter,
        color: p.color,
        wasBestMove: wasBest,
      );

      if (quality == MoveQuality.best) {
        final sign = p.color == 'w' ? 1 : -1;
        final cpBeforeMover = cpBefore * sign;

        final upgraded = _tryUpgradeToBrilliant(
          ply: p,
          baseQuality: quality,
          cpBeforeMover: cpBeforeMover,
        );

        if (upgraded != null) {
          quality = upgraded;
        }
      }

      qualities.add(quality);
    }

    if (!mounted || token != _requestToken) {
      return;
    }

    setState(() {
      _qualities = qualities;
      _analyzing = false;
      _currentIndex = _fens.length - 1;
    });

    _boardState.loadFen(_fens.last);
  }

  // ============================================================
  // كشف تقريبي لنقلة "رائعة!!" (تضحية حقيقية + أفضل نقلة)
  // ============================================================

  MoveQuality? _tryUpgradeToBrilliant({
    required PgnPly ply,
    required MoveQuality baseQuality,
    required int cpBeforeMover,
  }) {
    try {
      final boardBefore = GameState.parseBoard(
        ply.fenBefore.split(' ').first,
      );

      final movingPiece = boardBefore[ply.from];

      if (movingPiece == null ||
          movingPiece.length != 2) {
        return null;
      }

      final movingType = movingPiece[1];

      if (movingType == 'P' ||
          movingType == 'K') {
        return null;
      }

      int capturedValue = 0;

      if (ply.isCapture) {
        final capturedPiece = boardBefore[ply.to];

        if (capturedPiece != null &&
            capturedPiece.length == 2) {
          capturedValue =
              pieceValues[capturedPiece[1]] ?? 0;
        } else {
          capturedValue = 1;
        }
      }

      final movingValue =
          pieceValues[movingType] ?? 0;

      final sacrificedValue =
          movingValue - capturedValue;

      if (sacrificedValue < 2) {
        return null;
      }

      final afterGame = ch.Chess();
      afterGame.load(ply.fenAfter);

      List<dynamic> opponentMoves = [];

      try {
        opponentMoves = afterGame.moves(
          <String, dynamic>{'verbose': true},
        );
      } catch (_) {
        opponentMoves = [];
      }

      var opponentCanCapture = false;

      for (final m in opponentMoves) {
        String? to;

        try {
          to = m is Map
              ? m['to']?.toString()
              : (m as dynamic).toAlgebraic as String;
        } catch (_) {
          to = null;
        }

        if (to == ply.to) {
          opponentCanCapture = true;
          break;
        }
      }

      if (!opponentCanCapture) {
        return null;
      }

      final beforeGame = ch.Chess();
      beforeGame.load(ply.fenBefore);

      var legalCount = 0;

      try {
        legalCount = beforeGame.moves().length;
      } catch (_) {
        legalCount = 2;
      }

      final brilliant = isBrilliantCandidate(
        baseQuality: baseQuality,
        isSacrifice: true,
        cpBeforeMover: cpBeforeMover,
        onlyLegalMove: legalCount <= 1,
        movingPieceType: movingType,
      );

      return brilliant ? MoveQuality.brilliant : null;
    } catch (_) {
      return null;
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
  }

  /// ينتقل إلى النقلة رقم [index] ويحوّل التبويب إلى "نظرة
  /// عامة" حتى تظهر الرقعة والسهم مباشرة (يُستخدم من تبويبي
  /// الأخطاء واللحظات الحرجة).
  void _jumpAndShowBoard(int index) {
    _goTo(index);
    _tabController.animateTo(0);
  }

  BoardArrow _decodeArrow(String uci, Color color) {
    return BoardArrow(
      from: uci.substring(0, 2),
      to: uci.substring(2, 4),
      color: color,
    );
  }

  List<BoardArrow> _arrowsForCurrent() {
    if (_plies.isEmpty || _fens.isEmpty) {
      return const <BoardArrow>[];
    }

    final arrows = <BoardArrow>[];

    if (_currentIndex == 0) {
      if (_bestUci.isNotEmpty &&
          _bestUci[0].length >= 4) {
        arrows.add(
          _decodeArrow(
            _bestUci[0],
            Colors.green.withOpacity(0.85),
          ),
        );
      }

      return arrows;
    }

    final k = _currentIndex - 1;

    if (k < _qualities.length) {
      final ply = _plies[k];
      final color =
          moveQualityInfo[_qualities[k]]!.color;

      arrows.add(
        BoardArrow(
          from: ply.from,
          to: ply.to,
          color: color,
        ),
      );

      if (_qualities[k] != MoveQuality.best &&
          _qualities[k] != MoveQuality.brilliant &&
          k < _bestUci.length &&
          _bestUci[k].length >= 4) {
        arrows.add(
          _decodeArrow(
            _bestUci[k],
            Colors.green.withOpacity(0.85),
          ),
        );
      }
    }

    return arrows;
  }

  // ============================================================
  // حسابات تقرير المباراة (الدقة، مراحل اللعبة، اللحظات الحرجة)
  // ============================================================

  /// خسارة التقييم بوحدة القرن من منظور اللاعب الذي لعب
  /// النقلة رقم i (قيمة موجبة = تراجع).
  int _lossAt(int i) {
    final before = cpFromWhitePerspective(
      _evalPawns[i],
      _evalLabels[i],
    );

    final after = cpFromWhitePerspective(
      _evalPawns[i + 1],
      _evalLabels[i + 1],
    );

    final sign = _plies[i].color == 'w' ? 1 : -1;

    return (before * sign) - (after * sign);
  }

  double _accuracyAt(int i) {
    final before = cpFromWhitePerspective(
      _evalPawns[i],
      _evalLabels[i],
    );

    final after = cpFromWhitePerspective(
      _evalPawns[i + 1],
      _evalLabels[i + 1],
    );

    final wpBefore = winPercentWhite(before);
    final wpAfter = winPercentWhite(after);

    final color = _plies[i].color;

    final wpBeforeMover =
        color == 'w' ? wpBefore : 100 - wpBefore;
    final wpAfterMover =
        color == 'w' ? wpAfter : 100 - wpAfter;

    return moveAccuracy(
      winPercentBeforeMover: wpBeforeMover,
      winPercentAfterMover: wpAfterMover,
    );
  }

  /// عدد نقاط المادة (بدون بيادق وملوك) على الرقعة عند FEN
  /// معيّن — يُستخدم لتحديد بداية النهايات.
  int _nonPawnMaterial(String fen) {
    final board = GameState.parseBoard(
      fen.split(' ').first,
    );

    var total = 0;

    for (final piece in board.values) {
      if (piece.length != 2) continue;
      final t = piece[1];
      if (t == 'P' || t == 'K') continue;
      total += pieceValues[t] ?? 0;
    }

    return total;
  }

  /// index أول نقلة تدخل بها المباراة مرحلة النهايات، أو
  /// طول المباراة إن لم تصله (لا نهايات).
  int get _endgameStartPly {
    for (var i = 0; i < _fens.length; i++) {
      if (_nonPawnMaterial(_fens[i]) <= 12) {
        return i;
      }
    }

    return _plies.length;
  }

  int get _openingEndPly =>
      _plies.length < 20 ? _plies.length : 20;

  String _phaseOf(int plyIndex) {
    if (plyIndex < _openingEndPly) return 'opening';
    if (plyIndex >= _endgameStartPly) return 'endgame';
    return 'middlegame';
  }

  Map<String, double> get _accuracyBySide {
    if (_qualities.isEmpty) {
      return {'w': 0, 'b': 0};
    }

    double whiteSum = 0, blackSum = 0;
    int whiteN = 0, blackN = 0;

    for (var i = 0; i < _plies.length; i++) {
      final acc = _accuracyAt(i);

      if (_plies[i].color == 'w') {
        whiteSum += acc;
        whiteN++;
      } else {
        blackSum += acc;
        blackN++;
      }
    }

    return {
      'w': whiteN > 0 ? whiteSum / whiteN : 0,
      'b': blackN > 0 ? blackSum / blackN : 0,
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

    for (var i = 0; i < _plies.length; i++) {
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

  /// أكبر اللحظات الحرجة (أخطاء/فرص ضائعة) مرتبة تنازليًا حسب
  /// حجم خسارة التقييم.
  List<_CriticalMoment> get _criticalMoments {
    final moments = <_CriticalMoment>[];

    for (var i = 0; i < _qualities.length; i++) {
      final q = _qualities[i];

      if (q == MoveQuality.mistake ||
          q == MoveQuality.blunder ||
          q == MoveQuality.miss) {
        moments.add(
          _CriticalMoment(
            plyIndex: i,
            quality: q,
            lossCp: _lossAt(i),
          ),
        );
      }
    }

    moments.sort(
      (a, b) => b.lossCp.compareTo(a.lossCp),
    );

    return moments.take(8).toList();
  }

  // ============================================================
  // Build
  // ============================================================

  @override
  Widget build(BuildContext context) {
    if (_parseError != null) {
      return Scaffold(
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
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('$_whiteName ضد $_blackName'),
        actions: [
          IconButton(
            tooltip: 'قلب الرقعة',
            icon: const Icon(
              Icons.swap_vert_rounded,
            ),
            onPressed: () {
              setState(() {
                _boardState.flipBoard();
              });
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'نظرة عامة'),
            Tab(text: 'النقلات'),
            Tab(text: 'الأخطاء'),
            Tab(text: 'اللحظات الحرجة'),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_analyzing)
              LinearProgressIndicator(
                value: _progress,
              ),
            if (_analyzing)
              Padding(
                padding:
                    const EdgeInsets.symmetric(
                  vertical: 6,
                ),
                child: Text(
                  'جارٍ تحليل المباراة... '
                  '${(_progress * 100).round()}%'
                  ' ($_currentIndex/'
                  '${_fens.isEmpty ? 0 : _fens.length - 1})',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall,
                ),
              ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildOverviewTab(),
                  _buildMovesTab(),
                  _buildMistakesTab(),
                  _buildCriticalMomentsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // تبويب: نظرة عامة
  // ------------------------------------------------------------

  Widget _buildOverviewTab() {
    final hasEval = _evalPawns.isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          if (_resultText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(
                bottom: 8,
              ),
              child: Text(
                _resultText,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          Row(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              _EvalBar(
                pawns: hasEval
                    ? _evalPawns[_currentIndex]
                    : 0,
                label: hasEval
                    ? _evalLabels[_currentIndex]
                    : '0.00',
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: BoardWidget(
                    state: _boardState,
                    boardTheme: boardThemes[0],
                    pieceTheme: pieceThemes[0],
                    onTap: (_) {},
                    arrows: _arrowsForCurrent(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildNavControls(),
          const SizedBox(height: 12),
          if (!_analyzing && _qualities.isNotEmpty)
            _buildAccuracySummary(),
          const SizedBox(height: 12),
          if (!_analyzing && _qualities.isNotEmpty)
            _buildPhaseSummary(),
        ],
      ),
    );
  }

  Widget _buildNavControls() {
    final atStart = _currentIndex <= 0;
    final atEnd = _currentIndex >= _fens.length - 1;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: 'البداية',
          onPressed:
              atStart ? null : () => _goTo(0),
          icon: const Icon(Icons.skip_previous),
        ),
        IconButton(
          tooltip: 'السابقة',
          onPressed: atStart
              ? null
              : () => _goTo(_currentIndex - 1),
          icon: const Icon(Icons.navigate_before),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
          ),
          child: Text(
            '$_currentIndex / '
            '${_fens.isEmpty ? 0 : _fens.length - 1}',
          ),
        ),
        IconButton(
          tooltip: 'التالية',
          onPressed: atEnd
              ? null
              : () => _goTo(_currentIndex + 1),
          icon: const Icon(Icons.navigate_next),
        ),
        IconButton(
          tooltip: 'النهاية',
          onPressed: atEnd
              ? null
              : () => _goTo(_fens.length - 1),
          icon: const Icon(Icons.skip_next),
        ),
      ],
    );
  }

  Widget _buildAccuracySummary() {
    final acc = _accuracyBySide;

    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: 14,
        horizontal: 10,
      ),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment:
            MainAxisAlignment.spaceAround,
        children: [
          _accuracyChip(_whiteName, acc['w'] ?? 0),
          _accuracyChip(_blackName, acc['b'] ?? 0),
        ],
      ),
    );
  }

  Widget _accuracyChip(String label, double acc) {
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
          'دقة $label',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
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
                  color: Colors.grey.shade700,
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
        color: Colors.grey.withOpacity(0.06),
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
                  color: Colors.grey.shade600,
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
                  .withOpacity(0.15)
              : (info?.color.withOpacity(0.10) ??
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
                san,
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
              info.color.withOpacity(0.15),
          child: Icon(info.icon, color: info.color),
        ),
        title: Text(
          'النقلة $moveNumber'
          '${ply.color == 'w' ? '.' : '...'} '
          '${ply.san}',
        ),
        subtitle: Text(
          '${info.label} • خسارة تقييم'
          ' ${(loss / 100).toStringAsFixed(2)}'
          '${bestUci.length >= 4 ? ' • الأفضل: '
              '${bestUci.substring(0, 2)}'
              '${bestUci.substring(2, 4)}' : ''}',
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
                  info.color.withOpacity(0.15),
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
              '${ply.san}',
            ),
            subtitle: Text(
              '${info.label} • خسارة تقييم'
              ' ${(m.lossCp / 100).toStringAsFixed(2)}',
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

class _EvalBar extends StatelessWidget {
  final double pawns;
  final String label;

  const _EvalBar({
    required this.pawns,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final clamped = pawns.clamp(-8, 8);

    final whiteFraction =
        ((clamped + 8) / 16).clamp(0.0, 1.0);

    return SizedBox(
      width: 30,
      child: Column(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius:
                  BorderRadius.circular(4),
              child: Container(
                color: const Color(0xFF2B2B2B),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: FractionallySizedBox(
                    heightFactor: whiteFraction,
                    widthFactor: 1,
                    child: Container(
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 10),
          ),
        ],
      ),
    );
  }
}

// ================================================================
// نتيجة تقييم وضعية واحدة / لحظة حرجة
// ================================================================

class _Eval {
  final double pawns;
  final String label;
  final String bestUci;

  const _Eval(this.pawns, this.label, this.bestUci);
}

class _CriticalMoment {
  final int plyIndex;
  final MoveQuality quality;
  final int lossCp;

  const _CriticalMoment({
    required this.plyIndex,
    required this.quality,
    required this.lossCp,
  });
}
