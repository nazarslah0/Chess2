import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'board_input.dart';
import 'board_widget.dart';
import 'game_analysis_screen.dart';
import 'maia_service.dart';
import 'models.dart';
import 'sound_service.dart';
import 'uci_utils.dart';

/// العب ضد Maia: خصم يلعب مثل البشر بتصنيف 1100 أو 1500 أو 1900.
/// تُختار نقلات Maia عشوائيًا حسب احتمالاتها (وليس أقوى نقلة دائمًا)،
/// فيرتكب أخطاء بشرية مماثلة لذلك المستوى.
class MaiaPlayScreen extends StatefulWidget {
  const MaiaPlayScreen({super.key});

  @override
  State<MaiaPlayScreen> createState() => _MaiaPlayScreenState();
}

class _MaiaPlayScreenState extends State<MaiaPlayScreen> {
  final GameState _state = GameState();
  late final BoardInput _input = BoardInput(_state);
  final SoundService _sound = SoundService();
  final math.Random _rng = math.Random();

  MaiaSession? _session;

  List<int> _available = const <int>[];
  bool _loadingAvailable = true;

  int _bucket = AppSettings.instance.maiaBucket;
  String _colorChoice = 'w'; // w / b / r

  bool _started = false;
  bool _starting = false;
  bool _thinking = false;
  String _userColor = 'w';
  String? _result; // 1-0 / 0-1 / 1/2-1/2
  String? _resultText;
  String? _notice;

  final List<String> _uciHistory = <String>[];

  @override
  void initState() {
    super.initState();

    _state.onSound = (kind) => _sound.playKind(kind);
    _state.addListener(_onState);

    MaiaService.availableBuckets().then((v) {
      if (!mounted) return;

      setState(() {
        _available = v;
        _loadingAvailable = false;

        final near = MaiaService.nearestAvailable(_bucket, v);

        if (near != null) _bucket = near;
      });
    });
  }

