import 'package:flutter/material.dart';

import 'main.dart' show PositionAnalyzerScreen;
import 'pgn_import_screen.dart';
import 'puzzles_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';

/// الشاشة الرئيسية لـ ChessCraft: ستة أزرار بصور ذهبية.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    const base = 'assets/chesscraft';

    final items = <_Item>[
      _Item('stats', 'إحصائياتك', 'تابع تقدمك ونقاط قوتك وضعفك',
          const StatsScreen()),
      _Item('game', 'تحليل مباراة', 'حلل ملفات PGN أو مبارياتك',
          const PgnImportScreen()),
      _Item('position', 'تحليل وضعية', 'حلل أي وضعية على الرقعة',
          const PositionAnalyzerScreen()),
      _Item('brilliant', 'ألغاز بريليانت', 'تدرب على أجمل النقلات الرائعة',
          const PuzzlesScreen(mode: 'brilliant', title: 'ألغاز بريليانت')),
      _Item('mate', 'ألغاز جيك ميت', 'حل تمارين الكش مات',
          const PuzzlesScreen(mode: 'mate', title: 'ألغاز جيك ميت')),
      _Item('mine', 'ألغاز من مبارياتك', 'تمارين من أخطائك ومبارياتك',
          const PuzzlesScreen()),
    ];

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0E1526), Color(0xFF05070D)],
          ),
        ),
        child: SafeArea(
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Column(
              children: [
                SizedBox(
                  height: 190,
                  child: Stack(
                    children: [
                      Positioned(
                        right: 10,
                        top: 0,
                        bottom: 0,
                        child: Opacity(
                          opacity: 0.95,
                          child: Image.asset('$base/pieces/wK.png',
                              height: 190),
                        ),
                      ),
                      Positioned(
                        left: 18,
                        top: 30,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Image.asset('$base/ui/logo.png', height: 70),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                RichText(
                                  text: const TextSpan(
                                    style: TextStyle(
                                      fontSize: 34,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                    children: [
                                      TextSpan(text: 'Chess'),
                                      TextSpan(
                                        text: 'Craft',
                                        style: TextStyle(
                                            color: Color(0xFFE7B84B)),
                                      ),
                                    ],
                                  ),
                                ),
                                const Text(
                                  'حلّل • العب • تعلّم • تطوّر',
                                  style: TextStyle(
                                      fontSize: 13, color: Colors.white60),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        right: 12,
                        top: 8,
                        child: IconButton(
                          icon: const Icon(Icons.settings,
                              color: Colors.white70),
                          onPressed: () =>
                              _open(context, const SettingsScreen()),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final it = items[i];
                      return GestureDetector(
                        onTap: () => _open(context, it.screen),
                        child: AspectRatio(
                          aspectRatio: 1000 / 205,
                          child: LayoutBuilder(
                            builder: (context, c) => Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.asset('$base/ui/btn_${it.id}.webp',
                                    fit: BoxFit.fill),
                                Positioned(
                                  left: c.maxWidth * 0.215,
                                  right: c.maxWidth * 0.36,
                                  top: 0,
                                  bottom: 0,
                                  child: Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          it.title,
                                          style: const TextStyle(
                                            fontSize: 21,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.white,
                                            shadows: [
                                              Shadow(
                                                  blurRadius: 6,
                                                  color: Colors.black)
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        it.subtitle,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFFF1DDA8),
                                          shadows: [
                                            Shadow(
                                                blurRadius: 4,
                                                color: Colors.black)
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Item {
  final String id;
  final String title;
  final String subtitle;
  final Widget screen;

  _Item(this.id, this.title, this.subtitle, this.screen);
}
