import 'package:flutter/material.dart';

import 'lichess_service.dart';
import 'game_analysis_screen.dart';

/// شاشة البحث عن مباريات Lichess — نفس بنية شاشة Chess.com،
/// وتفتح نفس GameAnalysisScreen الموحّدة عند اختيار مباراة.
class LichessScreen extends StatefulWidget {
  const LichessScreen({super.key});

  @override
  State<LichessScreen> createState() =>
      _LichessScreenState();
}

enum _GameLimit { last10, last25, last50 }

class _LichessScreenState extends State<LichessScreen> {
  final TextEditingController _usernameCtrl =
      TextEditingController();

  final LichessService _service = LichessService();

  bool _loadingGames = false;
  String? _error;

  List<LichessGame> _games = <LichessGame>[];
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

  Future<void> _search() async {
    final u = _usernameCtrl.text.trim();

    if (u.isEmpty) {
      return;
    }

    setState(() {
      _loadingGames = true;
      _error = null;
      _games = <LichessGame>[];
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
        _error = e is LichessException
            ? e.message
            : 'حدث خطأ غير متوقع أثناء الاتصال بـ Lichess.';

        _loadingGames = false;
      });
    }
  }

  void _openGame(LichessGame g) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GameAnalysisScreen(
          pgn: g.pgn,
          whiteLabel: g.whiteUsername,
          blackLabel: g.blackUsername,
          resultLabel: g.result,
          sourceLabel: 'Lichess',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تحليل مباريات Lichess'),
      ),
      body: SafeArea(
        child: Padding(
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
                            'معرف Lichess (Username)',
                        hintText: 'مثال: DrNykterstein',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(
                          Icons.person_outline,
                        ),
                      ),
                      onSubmitted: (_) => _search(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _loadingGames
                          ? null
                          : _search,
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
              SegmentedButton<_GameLimit>(
                segments: const [
                  ButtonSegment(
                    value: _GameLimit.last10,
                    label: Text('آخر 10'),
                  ),
                  ButtonSegment(
                    value: _GameLimit.last25,
                    label: Text('آخر 25'),
                  ),
                  ButtonSegment(
                    value: _GameLimit.last50,
                    label: Text('آخر 50'),
                  ),
                ],
                selected: {_limit},
                onSelectionChanged: (s) {
                  setState(() {
                    _limit = s.first;
                  });
                },
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
                              : 'أدخل معرف Lichess'
                                  ' لعرض آخر مبارياته'
                                  ' وتحليلها بأسهم'
                                  ' وتصنيف للنقلات.',
                          textAlign:
                              TextAlign.center,
                          style: TextStyle(
                            color:
                                Colors.grey.shade600,
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _games.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1),
                        itemBuilder:
                            (context, index) {
                          final g = _games[index];
                          return _buildGameTile(g);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGameTile(LichessGame g) {
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
        backgroundColor: color.withValues(alpha: 0.15),
        child: Icon(icon, color: color),
      ),
      title: Text('ضد $opponent'),
      subtitle: Text(
        '${g.timeClass.isEmpty ? '' : '${g.timeClass} • '}$dateStr',
      ),
      trailing: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
      onTap: () => _openGame(g),
    );
  }
}
