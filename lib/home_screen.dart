import 'package:flutter/material.dart';

import 'main.dart' show PositionAnalyzerScreen;
import 'pgn_import_screen.dart';
import 'my_games_screen.dart';

/// الشاشة الرئيسية الحقيقية للتطبيق (القائمة الأساسية).
/// الرقعة والتحليل التفصيلي يبقيان في شاشات فرعية منفصلة،
/// حتى لا تزدحم الشاشة الرئيسية.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('محلل الشطرنج ♟️'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 420,
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment:
                    MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.grid_4x4_rounded,
                    size: 56,
                    color: Colors.indigo,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Chess Analyzer',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 32),
                  _MenuButton(
                    icon: Icons.grid_view_rounded,
                    label: 'تحليل وضعية',
                    subtitle:
                        'أنشئ وضعية أو الصق FEN وحلّلها'
                        ' بـ Stockfish',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              const PositionAnalyzerScreen(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  _MenuButton(
                    icon: Icons.query_stats_rounded,
                    label: 'تحليل مباراة',
                    subtitle:
                        'الصق PGN مباراة كاملة وحلّلها'
                        ' نقلة نقلة',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              const PgnImportScreen(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  _MenuButton(
                    icon: Icons.travel_explore_rounded,
                    label: 'مبارياتي',
                    subtitle:
                        'حمّل مبارياتك من Chess.com أو'
                        ' Lichess',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              const MyGamesScreen(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  _MenuButton(
                    icon: Icons.settings_rounded,
                    label: 'الإعدادات',
                    subtitle:
                        'الصوت والمظهر (قريبًا المزيد)',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              const _SettingsPlaceholder(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuButton({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.primary.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor:
                    scheme.primary.withValues(alpha: 0.15),
                child: Icon(
                  icon,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_left),
            ],
          ),
        ),
      ),
    );
  }
}

/// إعدادات مبسّطة (صوت التطبيق). سيُوسَّع لاحقًا (سمة الرقعة،
/// إحداثيات، سرعة التحليل الافتراضية...).
class _SettingsPlaceholder extends StatelessWidget {
  const _SettingsPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الإعدادات'),
      ),
      body: const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'إعدادات الصوت متاحة من داخل شاشة تحليل'
            ' الوضعية حاليًا. سيتم نقلها هنا مستقبلًا'
            ' مع إعدادات إضافية (السمة، الإحداثيات،'
            ' سرعة التحليل الافتراضية).',
          ),
        ),
      ),
    );
  }
}
