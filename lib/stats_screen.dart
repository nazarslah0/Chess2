import 'package:flutter/material.dart';

import 'puzzle_storage.dart';

/// إحصائياتك: ملخص تقدمك في التمارين المستخرجة من مبارياتك.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  List<PuzzleItem>? _items;

  @override
  void initState() {
    super.initState();
    PuzzleStorage.load().then((v) {
      if (mounted) setState(() => _items = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final total = items?.length ?? 0;
    final solved = items?.where((e) => e.solvedCount > 0).length ?? 0;
    final mates = items?.where((e) => e.bestSan.contains('#')).length ?? 0;
    final rate = total == 0 ? 0 : (solved * 100 / total).round();

    Widget card(String label, String value, IconData icon) => Card(
          child: ListTile(
            leading: Icon(icon, color: const Color(0xFFE7B84B)),
            title: Text(label),
            trailing: Text(
              value,
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('إحصائياتك')),
      body: items == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                card('تمارين من مبارياتك', '$total', Icons.extension),
                card('تمارين محلولة', '$solved', Icons.check_circle),
                card('نسبة الحل', '$rate%', Icons.trending_up),
                card('تمارين كش مات', '$mates', Icons.gps_fixed),
              ],
            ),
    );
  }
}
