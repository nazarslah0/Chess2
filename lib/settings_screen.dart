import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'board_widget.dart';
import 'maia_service.dart';
import 'models.dart';

/// الإعدادات العامة: ثيم الرقعة والقطع (تنطبق على كل رقع التطبيق)،
/// مستوى Maia الافتراضي، واسمك في المباريات.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final AppSettings _s = AppSettings.instance;

  final GameState _preview = GameState();

  late final TextEditingController _nameCtrl =
      TextEditingController(text: _s.playerName);

  List<int> _maiaAvailable = const <int>[];

  @override
  void initState() {
    super.initState();

    _preview.startPosition();

    MaiaService.availableBuckets().then((v) {
      if (mounted) setState(() => _maiaAvailable = v);
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _preview.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _s,
          builder: (context, _) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'المظهر (لكل رقع التطبيق)',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 280),
                    child: BoardWidget(
                      state: _preview,
                      boardTheme: _s.boardTheme,
                      pieceTheme: _s.pieceTheme,
                      onTap: (_) {},
                      interactive: false,
                      showCoordinates: false,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  decoration:
                      const InputDecoration(labelText: 'ثيم الرقعة'),
                  initialValue: _s.boardThemeIndex,
                  isExpanded: true,
                  items: [
                    for (var i = 0;
                        i < AppSettings.allBoardThemes.length;
                        i++)
                      DropdownMenuItem<int>(
                        value: i,
                        child: Text(AppSettings.allBoardThemes[i].name),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) _s.setBoardTheme(v);
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  decoration:
                      const InputDecoration(labelText: 'ثيم القطع'),
                  initialValue: _s.pieceThemeIndex,
                  isExpanded: true,
                  items: [
                    for (var i = 0;
                        i < AppSettings.allPieceThemes.length;
                        i++)
                      DropdownMenuItem<int>(
                        value: i,
                        child: Text(AppSettings.allPieceThemes[i].name),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) _s.setPieceTheme(v);
                  },
                ),
                const Divider(height: 32),
                const Text(
                  'Maia',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  _maiaAvailable.isEmpty
                      ? 'لم يتم العثور على أوزان Maia في التطبيق '
                          '(انظر assets/maia/README.txt).'
                      : 'المستوى الافتراضي في تحليل الوضعية واللعب:',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final b in MaiaService.buckets)
                      ChoiceChip(
                        label: Text('$b'),
                        selected: _s.maiaBucket == b,
                        onSelected: _maiaAvailable.contains(b)
                            ? (_) => _s.setMaiaBucket(b)
                            : null,
                      ),
                  ],
                ),
                const Divider(height: 32),
                const Text(
                  'اسمك في المباريات',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  'اسم مستخدمك في Chess.com أو Lichess. يُستخدم لمعرفة أي '
                  'لاعب هو أنت عند استخراج التمارين من أخطائك.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameCtrl,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'اسم المستخدم',
                  ),
                  onChanged: _s.setPlayerName,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
