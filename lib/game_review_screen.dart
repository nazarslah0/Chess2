import 'package:flutter/material.dart';

import 'chesscom_service.dart';
import 'game_analysis_screen.dart';
import 'app_theme.dart';

/// شاشة البحث عن مباريات Chess.com وعرضها كقائمة — التحليل
/// نفسه يتم بالكامل داخل GameAnalysisScreen (مصدر واحد
/// للتحليل يُستخدم أيضًا من Lichess ومن PGN المُلصَق يدويًا).
class GameReviewScreen extends StatefulWidget {
  const GameReviewScreen({super.key});

  @override
  State<GameReviewScreen> createState() =>
      _GameReviewScreenState();
}

enum _GameLimit { last10, last25, last50 }

class _GameReviewScreenState
    extends State<GameReviewScreen> {
  final TextEditingController _usernameCtrl =
      TextEditingController();

  final ChessComService _service = ChessComService();

  bool _loadingGames = false;
  String? _error;

  List<ChessComGame> _games = <ChessComGame>[];
  String _username = '';

  _GameLimit _limit = _GameLimit.last10;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    super.dispose();
  }

  int get _limitCount {
    switch (_limit) {
      case _GameLimit.last10:
        return 10;
      case _GameLimit.last25:
        return 25;
      case _GameLimit.last50:
        return 50;
    }
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
    });

    try {
      await _service.verifyUsername(u);

      final games = await _service.fetchRecentGames(
        u,
        limit: _limitCount,
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

  void _openGame(ChessComGame g) {
    final opponent = g.opponentOf(_username);

    final isWhite = g.whiteUsername.toLowerCase() ==
        _username.toLowerCase();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GameAnalysisScreen(
          pgn: g.pgn,
          whiteLabel: isWhite ? _username : opponent,
          blackLabel: isWhite ? opponent : _username,
          sourceLabel: 'Chess.com',
        ),
      ),
    );
  }

  // ============================================================
  // Build
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chess.com • Game Review'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Chess2Theme.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Chess2Theme.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.person_search_outlined, color: Chess2Theme.blue),
                        SizedBox(width: 10),
                        Text('ابحث عن لاعب', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _usernameCtrl,
                            textInputAction: TextInputAction.search,
                            onSubmitted: (_) => _search(),
                            decoration: const InputDecoration(
                              labelText: 'Chess.com Username',
                              hintText: 'مثال: hikaru',
                              prefixIcon: Icon(Icons.alternate_email_rounded),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 54,
                          height: 54,
                          child: FilledButton(
                            onPressed: _loadingGames ? null : _search,
                            child: _loadingGames
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.search_rounded),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SegmentedButton<_GameLimit>(
                      segments: const [
                        ButtonSegment(value: _GameLimit.last10, label: Text('10')),
                        ButtonSegment(value: _GameLimit.last25, label: Text('25')),
                        ButtonSegment(value: _GameLimit.last50, label: Text('50')),
                      ],
                      selected: {_limit},
                      onSelectionChanged: (s) => setState(() => _limit = s.first),
                    ),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Chess2Theme.red)),
              ],
              const SizedBox(height: 14),
              if (_username.isNotEmpty)
                Text('آخر مباريات $_username', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Expanded(
                child: _games.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.sports_esports_outlined, size: 52, color: Chess2Theme.muted.withValues(alpha=.65)),
                            const SizedBox(height: 10),
                            Text(_loadingGames ? 'جاري التحميل...' : 'أدخل Username لعرض المباريات', style: const TextStyle(color: Chess2Theme.muted)),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: _games.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) => _buildGameTile(_games[index]),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGameTile(ChessComGame g) {
    final outcome = g.outcomeFor(_username);
    final opponent = g.opponentOf(_username);

    final Color color;
    final String label;
    final IconData icon;
    switch (outcome) {
      case 'win':
        color = Chess2Theme.green;
        label = 'فوز';
        icon = Icons.emoji_events_rounded;
        break;
      case 'draw':
        color = Chess2Theme.orange;
        label = 'تعادل';
        icon = Icons.horizontal_rule_rounded;
        break;
      default:
        color = Chess2Theme.red;
        label = 'خسارة';
        icon = Icons.close_rounded;
    }

    final date = g.endTime;
    final dateStr = date == null ? '' : '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _openGame(g),
      child: Ink(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Chess2Theme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Chess2Theme.border),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: color.withValues(alpha=.12), borderRadius: BorderRadius.circular(13)),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ضد $opponent', style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text('${g.timeClass} • $dateStr', style: const TextStyle(color: Chess2Theme.muted, fontSize: 11)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w900)),
                const SizedBox(height: 3),
                const Text('تحليل', style: TextStyle(color: Chess2Theme.muted, fontSize: 11)),
              ],
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_left_rounded, color: Chess2Theme.muted),
          ],
        ),
      ),
    );
  }
}
