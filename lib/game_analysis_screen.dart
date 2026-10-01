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
      TabController(length: 5, vsync: this);

  String? _parseError;

  List<PgnPly> _plies = <PgnPly>[];
  List<String> _fens = <String>[];
  List<double> _evalPawns = <double>[];
  List<String> _evalLabels = <String>[];
  List<String> _bestUci = <String>[];
  List<List<String>> _pvUci = <List<String>>[];
  List<MoveQuality> _qualities = <MoveQuality>[];

  Map<String, String> _headers = <String, String>{};

  int _currentIndex = 0;

  bool _analyzing = false;
  double _progress = 0;
  String _analysisStage = 'تهيئة';
  int _analysisDone = 0;
  int _analysisTotal = 0;

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
    _pvUci = List<List<String>>.generate(
      _fens.length,
      (_) => const <String>[],
    );

    _boardState.loadFen(_fens.first);

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
  // التحليل السريع + التحليل العميق للمرشحين
  // ============================================================

  String _normalizeUci(String value) {
    final v = value.trim().toLowerCase();
    if (v.length < 4) return '';
    final promotion = v.length > 4 ? v.substring(4, 5) : '';
    return '${v.substring(0, 4)}$promotion';
  }

  String _playedUci(PgnPly ply) {
    final promotion =
        ply.promotion?.trim().toLowerCase() ?? '';
    return '${ply.from.toLowerCase()}'
        '${ply.to.toLowerCase()}'
        '$promotion';
  }

  bool _uciMatchesPlayed(
    String bestUci,
    PgnPly ply,
  ) {
    final best = _normalizeUci(bestUci);
    final played = _normalizeUci(_playedUci(ply));

    return best.isNotEmpty &&
        played.isNotEmpty &&
        best == played;
  }

  bool _looksLikeDeepCandidate(
    int i,
    List<EnginePositionResult> fast,
  ) {
    if (i < 0 || i >= _plies.length) return false;

    final p = _plies[i];

    final before = cpFromWhitePerspective(
      fast[i].evalPawns,
      fast[i].evalLabel,
    );

    final after = cpFromWhitePerspective(
      fast[i + 1].evalPawns,
      fast[i + 1].evalLabel,
    );

    final sign = p.color == 'w' ? 1 : -1;
    final loss = (before * sign) - (after * sign);

    // المرشحون الرئيسيون للتحليل العميق:
    // 1) فقد كبير في التقييم.
    // 2) النقلة ليست أفضل نقلة للمحرك.
    // 3) تغير حاد في التقييم.
    // 4) نقلات أخذ/تضحية قد تكون Brilliant.
    final bestMatches =
        _uciMatchesPlayed(fast[i].bestUci, p);

    if (loss.abs() >= 60) return true;
    if (!bestMatches && loss >= 30) return true;
    if (loss.abs() >= 90) return true;

    final piece =
        GameState.parseBoard(
          p.fenBefore.split(' ').first,
        )[p.from];

    if (piece != null &&
        piece.length == 2 &&
        piece[1] != 'P' &&
        piece[1] != 'K' &&
        p.isCapture) {
      return true;
    }

    return false;
  }

  Future<void> _runAnalysis(int token) async {
    try {
      await _engine.init();

      _analysisStage = 'التحليل السريع';
      _analysisDone = 0;
      _progress = 0;

      if (mounted) {
        setState(() {});
      }

      // ----------------------------------------------------------
      // Pass 1: تحليل سريع متوازي على عدة أنوية.
      // ----------------------------------------------------------
      final workerCount =
          _engine.recommendedWorkerCount;

      final fastResults =
          await _engine.analyzePositionsParallel(
        _fens,
        workerCount: workerCount,
        depth: 11,
        movetimeMs: 110,
        onProgress: (done, total) {
          if (!mounted || token != _requestToken) return;

          setState(() {
            _analysisDone = done;
            _analysisTotal = total;
            _progress =
                total == 0 ? 0 : (done / total) * 0.70;
          });
        },
      );

      if (!mounted || token != _requestToken) return;

      for (var i = 0; i < fastResults.length; i++) {
        _evalPawns[i] = fastResults[i].evalPawns;
        _evalLabels[i] = fastResults[i].evalLabel;
        _bestUci[i] = fastResults[i].bestUci;
        _pvUci[i] = fastResults[i].pv;
      }

      // ----------------------------------------------------------
      // اكتشاف المرشحين قبل التحليل العميق.
      // نعيد فحص الوضعيات المهمة فقط، بدل رفع العمق للمباراة
      // كلها.
      // ----------------------------------------------------------
      final candidatePositions = <int>{};

      for (var i = 0; i < _plies.length; i++) {
        if (_looksLikeDeepCandidate(i, fastResults)) {
          candidatePositions.add(i);
          candidatePositions.add(i + 1);
        }
      }

      // دائمًا نضمن فحص أول وآخر وضعية.
      candidatePositions.add(0);
      candidatePositions.add(_fens.length - 1);

      final sortedCandidates =
          candidatePositions
              .where((i) => i >= 0 && i < _fens.length)
              .toList()
            ..sort();

      // ----------------------------------------------------------
      // Pass 2: تحليل عميق للمرشحين فقط.
      // ----------------------------------------------------------
      if (sortedCandidates.isNotEmpty) {
        _analysisStage = 'التحليل العميق للنقلات المهمة';
        _analysisDone = 0;
        _analysisTotal = sortedCandidates.length;

        if (mounted) {
          setState(() {});
        }

        final candidateFens = sortedCandidates
            .map((i) => _fens[i])
            .toList(growable: false);

        final deepResults =
            await _engine.analyzePositionsParallel(
          candidateFens,
          workerCount: workerCount,
          depth: 18,
          movetimeMs: 320,
          onProgress: (done, total) {
            if (!mounted || token != _requestToken) return;

            setState(() {
              _analysisDone = done;
              _analysisTotal = total;
              _progress =
                  0.70 +
                  (total == 0
                          ? 0
                          : done / total) *
                      0.30;
            });
          },
        );

        if (!mounted || token != _requestToken) return;

        for (var j = 0;
            j < sortedCandidates.length &&
                j < deepResults.length;
            j++) {
          final index = sortedCandidates[j];
          final result = deepResults[j];

          _evalPawns[index] = result.evalPawns;
          _evalLabels[index] = result.evalLabel;
          _bestUci[index] = result.bestUci;
          _pvUci[index] = result.pv;
        }
      }

      // ----------------------------------------------------------
      // التصنيف النهائي بعد انتهاء التحليل العميق.
      // ----------------------------------------------------------
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

        final wasBest =
            _uciMatchesPlayed(
          _bestUci[i],
          p,
        );

        var quality = classifyMove(
          cpBeforeWhite: cpBefore,
          cpAfterWhite: cpAfter,
          color: p.color,
          wasBestMove: wasBest,
        );

        if (quality == MoveQuality.best) {
          final sign =
              p.color == 'w' ? 1 : -1;

          final cpBeforeMover =
              cpBefore * sign;

          final upgraded =
              _tryUpgradeToBrilliant(
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

      if (!mounted || token != _requestToken) return;

      setState(() {
        _qualities = qualities;
        _analyzing = false;
        _analysisStage = 'اكتمل التحليل';
        _progress = 1.0;
        _currentIndex = 0;
      });

      // يبدأ المستخدم من الوضعية الابتدائية، مثل وضع المراجعة
      // في تطبيقات تحليل المباريات الاحترافية.
      _boardState.loadFen(_fens.first);
    } catch (e) {
      if (!mounted || token != _requestToken) return;

      setState(() {
        _analyzing = false;
        _analysisStage = 'فشل التحليل';
      });
    }
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

  /// يحوّل قائمة نقلات PV (UCI) بدءًا من FEN معيّن إلى نص SAN
  /// مقروء، لعرضها كخط رئيسي مقترح تحت الرقعة.
  String _pvToSan(String fen, List<String> pvUci) {
    if (pvUci.isEmpty) return '';

    try {
      final game = ch.Chess();
      game.load(fen);

      final sanParts = <String>[];

      for (final uci in pvUci.take(6)) {
        if (uci.length < 4) break;

        final from = uci.substring(0, 2);
        final to = uci.substring(2, 4);
        final promo =
            uci.length > 4 ? uci.substring(4) : null;

        List<dynamic> legal = [];

        try {
          legal = game.moves(
            <String, dynamic>{'verbose': true},
          );
        } catch (_) {
          break;
        }

        dynamic matched;

        for (final m in legal) {
          String? mFrom;
          String? mTo;

          try {
            mFrom = m is Map
                ? m['from']?.toString()
                : (m as dynamic).fromAlgebraic
                    as String;
            mTo = m is Map
                ? m['to']?.toString()
                : (m as dynamic).toAlgebraic as String;
          } catch (_) {}

          if (mFrom == from && mTo == to) {
            matched = m;
            break;
          }
        }

        if (matched == null) break;

        final args = <String, dynamic>{
          'from': from,
          'to': to,
        };

        if (promo != null && promo.isNotEmpty) {
          args['promotion'] = promo;
        }

        String san = '';

        try {
          san = matched is Map
              ? (matched['san'] ?? '').toString()
              : '';
        } catch (_) {}

        final ok = game.move(args);

        if (ok == false) break;

        sanParts.add(san.isEmpty ? '$from$to' : san);
      }

      return sanParts.join(' ');
    } catch (_) {
      return '';
    }
  }

  /// لاحقة تقليدية (?, ??, ?!, !!) تُضاف لنص SAN، بنفس أسلوب
  /// الأمثلة المرفقة في الطلب.
  String _sanSuffix(MoveQuality q) {
    switch (q) {
      case MoveQuality.brilliant:
        return '!!';
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
  int? get _bestMoveIndex {
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
            Tab(text: 'تقرير المباراة'),
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
                  '$_analysisStage... '
                  '${(_progress * 100).round()}%'
                  ' ($_analysisDone/'
                  '$_analysisTotal) • '
                  '${_engine.recommendedWorkerCount} أنوية',
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
                  _buildReportTab(),
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
      padding: const EdgeInsets.fromLTRB(6, 10, 6, 12),
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
              const SizedBox(width: 5),
              Expanded(
                child: AspectRatio(
                  aspectRatio: 1,
                  // سحب يمين/يسار للتنقل بين النقلات، دون
                  // التعارض مع تحريك القطع (الرقعة هنا للعرض
                  // فقط عبر interactive: false).
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragEnd: (details) {
                      final v = details
                          .primaryVelocity;

                      if (v == null) return;

                      // سحب لليسار (سرعة سالبة) = النقلة
                      // التالية، كتقليب صفحة إلى الأمام.
                      if (v < -150) {
                        _goTo(_currentIndex + 1);
                      } else if (v > 150) {
                        _goTo(_currentIndex - 1);
                      }
                    },
                    child: BoardWidget(
                      state: _boardState,
                      boardTheme: boardThemes[0],
                      pieceTheme: pieceThemes[0],
                      onTap: (_) {},
                      arrows: _arrowsForCurrent(),
                      interactive: false,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildNavControls(),
          if (_fens.length > 1)
            Slider(
              value: _currentIndex.toDouble(),
              min: 0,
              max: (_fens.length - 1).toDouble(),
              divisions: _fens.length - 1,
              label: '$_currentIndex',
              onChanged: (v) => _goTo(v.round()),
            ),
          const SizedBox(height: 4),
          if (!_analyzing && _plies.isNotEmpty)
            _buildCurrentMoveInfo(),
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

  Widget _buildCurrentMoveInfo() {
    if (_currentIndex == 0) {
      final pv = _pvUci.isNotEmpty
          ? _pvToSan(_fens[0], _pvUci[0])
          : '';

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
                  color: Colors.grey.shade700,
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

    final bestSan = bestUci.length >= 4
        ? _pvToSan(_fens[k], [bestUci])
        : '';

    final pv = k < _pvUci.length
        ? _pvToSan(_fens[k], _pvUci[k])
        : '';

    final isBestOrBrilliant =
        q == MoveQuality.best ||
        q == MoveQuality.brilliant;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: info.color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: info.color.withOpacity(0.3),
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
                  color: Colors.grey.shade700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
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
                color: Colors.grey.shade700,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNavControls() {
    final atStart = _currentIndex <= 0;
    final atEnd = _currentIndex >= _fens.length - 1;

    final scheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _navButton(
          icon: Icons.skip_previous_rounded,
          tooltip: 'البداية',
          enabled: !atStart,
          onPressed: () => _goTo(0),
          scheme: scheme,
        ),
        const SizedBox(width: 6),
        _navButton(
          icon: Icons.navigate_before_rounded,
          tooltip: 'السابقة',
          enabled: !atStart,
          onPressed: () => _goTo(_currentIndex - 1),
          scheme: scheme,
          primary: true,
        ),
        Container(
          margin: const EdgeInsets.symmetric(
            horizontal: 10,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: scheme.primary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$_currentIndex / '
            '${_fens.isEmpty ? 0 : _fens.length - 1}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
        ),
        _navButton(
          icon: Icons.navigate_next_rounded,
          tooltip: 'التالية',
          enabled: !atEnd,
          onPressed: () => _goTo(_currentIndex + 1),
          scheme: scheme,
          primary: true,
        ),
        const SizedBox(width: 6),
        _navButton(
          icon: Icons.skip_next_rounded,
          tooltip: 'النهاية',
          enabled: !atEnd,
          onPressed: () => _goTo(_fens.length - 1),
          scheme: scheme,
        ),
      ],
    );
  }

  /// زر تنقل دائري له خلفية واضحة دائمًا (حتى عند التعطيل)،
  /// بدل IconButton العادي الذي يصبح شبه شفاف عند التعطيل
  /// ويعطي انطباعًا بأن الزر "اختفى".
  Widget _navButton({
    required IconData icon,
    required String tooltip,
    required bool enabled,
    required VoidCallback onPressed,
    required ColorScheme scheme,
    bool primary = false,
  }) {
    final size = primary ? 48.0 : 40.0;
    final iconSize = primary ? 28.0 : 22.0;

    final bgColor = !enabled
        ? scheme.onSurface.withOpacity(0.06)
        : primary
            ? scheme.primary
            : scheme.primary.withOpacity(0.12);

    final iconColor = !enabled
        ? scheme.onSurface.withOpacity(0.28)
        : primary
            ? scheme.onPrimary
            : scheme.primary;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: bgColor,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onPressed : null,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(
              icon,
              size: iconSize,
              color: iconColor,
            ),
          ),
        ),
      ),
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
      double accSum = 0;

      for (var i = 0; i < _plies.length; i++) {
        if (_phaseOf(i) != phase) continue;

        moveCount++;
        accSum += _accuracyAt(i);

        final q = _qualities[i];

        if (q == MoveQuality.mistake ||
            q == MoveQuality.blunder ||
            q == MoveQuality.miss) {
          errorCount++;
        }
      }

      result[phase] = _PhaseStat(
        moveCount: moveCount,
        accuracy:
            moveCount > 0 ? accSum / moveCount : 0,
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
    final countsBySide = _qualityCountsBySide;
    final bestIdx = _bestMoveIndex;
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
            color: Colors.grey.withOpacity(0.06),
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
                  .withOpacity(0.06),
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
                countsBySide['w']!,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _playerStatsCard(
                _blackName,
                acc['b'] ?? 0,
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
          currentIndex: _currentIndex,
          onSelect: (i) => _jumpAndShowBoard(i),
        ),
        const SizedBox(height: 16),

        // --------------------------------------------------
        // أفضل وأسوأ نقلة
        // --------------------------------------------------
        Row(
          children: [
            Expanded(
              child: _bestWorstCard(
                title: 'أفضل نقلة',
                icon: Icons.auto_awesome_rounded,
                color: const Color(0xFF1BADA6),
                plyIndex: bestIdx,
                emptyText:
                    'لا توجد نقلة رائعة بارزة في'
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
        color: Colors.grey.withOpacity(0.06),
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
            'الدقة',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey,
            ),
          ),
          const Divider(height: 14),
          row(MoveQuality.excellent),
          row(MoveQuality.good),
          row(MoveQuality.inaccuracy),
          row(MoveQuality.mistake),
          row(MoveQuality.blunder),
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
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withOpacity(0.25),
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
                color: Colors.grey.shade700,
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
                color: Colors.grey.shade700,
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

  Widget _phaseDetailCard(String label, String phaseKey) {
    final stat = _phaseStatsFull[phaseKey]!;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.06),
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
                color: Colors.grey.shade700,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              'دقة ${stat.accuracy.toStringAsFixed(0)}%',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              'أخطاء: ${stat.errorCount}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: stat.errorCount > 0
                    ? const Color(0xFFD9483D)
                    : Colors.grey.shade700,
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
              info.color.withOpacity(0.15),
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
              '${ply.san}${_sanSuffix(m.quality)}',
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
      width: 22,
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
  final int currentIndex;
  final void Function(int index) onSelect;

  const _EvalGraph({
    required this.evalPawns,
    required this.qualities,
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
  final int currentIndex;

  const _EvalGraphPainter({
    required this.evalPawns,
    required this.qualities,
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
      ..color = Colors.grey.withOpacity(0.08);
    final blackBg = Paint()
      ..color = Colors.grey.withOpacity(0.18);

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, mid),
      whiteBg,
    );
    canvas.drawRect(
      Rect.fromLTWH(0, mid, size.width, mid),
      blackBg,
    );

    final zeroPaint = Paint()
      ..color = Colors.grey.withOpacity(0.5)
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

    // مؤشر الموضع الحالي.
    if (currentIndex >= 0 && currentIndex < n) {
      final x = _xAt(currentIndex, n, size.width);

      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = Colors.red.withOpacity(0.4)
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
        oldDelegate.qualities != qualities;
  }
}
