import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'chesscom_import_screen.dart';
import 'main.dart' show PositionAnalyzerScreen;
import 'my_library_screen.dart';
import 'pgn_import_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';

const Color _kBg = Color(0xFF0A0E17);
const Color _kGold = Color(0xFFF2C14E);

/// الشاشة الرئيسية لتطبيق ChessCraft.
///
/// الأزرار صور ذهبية جاهزة (assets/images/btn_*.png) وفوقها النص.
/// الأزرار التي لم تُبنَ بعد (الألغاز) معطّلة وتظهر بشارة «قريبًا».
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  void _comingSoon(BuildContext context) {
    final messenger = ScaffoldMessenger.of(context);

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'هذه الميزة قيد البناء — قريبًا',
            textDirection: TextDirection.rtl,
          ),
          duration: Duration(seconds: 2),
        ),
      );
  }

  /// اختيار مصدر المباراة: PGN / Chess.com / مباراة محفوظة.
  void _chooseGameSource(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF121826),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheet) => SafeArea(
        child: ListTileTheme(
          textColor: Colors.white,
          iconColor: _kGold,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.content_paste_rounded),
                title: const Text('استيراد PGN'),
                onTap: () {
                  Navigator.pop(sheet);
                  _open(context, const PgnImportScreen());
                },
              ),
              ListTile(
                leading: const Icon(Icons.travel_explore_rounded),
                title: const Text('Chess.com'),
                onTap: () {
                  Navigator.pop(sheet);
                  _open(context, const ChessComImportScreen());
                },
              ),
              ListTile(
                leading: const Icon(Icons.folder_rounded),
                title: const Text('مباراة محفوظة'),
                onTap: () {
                  Navigator.pop(sheet);
                  _open(context, const GameLibraryScreen());
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final buttons = <_HomeButtonData>[
      _HomeButtonData(
        asset: 'assets/images/btn_stats.png',
        aspect: 1100 / 223,
        title: 'إحصائياتك',
        subtitle: 'تابع تقدمك ونقاط قوتك وضعفك',
        onTap: () => _open(context, const StatsScreen()),
      ),
      _HomeButtonData(
        asset: 'assets/images/btn_game.png',
        aspect: 1100 / 229,
        title: 'تحليل مباراة',
        subtitle: 'حلّل ملفات PGN أو مبارياتك',
        onTap: () => _chooseGameSource(context),
      ),
      _HomeButtonData(
        asset: 'assets/images/btn_position.png',
        aspect: 1100 / 222,
        title: 'تحليل وضعية',
        subtitle: 'حلّل أي وضعية على الرقعة',
        onTap: () => _open(context, const PositionAnalyzerScreen()),
      ),
      _HomeButtonData(
        asset: 'assets/images/btn_brilliant.png',
        aspect: 1100 / 237,
        title: 'ألغاز بريلينت',
        subtitle: 'تدرّب على أجمل النقلات الرائعة',
        onTap: () => _comingSoon(context),
        enabled: false,
      ),
      _HomeButtonData(
        asset: 'assets/images/btn_checkmate.png',
        aspect: 1100 / 228,
        title: 'ألغاز جيك ميت',
        subtitle: 'حل تمارين الكش مات',
        onTap: () => _comingSoon(context),
        enabled: false,
      ),
      _HomeButtonData(
        asset: 'assets/images/btn_mygames.png',
        aspect: 1100 / 232,
        title: 'ألغاز من مبارياتك',
        subtitle: 'تمارين من أخطائك ومبارياتك',
        onTap: () => _comingSoon(context),
        enabled: false,
      ),
    ];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _kBg,
        body: Stack(
          children: [
            const _HeroBackground(),
            SafeArea(
              child: Stack(
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                        children: [
                          const _Header(),
                          const SizedBox(height: 112),
                          for (final b in buttons) ...[
                            _HomeButton(data: b),
                            const SizedBox(height: 10),
                          ],
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    right: 16,
                    child: _SettingsButton(
                      onTap: () => _open(context, const SettingsScreen()),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------
// الخلفية (الملك والحصان) تتلاشى نحو لون الشاشة
// ----------------------------------------------------------------

class _HeroBackground extends StatelessWidget {
  const _HeroBackground();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: 420,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/home_bg.jpg',
            fit: BoxFit.cover,
            alignment: Alignment.centerRight,
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x330A0E17),
                  Color(0x990A0E17),
                  _kBg,
                ],
                stops: [0.0, 0.65, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------
// الشعار + اسم التطبيق
// ----------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Image.asset(
            'assets/images/logo.png',
            height: 74,
            filterQuality: FilterQuality.medium,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: RichText(
                    text: const TextSpan(
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                        height: 1.1,
                      ),
                      children: [
                        TextSpan(
                          text: 'Chess',
                          style: TextStyle(color: Colors.white),
                        ),
                        TextSpan(
                          text: 'Craft',
                          style: TextStyle(color: _kGold),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'حلّل • العب • تعلّم • تطوّر',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    color: Color(0xFFB8BECB),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          // مساحة تمنع تداخل الاسم مع زر الإعدادات.
          const SizedBox(width: 52),
        ],
      ),
    );
  }
}

class _SettingsButton extends StatelessWidget {
  final VoidCallback onTap;

  const _SettingsButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xCC111A2C),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0x33FFFFFF)),
          ),
          child: const Icon(
            Icons.settings_rounded,
            color: Colors.white,
            size: 24,
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------
// زر الصورة الذهبية
// ----------------------------------------------------------------

class _HomeButtonData {
  final String asset;
  final double aspect;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool enabled;

  const _HomeButtonData({
    required this.asset,
    required this.aspect,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.enabled = true,
  });
}

class _HomeButton extends StatelessWidget {
  final _HomeButtonData data;

  const _HomeButton({required this.data});

  /// يحوّل الصورة إلى شبه رمادية للأزرار المعطّلة.
  static const ColorFilter _dim = ColorFilter.matrix(<double>[
    0.30, 0.45, 0.10, 0, -8, //
    0.30, 0.45, 0.10, 0, -8,
    0.30, 0.45, 0.10, 0, -8,
    0, 0, 0, 0.75, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      data.asset,
      fit: BoxFit.fitWidth,
      width: double.infinity,
      filterQuality: FilterQuality.medium,
    );

    return Semantics(
      button: true,
      enabled: data.enabled,
      label: data.title,
      child: AspectRatio(
        aspectRatio: data.aspect,
        child: LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            final h = c.maxHeight;

            // مساحة النص: بين مربع الأيقونة (يسار) وقطع الشطرنج (يمين).
            final textLeft = w * 0.205;
            final textWidth = w * 0.42;

            final titleSize = (h * 0.30).clamp(15.0, 22.0).toDouble();
            final subSize = (h * 0.175).clamp(10.5, 14.0).toDouble();

            return Stack(
              children: [
                Positioned.fill(
                  child: data.enabled
                      ? image
                      : ColorFiltered(colorFilter: _dim, child: image),
                ),
                Positioned(
                  left: textLeft,
                  width: textWidth,
                  top: 0,
                  bottom: 0,
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            data.title,
                            textDirection: TextDirection.rtl,
                            style: TextStyle(
                              color: data.enabled
                                  ? Colors.white
                                  : const Color(0xFFB9BDC6),
                              fontSize: titleSize,
                              fontWeight: FontWeight.w800,
                              shadows: const [
                                Shadow(
                                  color: Color(0xCC000000),
                                  blurRadius: 6,
                                  offset: Offset(0, 1),
                                ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(height: h * 0.03),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            data.subtitle,
                            textDirection: TextDirection.rtl,
                            style: TextStyle(
                              color: data.enabled
                                  ? const Color(0xFFE9D9B0)
                                  : const Color(0xFF9096A3),
                              fontSize: subSize,
                              fontWeight: FontWeight.w500,
                              shadows: const [
                                Shadow(
                                  color: Color(0xCC000000),
                                  blurRadius: 5,
                                  offset: Offset(0, 1),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (!data.enabled)
                  Positioned(
                    top: h * 0.10,
                    left: w * 0.205,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xCC000000),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0x66F2C14E)),
                      ),
                      child: const Text(
                        'قريبًا',
                        textDirection: TextDirection.rtl,
                        style: TextStyle(
                          color: _kGold,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                Positioned.fill(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(h / 2),
                      splashColor: const Color(0x33F2C14E),
                      highlightColor: const Color(0x14F2C14E),
                      onTap: data.onTap,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
