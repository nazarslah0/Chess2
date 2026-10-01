import 'package:flutter/material.dart';

import 'game_analysis_screen.dart';
import 'pgn_utils.dart';
import 'app_theme.dart';

class PgnImportScreen extends StatefulWidget {
  const PgnImportScreen({super.key});

  @override
  State<PgnImportScreen> createState() => _PgnImportScreenState();
}

class _PgnImportScreenState extends State<PgnImportScreen> {
  final TextEditingController _pgnCtrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pgnCtrl.dispose();
    super.dispose();
  }

  void _analyze() {
    final pgn = _pgnCtrl.text.trim();
    if (pgn.isEmpty) {
      setState(() => _error = 'الصق نص PGN أولًا.');
      return;
    }

    final plies = parsePgnMoves(pgn);
    if (plies == null || plies.isEmpty) {
      setState(() => _error = 'تعذر قراءة هذا الـ PGN. تحقق من الصيغة.');
      return;
    }

    setState(() => _error = null);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GameAnalysisScreen(
          pgn: pgn,
          sourceLabel: 'PGN مستورد',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تحليل مباراة PGN')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Chess2Theme.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Chess2Theme.border),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.description_outlined, color: Chess2Theme.blue),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('أدخل مباراة', style: TextStyle(fontWeight: FontWeight.w900)),
                          SizedBox(height: 3),
                          Text('سنحللها سريعًا ثم نفحص اللحظات المهمة بعمق.', style: TextStyle(color: Chess2Theme.muted, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: TextField(
                  controller: _pgnCtrl,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  decoration: const InputDecoration(
                    hintText: '[White "Player"]\n[Black "Opponent"]\n[Result "1-0"]\n\n1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 ...',
                    alignLabelWithHint: true,
                    prefixIcon: Padding(padding: EdgeInsets.only(bottom: 240), child: Icon(Icons.code_rounded)),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Chess2Theme.red)),
              ],
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _analyze,
                icon: const Icon(Icons.bolt_rounded),
                label: const Text('ابدأ التحليل'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
