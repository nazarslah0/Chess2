import 'package:flutter/material.dart';

import 'game_review_screen.dart';
import 'lichess_screen.dart';
import 'app_theme.dart';

class MyGamesScreen extends StatelessWidget {
  const MyGamesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('مبارياتي')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            const Text('مصادر المباريات', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
            const SizedBox(height: 5),
            const Text('استورد مبارياتك ثم افتح Game Review والتحليل الكامل.', style: TextStyle(color: Chess2Theme.muted, fontSize: 12)),
            const SizedBox(height: 18),
            _SourceCard(
              title: 'Chess.com',
              subtitle: 'Username → آخر المباريات → تحليل',
              icon: Icons.emoji_events_outlined,
              color: const Color(0xFF7FA650),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GameReviewScreen())),
            ),
            const SizedBox(height: 12),
            _SourceCard(
              title: 'Lichess',
              subtitle: 'Username → المباريات العامة → تحليل',
              icon: Icons.public_rounded,
              color: const Color(0xFFB5B5B5),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LichessScreen())),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _SourceCard({required this.title, required this.subtitle, required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Chess2Theme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Chess2Theme.border),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: color.withValues(alpha: .13), borderRadius: BorderRadius.circular(15)),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(subtitle, style: const TextStyle(color: Chess2Theme.muted, fontSize: 12)),
            ])),
            const Icon(Icons.chevron_left_rounded, color: Chess2Theme.muted),
          ],
        ),
      ),
    );
  }
}
