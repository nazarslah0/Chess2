import 'dart:async';

import 'package:flutter/material.dart';

import 'models.dart';
import 'engine_service.dart';
import 'board_widget.dart';
import 'chesscom_service.dart';
import 'pgn_utils.dart';
import 'game_review_models.dart';

class GameReviewScreen extends StatefulWidget {
  const GameReviewScreen({super.key});

  @override
  State<GameReviewScreen> createState() =>
      _GameReviewScreenState();
}

class _GameReviewScreenState
    extends State<GameReviewScreen> {
  final TextEditingController _usernameCtrl =
      TextEditingController();

  final ChessComService _service = ChessComService();

  final EngineService _engine = EngineService();

  final GameState _boardState = GameState();

  bool _loadingGames = false;
  String? _error;

  List<ChessComGame> _games = <ChessComGame>[];
  String _username = '';

  ChessComGame? _selectedGame;

  List<PgnPly>? _plies;
  List<String> _fens = <String>[];
  List<double> _evalPawns = <double>[];
  List<String> _evalLabels = <String>[];
  List<String> _bestUci = <String>[];
  List<MoveQuality> _qualities = <MoveQuality>[];

  int _currentIndex = 0;

  bool _analyzing = false;
  double _progress = 0;

  double _depth = 14;

  int _requestToken = 0;

  @override
  void initState() {
    super.initState();
    _engine.init();
  }

  @override
  void dispose() {
    _engine.dispose();
    _usernameCtrl.dispose();
    _boardState.dispose();
    super.dispose();
  }

  // ============================================================
  // جلب المباريات
  // ============================================================

  Future<void> _search() async {
    final u = _usernameCtrl.text.trim();

    if (u.isEmpty) {
      return;
    }

    setState(() {
      _loadingGames = true;
      _error = null;
      _games = <ChessComGame>[];
      _selectedGame = null;
      _plies = null;
    });

    try {
      await _service.verifyUsername(u);

      final games = await _service.fetchRecentGames(
        u,
        limit: 20,
      );

      if (!mounted) return;

      setState(() {
        _username = u;
        _games = games;
        _loadingGames = false;

        if (games.isEmpty) {
          _error =
              'لا توجد مباريات ظاهرة لهذا الحساب.';
        }
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e is ChessComException
            ? e.message
            : 'حدث خطأ غير متوقع أثناء الاتصال بـ Chess.com.';

        _loadingGames = false;
      });
    }
  }

  // ============================================================
  // اختيار مباراة وتحليلها بالكامل
  // ============================================================

  Future<void> _selectGame(ChessComGame g) async {
    final plies = parsePgnMoves(g.pgn);

    if (plies == null || plies.isEmpty) {
      setState(() {
        _error =
            'تعذر قراءة نقلات هذه المباراة (PGN غير مدعوم).';
      });
      return;
    }

    final myToken = ++_requestToken;

    final fens = <String>[
      plies.first.fenBefore,
      for (final p in plies) p.fenAfter,
    ];

    setState(() {
      _error = null;
      _selectedGame = g;
      _plies = plies;
      _fens = fens;
      _evalPawns =
          List<double>.filled(fens.length, 0.0);
      _evalLabels =
          List<String>.filled(fens.length, '0.00');
      _bestUci =
          List<String>.filled(fens.length, '');
      _qualities = <MoveQuality>[];
      _currentIndex = 0;
      _progress = 0;
      _analyzing = true;
    });

    _boardState.loadFen(fens.first);

    await _runAnalysis(myToken);
  }

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

    final fens = _fens;

    for (var i = 0; i < fens.length; i++) {
      if (!mounted || token != _requestToken) {
        return;
      }

      final r = await _evaluatePosition(fens[i]);

      if (!mounted || token != _requestToken) {
        return;
      }

      _evalPawns[i] = r.pawns;
      _evalLabels[i] = r.label;
      _bestUci[i] = r.bestUci;

      setState(() {
        _progress = (i + 1) / fens.length;
      });
    }

    final plies = _plies!;

    final qualities = <MoveQuality>[];

    for (var i = 0; i < plies.length; i++) {
      final p = plies[i];

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

      qualities.add(
        classifyMove(
          cpBeforeWhite: cpBefore,
          cpAfterWhite: cpAfter,
          color: p.color,
          wasBestMove: wasBest,
        ),
      );
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
  // التنقل بين النقلات
  // ============================================================

  void _goTo(int index) {
    if (_fens.isEmpty) {
      return;
    }

    final clamped =
        index.clamp(0, _fens.length - 1);

    setState(() {
      _currentIndex = clamped;
    });

    _boardState.loadFen(_fens[clamped]);
  }

  BoardArrow _decodeArrow(String uci, Color color) {
    return BoardArrow(
      from: uci.substring(0, 2),
      to: uci.substring(2, 4),
      color: color,
    );
  }

  List<BoardArrow> _arrowsForCurrent() {
    if (_plies == null || _fens.isEmpty) {
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
      final ply = _plies![k];
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
  // Build
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selectedGame == null
              ? 'تحليل مباريات Chess.com'
              : '${_selectedGame!.whiteUsername}'
                  ' ضد '
                  '${_selectedGame!.blackUsername}',
        ),
        leading: _selectedGame != null
            ? IconButton(
                icon: const Icon(
                  Icons.arrow_back,
                ),
                onPressed: () {
                  setState(() {
                    _requestToken++;
                    _selectedGame = null;
                    _plies = null;
                    _analyzing = false;
                  });
                },
              )
            : null,
        actions: _selectedGame == null
            ? null
            : [
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
      ),
      body: SafeArea(
        child: _selectedGame == null
            ? _buildSearchBody()
            : _buildReviewBody(),
      ),
    );
  }

  // ------------------------------------------------------------
  // واجهة البحث وقائمة المباريات
  // ------------------------------------------------------------

  Widget _buildSearchBody() {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _usernameCtrl,
                  textInputAction:
                      TextInputAction.search,
                  decoration:
                      const InputDecoration(
                    labelText:
                        'معرف Chess.com (Username)',
                    hintText: 'مثال: hikaru',
                    border: OutlineInputBorder(),
                    prefixIcon:
                        Icon(Icons.person_outline),
                  ),
                  onSubmitted: (_) => _search(),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed:
                      _loadingGames ? null : _search,
                  child: _loadingGames
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child:
                              CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('بحث'),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                child: Text(
                  'عمق التحليل: ${_depth.round()}',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium,
                ),
              ),
              Expanded(
                flex: 3,
                child: Slider(
                  value: _depth,
                  min: 10,
                  max: 20,
                  divisions: 10,
                  label: _depth.round().toString(),
                  onChanged: (v) {
                    setState(() {
                      _depth = v;
                    });
                  },
                ),
              ),
            ],
          ),

          if (_error != null)
            Padding(
              padding:
                  const EdgeInsets.symmetric(
                vertical: 8,
              ),
              child: Text(
                _error!,
                style: const TextStyle(
                  color: Colors.red,
                ),
              ),
            ),

          const SizedBox(height: 8),

          Expanded(
            child: _games.isEmpty
                ? Center(
                    child: Text(
                      _loadingGames
                          ? 'جاري التحميل...'
                          : 'أدخل معرف Chess.com لعرض'
                              ' آخر مبارياته وتحليلها'
                              ' بأسهم وتصنيف للنقلات.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: _games.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final g = _games[index];
                      return _buildGameTile(g);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildGameTile(ChessComGame g) {
    final outcome = g.outcomeFor(_username);
    final opponent = g.opponentOf(_username);

    Color color;
    String label;
    IconData icon;

    switch (outcome) {
      case 'win':
        color = const Color(0xFF2AA876);
        label = 'فوز';
        icon = Icons.emoji_events_rounded;
        break;
      case 'draw':
        color = Colors.grey;
        label = 'تعادل';
        icon = Icons.horizontal_rule_rounded;
        break;
      default:
        color = const Color(0xFFD9483D);
        label = 'خسارة';
        icon = Icons.close_rounded;
    }

    final date = g.endTime;
    final dateStr = date == null
        ? ''
        : '${date.year}/${date.month.toString().padLeft(2, '0')}'
            '/${date.day.toString().padLeft(2, '0')}';

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withOpacity(0.15),
        child: Icon(icon, color: color),
      ),
      title: Text('ضد $opponent'),
      subtitle: Text(
        '${g.timeClass} • $dateStr',
      ),
      trailing: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
      onTap: () => _selectGame(g),
    );
  }

  // ------------------------------------------------------------
  // واجهة المراجعة
  // ------------------------------------------------------------

  Widget _buildReviewBody() {
    final hasEval = _evalPawns.isNotEmpty;

    return Column(
      children: [
        if (_analyzing)
          LinearProgressIndicator(value: _progress),

        if (_analyzing)
          Padding(
            padding: const EdgeInsets.symmetric(
              vertical: 6,
            ),
            child: Text(
              'جارٍ تحليل المباراة... '
              '${(_progress * 100).round()}%',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall,
            ),
          ),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    _EvalBar(
                      pawns: hasEval
                          ? _evalPawns[
                              _currentIndex]
                          : 0,
                      label: hasEval
                          ? _evalLabels[
                              _currentIndex]
                          : '0.00',
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: BoardWidget(
                          state: _boardState,
                          boardTheme:
                              boardThemes[0],
                          pieceTheme:
                              pieceThemes[0],
                          onTap: (_) {},
                          arrows:
                              _arrowsForCurrent(),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                _buildNavControls(),

                const SizedBox(height: 12),

                if (!_analyzing &&
                    _qualities.isNotEmpty)
                  _buildAccuracySummary(),

                const SizedBox(height: 12),

                if (_plies != null)
                  _buildMoveList(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNavControls() {
    final atStart = _currentIndex <= 0;
    final atEnd =
        _currentIndex >= _fens.length - 1;

    return Row(
      mainAxisAlignment:
          MainAxisAlignment.center,
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
    double whiteSum = 0;
    double blackSum = 0;
    int whiteN = 0;
    int blackN = 0;

    for (var i = 0; i < _plies!.length; i++) {
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

      final color = _plies![i].color;

      final wpBeforeMover =
          color == 'w' ? wpBefore : 100 - wpBefore;
      final wpAfterMover =
          color == 'w' ? wpAfter : 100 - wpAfter;

      final acc = moveAccuracy(
        winPercentBeforeMover: wpBeforeMover,
        winPercentAfterMover: wpAfterMover,
      );

      if (color == 'w') {
        whiteSum += acc;
        whiteN++;
      } else {
        blackSum += acc;
        blackN++;
      }
    }

    final whiteAcc =
        whiteN > 0 ? whiteSum / whiteN : 0.0;
    final blackAcc =
        blackN > 0 ? blackSum / blackN : 0.0;

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
          _accuracyChip('الأبيض', whiteAcc),
          _accuracyChip('الأسود', blackAcc),
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

  Widget _buildMoveList() {
    final plies = _plies!;
    final rows = <Widget>[];

    for (var i = 0; i < plies.length; i += 2) {
      final whiteP = plies[i];
      final whiteQ =
          _qualities.length > i ? _qualities[i] : null;

      final hasBlack = i + 1 < plies.length;
      final blackP = hasBlack ? plies[i + 1] : null;
      final blackQ = hasBlack &&
              _qualities.length > i + 1
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
                () => _goTo(i + 1),
                isCurrent:
                    _currentIndex == i + 1,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: blackP == null
                  ? const SizedBox()
                  : _moveChip(
                      blackP.san,
                      blackQ,
                      () => _goTo(i + 2),
                      isCurrent:
                          _currentIndex == i + 2,
                    ),
            ),
          ],
        ),
      );
    }

    return Column(children: rows);
  }

  Widget _moveChip(
    String san,
    MoveQuality? q,
    VoidCallback onTap, {
    bool isCurrent = false,
  }) {
    final info = q != null
        ? moveQualityInfo[q]
        : null;

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
                  alignment:
                      Alignment.bottomCenter,
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
            style: const TextStyle(
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

// ================================================================
// نتيجة تقييم وضعية واحدة
// ================================================================

class _Eval {
  final double pawns;
  final String label;
  final String bestUci;

  const _Eval(this.pawns, this.label, this.bestUci);
}
