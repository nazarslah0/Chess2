import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'main.dart' show PositionAnalyzerScreen;
import 'pgn_import_screen.dart';
import 'my_games_screen.dart';
import 'app_theme.dart';

/// الصفحة الرئيسية الجديدة لـ Chess2 — لوحة تحكم سريعة بدل قائمة أزرار تقليدية.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: Chess2Theme.surface2,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Chess2Theme.border),
                      ),
                      child: const Icon(Icons.sports_esports_outlined, color: Chess2Theme.blue, size: 30),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Chess2', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                          SizedBox(height: 2),
                          Text('محلل الشطرنج الاحترافي', style: TextStyle(color: Chess2Theme.muted, fontSize: 12)),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'الإعدادات',
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const _SettingsScreen()),
                      ),
                      icon: const Icon(Icons.settings_outlined),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
              sliver: SliverToBoxAdapter(
                child: _HeroCard(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PositionAnalyzerScreen()),
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              sliver: SliverToBoxAdapter(
                child: Text('تحليل ومراجعة', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
              sliver: SliverGrid.count(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.18,
                children: [
                  _DashboardCard(
                    icon: Icons.description_outlined,
                    title: 'تحليل PGN',
                    subtitle: 'مباراة كاملة',
                    color: Chess2Theme.blue,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PgnImportScreen())),
                  ),
                  _DashboardCard(
                    icon: Icons.library_books_outlined,
                    title: 'مبارياتي',
                    subtitle: 'Chess.com / Lichess',
                    color: Chess2Theme.green,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyGamesScreen())),
                  ),
                  _DashboardCard(
                    icon: Icons.auto_graph_rounded,
                    title: 'Game Review',
                    subtitle: 'أخطاء ولحظات حرجة',
                    color: Chess2Theme.orange,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PgnImportScreen())),
                  ),
                  _DashboardCard(
                    icon: Icons.school_outlined,
                    title: 'المدرب',
                    subtitle: 'قريبًا',
                    color: const Color(0xFFB38CFF),
                    onTap: () => _showComingSoon(context),
                  ),
                ],
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
              sliver: SliverToBoxAdapter(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Chess2Theme.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Chess2Theme.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.bolt_rounded, color: Chess2Theme.blue),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('تحليل متعدد الأنوية', style: TextStyle(fontWeight: FontWeight.w800)),
                            SizedBox(height: 3),
                            Text('Fast Pass + Deep Review + Cache', style: TextStyle(color: Chess2Theme.muted, fontSize: 12)),
                          ],
                        ),
                      ),
                      Text('${PlatformInfo.workerCount}×', style: const TextStyle(color: Chess2Theme.blue, fontWeight: FontWeight.w900, fontSize: 18)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static void _showComingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Personal Chess Coach — قريبًا')));
  }
}

class PlatformInfo {
  static int get workerCount {
    final processors = Platform.numberOfProcessors;
    final suggested = processors >= 4 ? processors - 1 : processors;
    return math.max(1, math.min(6, suggested));
  }
}

class _HeroCard extends StatelessWidget {
  final VoidCallback onTap;
  const _HeroCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF123F75), Color(0xFF0D223A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFF275D91)),
        ),
        child: Row(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(.10),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.analytics_outlined, size: 34, color: Colors.white),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('تحليل وضعية', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
                  SizedBox(height: 5),
                  Text('FEN • Best Move • PV • أسهم واضحة', style: TextStyle(color: Color(0xFFC7D8EA), fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_left_rounded, color: Colors.white),
          ],
        ),
      ),
    );
  }
}

class _DashboardCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _DashboardCard({required this.icon, required this.title, required this.subtitle, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Chess2Theme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Chess2Theme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: color.withOpacity(.13), borderRadius: BorderRadius.circular(13)),
              child: Icon(icon, color: color),
            ),
            const Spacer(),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 3),
            Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Chess2Theme.muted, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _SettingsScreen extends StatelessWidget {
  const _SettingsScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const _SettingTile(icon: Icons.speed_rounded, title: 'سرعة التحليل', value: 'Fast + Deep'),
          _SettingTile(icon: Icons.memory_rounded, title: 'المعالج المتوازي', value: 'حتى ${PlatformInfo.workerCount} Workers'),
          const _SettingTile(icon: Icons.psychology_outlined, title: 'المحرك', value: 'Stockfish 19'),
          const _SettingTile(icon: Icons.palette_outlined, title: 'المظهر', value: 'Dark Pro'),
          const _SettingTile(icon: Icons.volume_up_outlined, title: 'الأصوات', value: 'مفعّلة'),
        ],
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  const _SettingTile({required this.icon, required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Chess2Theme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Chess2Theme.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: Chess2Theme.blue),
          const SizedBox(width: 12),
          Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700))),
          Text(value, style: const TextStyle(color: Chess2Theme.muted, fontSize: 12)),
        ],
      ),
    );
  }
}
