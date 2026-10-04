import 'package:flutter/material.dart';

import 'account_storage.dart';
import 'analysis_cache.dart';
import 'analysis_result.dart';
import 'game_library.dart';
import 'game_review_models.dart';
import 'maia_service.dart';
import 'user_stats.dart';

/// إحصائياتي: تُحسب من مبارياتك المحفوظة وتحليلاتها في الكاش.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  static const bg = Color(0xFF312E2B);
  static const panel = Color(0xFF262522);
  static const green = Color(0xFF81B64C);

  /// أقصى عدد تحليلات تُقرأ من الكاش (الأحدث أولًا) لإبقاء الشاشة سريعة.
  static const int _maxAnalyses = 150;

  bool _loading = true;
  String? _user;
  List<String> _users = <String>[];
  Map<String, List<LibraryGame>> _byUser = <String, List<LibraryGame>>{};
  UserStats? _stats;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final all = await GameLibraryStorage.instance.all();

    final by = <String, List<LibraryGame>>{};

    for (final g in all) {
      if (g.userColor != null) (by[g.username] ??= <LibraryGame>[]).add(g);
    }

    final users = by.keys.toList()
      ..sort((a, b) => by[b]!.length.compareTo(by[a]!.length));

    final saved = (await AccountStorage.getChessComUsername())?.toLowerCase();

    _byUser = by;
    _users = users;

    await _select(
      saved != null && by.containsKey(saved)
          ? saved
          : (users.isEmpty ? null : users.first),
    );
  }

  Future<void> _select(String? user) async {
    setState(() {
      _user = user;
      _loading = true;
    });

    if (user == null) {
      setState(() {
        _stats = UserStats();
        _loading = false;
      });
      return;
    }

    final maia = await MaiaService.availableBuckets();
    final settings = analysisSettingsKey(maia);

    final games = _byUser[user]!;
    final items = <({LibraryGame game, GameAnalysis? analysis})>[];

    var loaded = 0;

    for (final g in games) {
      GameAnalysis? a;

      if (loaded < _maxAnalyses) {
        a = await AnalysisCache.instance.load(libraryAnalysisKey(g, settings));

        if (a != null) loaded++;
      }

      items.add((game: g, analysis: a));
    }

    if (!mounted) return;

    setState(() {
      _stats = computeUserStats(items);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: panel,
        foregroundColor: Colors.white,
        title: const Text('إحصائياتي'),
        actions: [
          if (_users.length > 1)
            PopupMenuButton<String>(
              icon: const Icon(Icons.person_outline),
              onSelected: _select,
              itemBuilder: (_) => [
                for (final u in _users) PopupMenuItem(value: u, child: Text(u)),
              ],
            ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : (_stats == null || _stats!.total.games == 0)
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'لا توجد مباريات بعد.\nاستورد مبارياتك من Chess.com ثم حلّلها لتظهر إحصائياتك.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  )
                : _content(_stats!),
      ),
    );
  }

  String _n(double? v, [int d = 0]) => v == null ? '—' : v.toStringAsFixed(d);

  Widget _card(String title, Widget child) => Card(
        color: panel,
        margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              child,
            ],
          ),
        ),
      );

  Widget _kv(String k, String v, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(child: Text(k, style: const TextStyle(color: Colors.white70))),
            Text(v,
                style: TextStyle(
                    color: color ?? Colors.white, fontWeight: FontWeight.w700)),
          ],
        ),
      );

  Widget _content(UserStats s) {
    final t = s.total;

    return ListView(
      children: [
        if (_user != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Text(_user!, style: const TextStyle(color: Colors.white54)),
          ),
        _card(
          'نظرة عامة',
          Column(
            children: [
              _kv('عدد المباريات', '${t.games}'),
              _kv('فوز', '${t.wins}', color: green),
              _kv('خسارة', '${t.losses}', color: const Color(0xFFCA3431)),
              _kv('تعادل', '${t.draws}'),
              _kv('نسبة الفوز', '${_n(t.winRate)}%'),
              const Divider(color: Colors.white12),
              _kv('مباريات محللة', '${t.analyzed}'),
              _kv('متوسط ACPL', _n(t.acpl, 1)),
              _kv('الدقة', t.accuracy == null ? '—' : '${_n(t.accuracy, 1)}%'),
            ],
          ),
        ),
        _card(
          'نقلاتك',
          Column(
            children: [
              for (final q in moveQualityDisplayOrder)
                _kv(moveQualityInfo[q]!.label, '${s.qualities[q] ?? 0}',
                    color: moveQualityInfo[q]!.color),
            ],
          ),
        ),
        _card(
          'حسب نوع اللعب',
          Column(
            children: [
              for (final k in const ['blitz', 'rapid', 'bullet'])
                if (s.byTimeClass[k] != null)
                  _kv(
                    k[0].toUpperCase() + k.substring(1),
                    '${s.byTimeClass[k]!.games} • ${_n(s.byTimeClass[k]!.winRate)}% • '
                        'ACPL ${_n(s.byTimeClass[k]!.acpl, 1)}',
                  ),
            ],
          ),
        ),
        _card(
          'حسب المرحلة (ACPL)',
          Column(
            children: [
              _kv('الافتتاح', _n(s.acplByPhase['opening'], 1)),
              _kv('الوسط', _n(s.acplByPhase['middlegame'], 1)),
              _kv('النهاية', _n(s.acplByPhase['endgame'], 1)),
            ],
          ),
        ),
      ],
    );
  }
}
