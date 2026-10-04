import 'package:flutter/material.dart';

import 'main.dart' show PositionAnalyzerScreen;
import 'pgn_import_screen.dart';
import 'settings_screen.dart';

/// الشاشة الرئيسية الجديدة لـ ChessCraft.
/// (الشاشة القديمة محفوظة في classic_home_screen.dart.)
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  void _soon(BuildContext context) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('قريبًا ✨'),
          duration: Duration(seconds: 1),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    const base = 'assets';

    // screen == null  =>  "قريبًا"
    final items = <_Item>[
      const _Item('stats', 'إحصائياتك', 'تابع تقدمك ونقاط قوتك وضعفك', null),
      const _Item(
          'game', 'تحليل مباراة', 'حلل ملفات PGN أو مبارياتك', 'game'),
      const _Item(
          'position', 'وضعية خاصة', 'حلل أي وضعية على الرقعة', 'position'),
      const _Item(
          'brilliant', 'ألغاز بريليانت', 'تدرب على أجمل النقلات الرائعة', null),
      const _Item('mate', 'ألغاز جيك ميت', 'حل تمارين الكش مات', null),
      const _Item(
          'mine', 'ألغاز من مبارياتك', 'تمارين من أخطائك ومبارياتك', null),
    ];

    Widget? target(String? key) {
      switch (key) {
        case 'game':
          return const PgnImportScreen();
        case 'position':
          return const PositionAnalyzerScreen();
      }
      return null;
    }

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
                        child: Image.asset('assets/ChessCraft/wK.png',
                            height: 190),
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
                      final screen = target(it.screenKey);
                      final soon = screen == null;

                      return GestureDetector(
                        onTap: () =>
                            soon ? _soon(context) : _open(context, screen),
                        child: AspectRatio(
                          aspectRatio: 1000 / 205,
                          child: LayoutBuilder(
                            builder: (context, c) => Stack(
                              fit: StackFit.expand,
                              children: [
                                Opacity(
                                  opacity: soon ? 0.7 : 1,
                                  child: Image.asset(
                                      '$base/ui/btn_${it.id}.webp',
                                      fit: BoxFit.fill),
                                ),
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
                                if (soon)
                                  Positioned(
                                    right: c.maxWidth * 0.13,
                                    top: 10,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.black54,
                                        borderRadius:
                                            BorderRadius.circular(10),
                                        border: Border.all(
                                            color: const Color(0xFFE7B84B)),
                                      ),
                                      child: const Text(
                                        'قريبًا',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFFE7B84B),
                                        ),
                                      ),
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
  final String? screenKey;

  const _Item(this.id, this.title, this.subtitle, this.screenKey);
}
