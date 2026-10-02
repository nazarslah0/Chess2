import 'game_review_models.dart';

/// نتيجة تحليل مباراة كاملة محفوظة — تُستخدم لتفادي إعادة
/// تشغيل Stockfish إن فُتحت نفس المباراة مرة أخرى بنفس إعدادات
/// المحرك خلال نفس جلسة التطبيق.
///
/// ملاحظة صريحة: هذا تخزين مؤقت في الذاكرة (Session cache) —
/// يُفرَّغ عند إغلاق التطبيق، وليس تخزينًا دائمًا على القرص
/// (ذلك يحتاج قاعدة بيانات محلية لم تُضف بعد).
class AnalysisCacheEntry {
  final List<double> evalPawns;
  final List<String> evalLabels;
  final List<String> bestUci;
  final List<List<String>> pvUci;
  final List<int?> secondBestCpWhite;
  final List<MoveQuality> qualities;
  final List<bool> isBestEngineMove;
  final List<int?> moveGapCp;

  const AnalysisCacheEntry({
    required this.evalPawns,
    required this.evalLabels,
    required this.bestUci,
    required this.pvUci,
    required this.secondBestCpWhite,
    required this.qualities,
    required this.isBestEngineMove,
    required this.moveGapCp,
  });
}

class AnalysisCache {
  AnalysisCache._();

  static final AnalysisCache instance = AnalysisCache._();

  final Map<String, AnalysisCacheEntry> _store = {};

  /// مفتاح التخزين المؤقت: محتوى PGN + إعدادات المحرك.
  /// نستخدم hashCode + طول النص كبصمة خفيفة بدون حزمة crypto
  /// خارجية — كافٍ لتخزين مؤقت داخل الجلسة (ليس أمنيًا).
  String keyFor({
    required String pgn,
    required int depth,
    required int multiPv,
    String engineVersion = 'stockfish19',
  }) {
    return '${pgn.hashCode}_${pgn.length}'
        '_d$depth'
        '_mpv$multiPv'
        '_$engineVersion';
  }

  AnalysisCacheEntry? get(String key) => _store[key];

  void put(String key, AnalysisCacheEntry entry) {
    _store[key] = entry;
  }

  void clear() => _store.clear();
}
