import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// تمرين شخصي مستخرج من مباراة حلّلتها: وضعية فاتتك فيها نقلة قوية.
class PuzzleItem {
  final String id;

  /// الوضعية قبل النقلة الفائتة (الدور على اللاعب الذي أخطأ).
  final String fen;

  /// أفضل نقلة (UCI) وSAN، والنقلة التي لُعبت فعلًا.
  final String bestUci;
  final String bestSan;
  final String playedSan;

  /// تكملة الخط الرئيسي بصيغة SAN (للعرض بعد الحل).
  final String line;

  /// مستوى Maia المستخدم، واحتمال أن يجد لاعب بهذا المستوى أفضل
  /// نقلة (0..1) — null إن لم يُحسب.
  final int? maiaBucket;
  final double? maiaBestProb;

  /// وصف المباراة (مثل "White vs Black").
  final String label;

  final int createdAt;
  final int solvedCount;

  /// بيانات إضافية اختيارية (للتمارين المستخرجة من مباريات المكتبة):
  /// النوع (blunder / missed_win / missed_tactic / critical / brilliant)،
  /// الصعوبة (1..3)، رد الخصم المتوقع (UCI)، المباراة والنقلة المصدر.
  final String? theme;
  final int? difficulty;
  final String? expectedResponse;
  final String? sourceGameId;
  final int? sourceMoveNumber;

  const PuzzleItem({
    required this.id,
    required this.fen,
    required this.bestUci,
    required this.bestSan,
    required this.playedSan,
    required this.line,
    required this.label,
    required this.createdAt,
    this.maiaBucket,
    this.maiaBestProb,
    this.solvedCount = 0,
    this.theme,
    this.difficulty,
    this.expectedResponse,
    this.sourceGameId,
    this.sourceMoveNumber,
  });

  String get turn {
    final parts = fen.split(' ');

    return parts.length > 1 ? parts[1] : 'w';
  }

  PuzzleItem copyWith({int? solvedCount}) => PuzzleItem(
        id: id,
        fen: fen,
        bestUci: bestUci,
        bestSan: bestSan,
        playedSan: playedSan,
        line: line,
        label: label,
        createdAt: createdAt,
        maiaBucket: maiaBucket,
        maiaBestProb: maiaBestProb,
        solvedCount: solvedCount ?? this.solvedCount,
        theme: theme,
        difficulty: difficulty,
        expectedResponse: expectedResponse,
        sourceGameId: sourceGameId,
        sourceMoveNumber: sourceMoveNumber,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'fen': fen,
        'bestUci': bestUci,
        'bestSan': bestSan,
        'playedSan': playedSan,
        'line': line,
        'label': label,
        'createdAt': createdAt,
        'maiaBucket': maiaBucket,
        'maiaBestProb': maiaBestProb,
        'solvedCount': solvedCount,
        'theme': theme,
        'difficulty': difficulty,
        'expectedResponse': expectedResponse,
        'sourceGameId': sourceGameId,
        'sourceMoveNumber': sourceMoveNumber,
      };

  static PuzzleItem? fromJson(dynamic j) {
    if (j is! Map) return null;

    final fen = j['fen']?.toString();
    final best = j['bestUci']?.toString();

    if (fen == null || best == null || best.length < 4) return null;

    return PuzzleItem(
      id: j['id']?.toString() ?? fen,
      fen: fen,
      bestUci: best,
      bestSan: j['bestSan']?.toString() ?? best,
      playedSan: j['playedSan']?.toString() ?? '',
      line: j['line']?.toString() ?? '',
      label: j['label']?.toString() ?? '',
      createdAt: (j['createdAt'] as num?)?.toInt() ?? 0,
      maiaBucket: (j['maiaBucket'] as num?)?.toInt(),
      maiaBestProb: (j['maiaBestProb'] as num?)?.toDouble(),
      solvedCount: (j['solvedCount'] as num?)?.toInt() ?? 0,
      theme: j['theme']?.toString(),
      difficulty: (j['difficulty'] as num?)?.toInt(),
      expectedResponse: j['expectedResponse']?.toString(),
      sourceGameId: j['sourceGameId']?.toString(),
      sourceMoveNumber: (j['sourceMoveNumber'] as num?)?.toInt(),
    );
  }
}

class PuzzleStorage {
  PuzzleStorage._();

  static const String _key = 'chess2_puzzles_v1';
  static const int maxItems = 200;

  /// مفتاح الوضعية (بدون عدّادات النقلات) لمنع التكرار.
  static String idFor(String fen) =>
      fen.trim().split(RegExp(r'\s+')).take(4).join(' ');

  static Future<List<PuzzleItem>> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);

      if (raw == null || raw.isEmpty) return <PuzzleItem>[];

      final list = jsonDecode(raw);

      if (list is! List) return <PuzzleItem>[];

      return <PuzzleItem>[
        for (final j in list)
          if (PuzzleItem.fromJson(j) != null) PuzzleItem.fromJson(j)!,
      ];
    } catch (_) {
      return <PuzzleItem>[];
    }
  }

  static Future<void> _save(List<PuzzleItem> items) async {
    try {
      final p = await SharedPreferences.getInstance();

      await p.setString(
        _key,
        jsonEncode(<dynamic>[for (final i in items) i.toJson()]),
      );
    } catch (_) {}
  }

  /// يضيف التمارين الجديدة (يتجاهل المكرر). يعيد عدد ما أُضيف فعلًا.
  static Future<int> addAll(List<PuzzleItem> fresh) async {
    if (fresh.isEmpty) return 0;

    final items = await load();
    final ids = items.map((e) => e.id).toSet();

    var added = 0;

    for (final f in fresh) {
      if (ids.add(f.id)) {
        items.insert(0, f);
        added++;
      }
    }

    if (items.length > maxItems) {
      items.removeRange(maxItems, items.length);
    }

    if (added > 0) await _save(items);

    return added;
  }

  static Future<void> markSolved(String id) async {
    final items = await load();

    final i = items.indexWhere((e) => e.id == id);

    if (i < 0) return;

    items[i] = items[i].copyWith(solvedCount: items[i].solvedCount + 1);

    await _save(items);
  }

  static Future<void> remove(String id) async {
    final items = await load();

    items.removeWhere((e) => e.id == id);

    await _save(items);
  }

  static Future<void> clear() => _save(<PuzzleItem>[]);
}
