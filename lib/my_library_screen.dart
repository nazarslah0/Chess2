import 'package:flutter/material.dart';

import 'analysis_cache.dart';
import 'game_analysis_screen.dart';
import 'game_library.dart';

/// مكتبة مبارياتي: كل المباريات المحفوظة (Chess.com / PGN) مع بحث
/// وتصفية وحالة التحليل.
class GameLibraryScreen extends StatefulWidget {
  const GameLibraryScreen({super.key});

  @override
  State<GameLibraryScreen> createState() => _GameLibraryScreenState();
}

class _GameLibraryScreenState extends State<GameLibraryScreen> {
  static const bg = Color(0xFF312E2B);
  static const panel = Color(0xFF262522);
  static const green = Color(0xFF81B64C);

  List<LibraryGame> _games = <LibraryGame>[];
  Set<String> _analyzed = <String>{};
  bool _loading = true;

  String _query = '';
  String? _source; // chess_com / pgn
  String? _outcome; // win / loss / draw
  String? _timeClass; // blitz / rapid / bullet
  bool? _rated;
  bool? _analyzedOnly;
  int _days = 0; // 0 = الكل

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final games = await GameLibraryStorage.instance.all();
    final settings = analysisSettingsKey();

    final analyzed = <String>{};

    for (final g in games) {
      if (await AnalysisCache.instance.contains(libraryAnalysisKey(g, settings))) {
        analyzed.add(g.id);
      }
    }

    if (!mounted) return;

    setState(() {
      _games = games;
      _analyzed = analyzed;
      _loading = false;
    });
  }

  List<LibraryGame> get _filtered {
    final q = _query.trim().toLowerCase();
    final since = _days == 0
        ? 0
        : DateTime.now().subtract(Duration(days: _days)).millisecondsSinceEpoch;

    return [
      for (final g in _games)
        if ((q.isEmpty ||
                g.white.toLowerCase().contains(q) ||
                g.black.toLowerCase().contains(q)) &&
            (_source == null || g.source == _source) &&
            (_outcome == null || g.outcome == _outcome) &&
            (_timeClass == null || g.timeClass == _timeClass) &&
            (_rated == null || g.rated == _rated) &&
            (_analyzedOnly == null ||
                _analyzed.contains(g.id) == _analyzedOnly) &&
            (since == 0 || g.endTimeMs == 0 || g.endTimeMs >= since))
          g,
    ];
  }

  Widget _chip<T>(String label, T? current, T value, ValueChanged<T?> set) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: FilterChip(
        label: Text(label),
        selected: current == value,
        onSelected: (on) => set(on ? value : null),
      ),
    );
  }

  void _open(LibraryGame g) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => GameAnalysisScreen(
              pgn: g.pgn,
              whiteLabel: g.white,
              blackLabel: g.black,
              resultLabel: g.result,
              sourceLabel: g.source == kSourceChessCom ? 'Chess.com' : 'PGN',
              userName: g.username,
            ),
          ),
        )
        .then((_) => _load());
  }

  Future<void> _delete(LibraryGame g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('حذف المباراة؟'),
        content: Text('${g.white} vs ${g.black}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('حذف')),
        ],
      ),
    );

    if (ok != true) return;

    await GameLibraryStorage.instance.remove(g.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: panel,
        foregroundColor: Colors.white,
        title: const Text('مبارياتي'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: TextField(
                style: const TextStyle(color: Colors.white),
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'بحث عن لاعب',
                  hintStyle: const TextStyle(color: Colors.white38),
                  prefixIcon: const Icon(Icons.search, color: Colors.white70),
                  filled: true,
                  fillColor: panel,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  _chip<String>('Chess.com', _source, kSourceChessCom, (v) => setState(() => _source = v)),
                  _chip<String>('PGN', _source, kSourcePgn, (v) => setState(() => _source = v)),
                  _chip<bool>('المحللة', _analyzedOnly, true, (v) => setState(() => _analyzedOnly = v)),
                  _chip<bool>('غير المحللة', _analyzedOnly, false, (v) => setState(() => _analyzedOnly = v)),
                  _chip<String>('فوز', _outcome, 'win', (v) => setState(() => _outcome = v)),
                  _chip<String>('خسارة', _outcome, 'loss', (v) => setState(() => _outcome = v)),
                  _chip<String>('تعادل', _outcome, 'draw', (v) => setState(() => _outcome = v)),
                  _chip<String>('Blitz', _timeClass, 'blitz', (v) => setState(() => _timeClass = v)),
                  _chip<String>('Rapid', _timeClass, 'rapid', (v) => setState(() => _timeClass = v)),
                  _chip<String>('Bullet', _timeClass, 'bullet', (v) => setState(() => _timeClass = v)),
                  _chip<bool>('Rated', _rated, true, (v) => setState(() => _rated = v)),
                  _chip<bool>('Unrated', _rated, false, (v) => setState(() => _rated = v)),
                  _chip<int>('آخر 30 يومًا', _days == 0 ? null : _days, 30, (v) => setState(() => _days = v ?? 0)),
                  _chip<int>('آخر سنة', _days == 0 ? null : _days, 365, (v) => setState(() => _days = v ?? 0)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                '${list.length} من ${_games.length} مباراة',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : list.isEmpty
                      ? const Center(
                          child: Text(
                            'لا توجد مباريات. استورد من Chess.com أو الصق PGN.',
                            style: TextStyle(color: Colors.white54),
                          ),
                        )
                      : ListView.builder(
                          itemCount: list.length,
                          itemBuilder: (context, i) => _tile(list[i]),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(LibraryGame g) {
    final analyzed = _analyzed.contains(g.id);
    final out = g.outcome;

    final color = out == 'win'
        ? green
        : out == 'loss'
            ? const Color(0xFFCA3431)
            : Colors.white54;

    return ListTile(
      onTap: () => _open(g),
      onLongPress: () => _delete(g),
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.2),
        child: Text(g.result == '1/2-1/2' ? '½' : g.result.split('-').first,
            style: TextStyle(color: color, fontWeight: FontWeight.bold)),
      ),
      title: Text('${g.white} vs ${g.black}',
          style: const TextStyle(color: Colors.white, fontSize: 14)),
      subtitle: Text(
        [
          g.date.replaceAll('.', '/'),
          if (g.timeClass.isNotEmpty) g.timeClass,
          if (g.whiteRating != null && g.blackRating != null)
            '${g.whiteRating} - ${g.blackRating}',
          g.source == kSourceChessCom ? 'Chess.com' : 'PGN',
        ].join('  •  '),
        style: const TextStyle(color: Colors.white54, fontSize: 12),
      ),
      trailing: Icon(
        analyzed ? Icons.check_circle_rounded : Icons.query_stats_rounded,
        color: analyzed ? green : Colors.white38,
      ),
    );
  }
}
