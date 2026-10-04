import 'package:flutter/material.dart';

import 'account_storage.dart';
import 'chesscom_service.dart';
import 'game_analysis_screen.dart';

/// شاشة البحث والتحليل لحسابات Chess.com.
///
/// - تحفظ آخر Username محليًا.
/// - تجلب آخر 50 مباراة تلقائيًا دون اختيار 10/25/50.
/// - زر تبديل الحساب يفتح حسابًا آخر مع إبقاء الحساب الجديد محفوظًا.
class GameReviewScreen extends StatefulWidget {
  const GameReviewScreen({super.key});

  @override
  State<GameReviewScreen> createState() => _GameReviewScreenState();
}

class _GameReviewScreenState extends State<GameReviewScreen> {
  final TextEditingController _usernameCtrl = TextEditingController();
  final ChessComService _service = ChessComService();

  bool _loadingGames = false;
  String? _error;
  List<ChessComGame> _games = <ChessComGame>[];
  String _username = '';
  String? _savedUsername;

  @override
  void initState() {
    super.initState();
    _restoreAccount();
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    super.dispose();
  }

  Future<void> _restoreAccount() async {
    final saved = await AccountStorage.getChessComUsername();
    if (!mounted || saved == null) return;

    setState(() {
      _savedUsername = saved;
      _usernameCtrl.text = saved;
      _username = saved;
    });

    // بعد حفظ الحساب، يعاد تحميل آخر 50 مباراة تلقائيًا.
    await _search(saved);
  }

  Future<void> _search([String? requestedUsername]) async {
    final u = (requestedUsername ?? _usernameCtrl.text).trim();
    if (u.isEmpty) return;

    FocusScope.of(context).unfocus();

    setState(() {
      _loadingGames = true;
      _error = null;
      _games = <ChessComGame>[];
      _username = u;
    });

    try {
      await _service.verifyUsername(u);
      final games = await _service.fetchRecentGames(u, limit: 50);
      await AccountStorage.saveChessComUsername(u);

      if (!mounted) return;

      setState(() {
        _savedUsername = u;
        _usernameCtrl.text = u;
        _games = games;
        _loadingGames = false;
        if (games.isEmpty) {
          _error = 'لا توجد مباريات ظاهرة لهذا الحساب.';
        }
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e is ChessComException
            ? e.message
            : 'حدث خطأ أثناء الاتصال بـ Chess.com.';
        _loadingGames = false;
      });
    }
  }

  Future<void> _switchAccount() async {
    final controller = TextEditingController(text: _username);

    final username = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تبديل حساب Chess.com'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            labelText: 'اسم المستخدم',
            hintText: 'مثال: hikaru',
            prefixIcon: Icon(Icons.person_search_rounded),
          ),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            icon: const Icon(Icons.swap_horiz_rounded),
            label: const Text('تبديل'),
          ),
        ],
      ),
    );

    controller.dispose();
    if (username == null || username.trim().isEmpty) return;

    _usernameCtrl.text = username.trim();
    await _search(username.trim());
  }

  void _openGame(ChessComGame g) {
    final opponent = g.opponentOf(_username);
    final isWhite = g.whiteUsername.toLowerCase() == _username.toLowerCase();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GameAnalysisScreen(
          pgn: g.pgn,
          whiteLabel: isWhite ? _username : opponent,
          blackLabel: isWhite ? opponent : _username,
          resultLabel: isWhite ? g.whiteResult : g.blackResult,
          sourceLabel: 'Chess.com',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF312E2B);
    const panel = Color(0xFF262522);
    const green = Color(0xFF81B64C);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: panel,
        foregroundColor: Colors.white,
        title: const Text('تحليل مباريات Chess.com'),
        actions: [
          if (_savedUsername != null)
            IconButton(
              tooltip: 'تبديل الحساب',
              onPressed: _loadingGames ? null : _switchAccount,
              icon: const Icon(Icons.swap_horiz_rounded),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildAccountHeader(green),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _usernameCtrl,
                      style: const TextStyle(color: Colors.white),
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        labelText: 'اسم مستخدم Chess.com',
                        labelStyle: const TextStyle(color: Colors.white70),
                        hintText: 'مثال: hikaru',
                        hintStyle: const TextStyle(color: Colors.white38),
                        prefixIcon: const Icon(Icons.person_outline, color: Colors.white70),
                        filled: true,
                        fillColor: panel,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.white12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: green, width: 2),
                        ),
                      ),
                      onSubmitted: (_) => _search(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 56,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _loadingGames ? null : _search,
                      child: _loadingGames
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('بحث'),
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Color(0xFFE57373)),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
              child: Row(
                children: [
                  const Icon(Icons.history_rounded, color: Colors.white70, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'آخر 50 مباراة',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  if (_games.isNotEmpty)
                    Text(
                      '${_games.length} مباراة',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                ],
              ),
            ),
            Expanded(
              child: _games.isEmpty
                  ? Center(
                      child: _loadingGames
                          ? const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(color: Color(0xFF81B64C)),
                                SizedBox(height: 12),
                                Text('جاري تحميل آخر 50 مباراة...', style: TextStyle(color: Colors.white70)),
                              ],
                            )
                          : const Text(
                              'احفظ حسابك ثم سيتم تحميل آخر 50 مباراة تلقائيًا.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white54),
                            ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 20),
                      itemCount: _games.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (context, index) => _buildGameTile(_games[index], index),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountHeader(Color green) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      color: const Color(0xFF262522),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFF3B3937),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.person_rounded, color: green, size: 28),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('الحساب المحفوظ', style: TextStyle(color: Colors.white54, fontSize: 11)),
                Text(
                  _savedUsername ?? 'لم يتم اختيار حساب',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ],
            ),
          ),
          if (_savedUsername != null)
            TextButton.icon(
              onPressed: _loadingGames ? null : _switchAccount,
              icon: const Icon(Icons.swap_horiz_rounded, size: 18),
              label: const Text('تبديل'),
              style: TextButton.styleFrom(foregroundColor: green),
            ),
        ],
      ),
    );
  }

  Widget _buildGameTile(ChessComGame g, int index) {
    final outcome = g.outcomeFor(_username);
    final opponent = g.opponentOf(_username);

    final Color color;
    final String label;
    final IconData icon;

    switch (outcome) {
      case 'win':
        color = const Color(0xFF81B64C);
        label = 'فوز';
        icon = Icons.emoji_events_rounded;
        break;
      case 'draw':
        color = const Color(0xFFB3B3B3);
        label = 'تعادل';
        icon = Icons.horizontal_rule_rounded;
        break;
      default:
        color = const Color(0xFFD85040);
        label = 'خسارة';
        icon = Icons.close_rounded;
    }

    final date = g.endTime;
    final dateStr = date == null
        ? ''
        : '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';

    return Material(
      color: const Color(0xFF3A3937),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _openGame(g),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: 8),
              CircleAvatar(
                radius: 19,
                backgroundColor: color.withValues(alpha: .15),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ضد $opponent',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${g.timeClass.isEmpty ? 'Chess.com' : g.timeClass} • $dateStr',
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Text(
                label,
                style: TextStyle(color: color, fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_left_rounded, color: Colors.white38),
            ],
          ),
        ),
      ),
    );
  }
}
