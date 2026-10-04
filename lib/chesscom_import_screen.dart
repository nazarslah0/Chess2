import 'package:flutter/material.dart';

import 'chesscom_import_controller.dart';
import 'chesscom_repository.dart';
import 'my_library_screen.dart';

/// استيراد مباريات Chess.com (Public API فقط) إلى مكتبة المباريات.
class ChessComImportScreen extends StatefulWidget {
  const ChessComImportScreen({super.key});

  @override
  State<ChessComImportScreen> createState() => _ChessComImportScreenState();
}

class _ChessComImportScreenState extends State<ChessComImportScreen> {
  final ChessComImportController _c = ChessComImportController();
  final TextEditingController _user = TextEditingController();

  static const bg = Color(0xFF312E2B);
  static const panel = Color(0xFF262522);
  static const green = Color(0xFF81B64C);

  @override
  void initState() {
    super.initState();
    _c.init().then((_) {
      if (mounted && _user.text.isEmpty) _user.text = _c.username;
    });
  }

  @override
  void dispose() {
    _c.dispose();
    _user.dispose();
    super.dispose();
  }

  static const _periods = <ImportPeriod, String>{
    ImportPeriod.lastMonth: 'آخر شهر',
    ImportPeriod.last3Months: 'آخر 3 أشهر',
    ImportPeriod.last6Months: 'آخر 6 أشهر',
    ImportPeriod.thisYear: 'هذه السنة',
    ImportPeriod.month: 'اختيار شهر',
    ImportPeriod.all: 'كل الأشهر المتاحة',
  };

  List<({int year, int month})> _recentMonths() {
    final now = DateTime.now();

    return [
      for (var i = 0; i < 36; i++)
        (
          year: DateTime(now.year, now.month - i).year,
          month: DateTime(now.year, now.month - i).month,
        ),
    ];
  }

  Future<void> _import() async {
    final r = await _c.importSelected();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('تم استيراد ${r.added} مباراة'
            '${r.skipped > 0 ? ' (تجاهل ${r.skipped} مكررة)' : ''}'),
        action: SnackBarAction(
          label: 'مكتبتي',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const GameLibraryScreen()),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: panel,
        foregroundColor: Colors.white,
        title: const Text('استيراد من Chess.com'),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _c,
          builder: (context, _) => Column(
            children: [
              _form(),
              if (_c.error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      _c.error!,
                      style: const TextStyle(color: Color(0xFFE57373)),
                    ),
                  ),
                ),
              if (_c.loading)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _c.progress,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                      TextButton(
                        onPressed: _c.cancel,
                        child: const Text('إلغاء'),
                      ),
                    ],
                  ),
                ),
              if (_c.items.isNotEmpty) _listHeader(),
              Expanded(child: _list()),
              if (_c.items.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: green),
                      onPressed: _c.selected.isEmpty ? null : _import,
                      child: Text('استيراد المحدد (${_c.selected.length})'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _form() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _user,
            style: const TextStyle(color: Colors.white),
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _c.fetch(_user.text),
            decoration: InputDecoration(
              labelText: 'اسم المستخدم',
              labelStyle: const TextStyle(color: Colors.white70),
              prefixIcon: const Icon(Icons.person_outline, color: Colors.white70),
              filled: true,
              fillColor: panel,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            children: [
              for (final e in _periods.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: _c.period == e.key,
                  onSelected: _c.loading ? null : (_) => _c.setPeriod(e.key),
                ),
            ],
          ),
          if (_c.period == ImportPeriod.month)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: DropdownButton<({int year, int month})>(
                isExpanded: true,
                dropdownColor: panel,
                hint: const Text('اختر الشهر', style: TextStyle(color: Colors.white70)),
                value: _c.month,
                items: [
                  for (final m in _recentMonths())
                    DropdownMenuItem(
                      value: m,
                      child: Text(
                        '${m.year}/${m.month.toString().padLeft(2, '0')}',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                ],
                onChanged: (m) {
                  if (m != null) _c.setMonth(m);
                },
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: green),
                  onPressed: _c.loading ? null : () => _c.fetch(_user.text),
                  child: const Text('جلب المباريات'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _c.syncing || _c.loading ? null : () => _c.syncNow(_user.text),
                icon: _c.syncing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync_rounded),
                label: const Text('مزامنة الآن'),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              [
                if (_c.syncState != null)
                  'آخر مزامنة: ${DateTime.fromMillisecondsSinceEpoch(_c.syncState!.lastSyncMs).toString().substring(0, 10)}',
                if (_c.syncMessage != null) _c.syncMessage!,
              ].join(' — '),
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _listHeader() {
    final newCount = _c.items.where((g) => !_c.existing.contains(g.id)).length;

    return CheckboxListTile(
      dense: true,
      activeColor: green,
      value: _c.allSelected,
      onChanged: (v) => _c.toggleAll(v ?? false),
      title: Text(
        'تم العثور على ${_c.items.length} مباراة ($newCount جديدة) — تحديد الكل',
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
    );
  }

  Widget _list() {
    return ListView.builder(
      itemCount: _c.items.length,
      itemBuilder: (context, i) {
        final g = _c.items[i];
        final exists = _c.existing.contains(g.id);

        return CheckboxListTile(
          dense: true,
          activeColor: green,
          value: exists || _c.selected.contains(g.id),
          onChanged: exists ? null : (_) => _c.toggle(g.id),
          title: Text(
            '${g.white} vs ${g.black}',
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          subtitle: Text(
            [
              g.date.replaceAll('.', '/'),
              g.result,
              g.timeClass,
              if (g.whiteRating != null && g.blackRating != null)
                '${g.whiteRating} - ${g.blackRating}',
              if (exists) 'موجودة',
            ].where((e) => e.isNotEmpty).join('  •  '),
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        );
      },
    );
  }
}