  void _onState() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _state.removeListener(_onState);
    _session?.close();
    _sound.dispose();
    _state.dispose();
    super.dispose();
  }

  String get _turn {
    final parts = _state.currentFen.split(' ');

    return parts.length > 1 ? parts[1] : 'w';
  }

  // ------------------------------------------------------------
  // بدء اللعبة
  // ------------------------------------------------------------

  Future<void> _start() async {
    setState(() {
      _starting = true;
      _notice = null;
    });

    await _session?.close();
    _session = await MaiaSession.open(_bucket);

    if (!mounted) return;

    if (_session == null) {
      setState(() {
        _starting = false;
        _notice = 'تعذّر تشغيل Maia على هذا الجهاز.';
      });

      return;
    }

    _userColor = _colorChoice == 'r'
        ? (_rng.nextBool() ? 'w' : 'b')
        : _colorChoice;

    _state.startPosition();
    _state.flipped = _userColor == 'b';
    _input.clear();
    _uciHistory.clear();

    setState(() {
      _started = true;
      _starting = false;
      _result = null;
      _resultText = null;
    });

    if (_userColor == 'b') {
      await _maiaMove();
    }
  }

  // ------------------------------------------------------------
  // نقلات اللاعب وMaia
  // ------------------------------------------------------------

  Future<String?> _askPromotion() {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('اختر قطعة الترقية'),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in const <String, String>{
              'q': 'وزير',
              'r': 'رخ',
              'b': 'فيل',
              'n': 'حصان',
            }.entries)
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, e.key),
                child: Text(e.value),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _onTap(String square) async {
    if (!_started || _thinking || _result != null) return;

    final moved = await _input.tap(
      square,
      _askPromotion,
      side: _userColor,
    );

    if (!mounted) return;

    setState(() {});

    if (!moved) return;

    final uci = _input.lastUci;

    if (uci != null) _uciHistory.add(uci);

    if (_checkEnd()) return;

    await _maiaMove();
  }

  /// يختار نقلة من سياسة Maia عشوائيًا بحسب احتمالاتها، ويتجاهل
  /// النقلات شبه المستحيلة (< 1%).
  String? _sample(Map<String, double> policy) {
    final entries = policy.entries
        .where((e) => parseUci(e.key) != null && e.value >= 0.01)
        .toList();

    if (entries.isEmpty) {
      final ranked = MaiaService.ranked(policy);

      return ranked.isEmpty ? null : ranked.first.key;
    }

    final total = entries.fold<double>(0, (a, e) => a + e.value);

    var r = _rng.nextDouble() * total;

    for (final e in entries) {
      r -= e.value;

      if (r <= 0) return e.key;
    }

    return entries.last.key;
  }

  String? _randomLegalUci() {
    final fen = _state.currentFen;
    final board = GameState.parseBoard(fen.split(' ').first);
    final turn = _turn;

    final all = <String>[];

    board.forEach((sq, piece) {
      if (!piece.startsWith(turn)) return;

      for (final t in _state.legalTargets(sq)) {
        final promo = piece.substring(1) == 'P' &&
                (t.endsWith('8') || t.endsWith('1'))
            ? 'q'
            : '';

        all.add('$sq$t$promo');
      }
    });

    return all.isEmpty ? null : all[_rng.nextInt(all.length)];
  }

  Future<void> _maiaMove() async {
    if (!mounted || _result != null) return;

    setState(() => _thinking = true);

    Map<String, double>? policy;

    try {
      policy = await _session?.policy(
        startFen: GameState.startFen,
        movesUci: List<String>.of(_uciHistory),
      );
    } catch (_) {
      policy = null;
    }

    if (!mounted) return;

    var uci = policy == null ? null : _sample(policy);

    var ok = false;

    if (uci != null) {
      ok = _applyUci(uci);
    }

    if (!ok) {
      // احتياطي: نقلة قانونية عشوائية إن فشلت Maia.
      uci = _randomLegalUci();

      if (uci != null) ok = _applyUci(uci);

      if (mounted) {
        setState(() {
          _notice = 'تعذّر الحصول على نقلة من Maia؛ لُعبت نقلة عشوائية.';
        });
      }
    }

    if (!mounted) return;

    setState(() => _thinking = false);

    _checkEnd();
  }

  bool _applyUci(String uci) {
    final move = parseUci(uci);

    if (move == null) return false;

    final ok = _state.tryMove(
      move.from,
      move.to,
      promotion: move.promotion,
    );

    if (ok) _uciHistory.add(move.uci);

    return ok;
  }

  // ------------------------------------------------------------
  // نهاية اللعبة
  // ------------------------------------------------------------

  bool _checkEnd() {
    final c = _state.chess;

    String? res;
    String? text;

    try {
      if (c.in_checkmate) {
        // الدور على من تعرّض للمات.
        final whiteWins = _turn == 'b';

        res = whiteWins ? '1-0' : '0-1';
        text = 'كش مات — فاز ${whiteWins ? 'الأبيض' : 'الأسود'}';
      } else if (c.in_stalemate) {
        res = '1/2-1/2';
        text = 'تعادل (ستاليمايت)';
      } else if (c.in_draw) {
        res = '1/2-1/2';
        text = 'تعادل';
      }
    } catch (_) {}

    if (res == null) return false;

    setState(() {
      _result = res;
      _resultText = text;
    });

    return true;
  }

  void _resign() {
    final whiteWins = _userColor == 'b';

    setState(() {
      _result = whiteWins ? '1-0' : '0-1';
      _resultText = 'استسلمت — فازت Maia';
    });
  }

  // ------------------------------------------------------------
  // تحليل المباراة
  // ------------------------------------------------------------

  String _buildPgn() {
    final user = 'أنت';
    final maia = 'Maia $_bucket';

    final white = _userColor == 'w' ? user : maia;
    final black = _userColor == 'w' ? maia : user;

    final b = StringBuffer()
      ..writeln('[Event "Chess2 vs Maia"]')
      ..writeln('[Site "Chess2"]')
      ..writeln('[White "$white"]')
      ..writeln('[Black "$black"]')
      ..writeln('[Result "${_result ?? '*'}"]');

    if (_userColor == 'w') {
      b.writeln('[BlackElo "$_bucket"]');
    } else {
      b.writeln('[WhiteElo "$_bucket"]');
    }

    b.writeln();

    final moves = StringBuffer();

    for (var i = 0; i < _state.history.length; i++) {
      final m = _state.history[i];

      if (m.color == 'w') {
        moves.write('${(i ~/ 2) + 1}. ${m.san} ');
      } else {
        moves.write(i == 0 ? '1... ${m.san} ' : '${m.san} ');
      }
    }

    b.write('${moves.toString().trim()} ${_result ?? '*'}');

    return b.toString();
  }

  void _openAnalysis() {
    if (_state.history.isEmpty) return;

    final white = _userColor == 'w' ? 'أنت' : 'Maia $_bucket';
    final black = _userColor == 'w' ? 'Maia $_bucket' : 'أنت';

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GameAnalysisScreen(
          pgn: _buildPgn(),
          whiteLabel: white,
          blackLabel: black,
          sourceLabel: 'ضد Maia',
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // الواجهة
  // ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('العب ضد Maia')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              if (!_started) _buildSetup() else _buildGame(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSetup() {
    if (_loadingAvailable) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: CircularProgressIndicator(),
      );
    }

    if (_available.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'لم يتم العثور على أوزان Maia في التطبيق.\n'
            'ضع ملفات maia-1100.pb.gz و maia-1500.pb.gz و '
            'maia-1900.pb.gz في assets/maia/ ثم أعد بناء التطبيق '
            '(التفاصيل في assets/maia/README.txt).',
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'مستوى Maia',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final b in _available)
                  ChoiceChip(
                    label: Text('$b'),
                    selected: _bucket == b,
                    onSelected: (_) => setState(() => _bucket = b),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'ألعب بالقطع',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('الأبيض'),
                  selected: _colorChoice == 'w',
                  onSelected: (_) => setState(() => _colorChoice = 'w'),
                ),
                ChoiceChip(
                  label: const Text('الأسود'),
                  selected: _colorChoice == 'b',
                  onSelected: (_) => setState(() => _colorChoice = 'b'),
                ),
                ChoiceChip(
                  label: const Text('عشوائي'),
                  selected: _colorChoice == 'r',
                  onSelected: (_) => setState(() => _colorChoice = 'r'),
                ),
              ],
            ),
            if (_notice != null) ...[
              const SizedBox(height: 12),
              Text(_notice!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _starting ? null : _start,
                icon: _starting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow_rounded),
                label: Text(_starting ? 'جارٍ تحميل Maia...' : 'ابدأ'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGame() {
    final myTurn = _result == null && !_thinking && _turn == _userColor;

    final status = _result != null
        ? (_resultText ?? 'انتهت المباراة')
        : (_thinking
            ? 'Maia $_bucket تفكّر...'
            : (myTurn ? 'دورك' : 'دور Maia'));

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                status,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            Text(
              'Maia $_bucket',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListenableBuilder(
            listenable: AppSettings.instance,
            builder: (context, _) => BoardWidget(
              state: _state,
              boardTheme: AppSettings.instance.boardTheme,
              pieceTheme: AppSettings.instance.pieceTheme,
              onTap: _onTap,
              targets: _input.targets,
            ),
          ),
        ),
        if (_notice != null) ...[
          const SizedBox(height: 8),
          Text(
            _notice!,
            style: const TextStyle(color: Colors.orange, fontSize: 12),
          ),
        ],
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            if (_result == null)
              OutlinedButton(
                onPressed: _thinking ? null : _resign,
                child: const Text('استسلام'),
              ),
            OutlinedButton(
              onPressed: _state.flipBoard,
              child: const Text('قلب الرقعة'),
            ),
            if (_state.history.isNotEmpty)
              FilledButton.icon(
                onPressed: _thinking ? null : _openAnalysis,
                icon: const Icon(Icons.query_stats_rounded),
                label: const Text('تحليل المباراة'),
              ),
            FilledButton.tonal(
              onPressed: _thinking
                  ? null
                  : () => setState(() {
                        _started = false;
                        _result = null;
                        _resultText = null;
                      }),
              child: const Text('مباراة جديدة'),
            ),
          ],
        ),
      ],
    );
  }
}
