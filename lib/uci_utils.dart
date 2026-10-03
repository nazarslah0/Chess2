/// تحويل/مقارنة نقلات UCI — مصدر واحد موحّد لكل تحويلات
/// UCI → مربع الرقعة في المشروع، بدل تكرار substring/startsWith
/// في أماكن متفرقة (وهو ما كان يسبب أخطاء مثل مطابقة
/// "e7e8" مع "e7e8q" وأيضًا مع "e7e1" بالخطأ عبر startsWith
/// الساذج على نصوص قصيرة).
class UciMove {
  final String from;
  final String to;

  /// حرف الترقية بحروف صغيرة (q/r/b/n) أو null إن لم تكن
  /// النقلة ترقية.
  final String? promotion;

  const UciMove({
    required this.from,
    required this.to,
    this.promotion,
  });

  /// يحلّل نص UCI مثل "e2e4" أو "e7e8q". يعيد null إن كان
  /// النص غير صالح (غير 4 أو 5 أحرف، أو مربعات خارج النطاق).
  static UciMove? parse(String? uci) {
    if (uci == null) return null;

    final u = uci.trim();

    if (u.length != 4 && u.length != 5) {
      return null;
    }

    final from = u.substring(0, 2);
    final to = u.substring(2, 4);

    if (!_isSquare(from) || !_isSquare(to)) {
      return null;
    }

    final promo =
        u.length == 5 ? u.substring(4).toLowerCase() : null;

    if (promo != null &&
        !['q', 'r', 'b', 'n'].contains(promo)) {
      return null;
    }

    return UciMove(from: from, to: to, promotion: promo);
  }

  static bool _isSquare(String s) {
    if (s.length != 2) return false;

    final file = s.codeUnitAt(0);
    final rank = s.codeUnitAt(1);

    return file >= 'a'.codeUnitAt(0) &&
        file <= 'h'.codeUnitAt(0) &&
        rank >= '1'.codeUnitAt(0) &&
        rank <= '8'.codeUnitAt(0);
  }

  /// مقارنة كاملة ودقيقة: from + to + promotion (إن وُجدت).
  /// هذه هي الطريقة الوحيدة الصحيحة لمعرفة "هل هذه نفس
  /// النقلة؟" — لا تستخدم startsWith أبدًا لهذا الغرض، لأن
  /// "e7e8" هي بادئة نصية لكل من "e7e8q" و"e7e8r" و"e7e1"
  /// (لو وُجد مربع e8 بالخطأ كجزء من نص آخر).
  bool sameMove(UciMove? other) {
    if (other == null) return false;

    if (from != other.from || to != other.to) {
      return false;
    }

    // إن كانت إحدى النقلتين بلا ترقية والأخرى بترقية، فهما
    // مختلفتان فقط إذا كانت الأخرى تحمل ترقية فعلية مختلفة.
    // نقلة بلا حرف ترقية مُسجَّلة من UCI الأساسي (4 أحرف)
    // تُقارَن بالتطابق الحرفي لحقل promotion نفسه.
    return promotion == other.promotion;
  }

  String get uci => '$from$to${promotion ?? ''}';

  @override
  String toString() => uci;
}

/// تحويل نص UCI إلى [UciMove] (أو null إن كان غير صالح).
/// هذه هي نقطة الدخول الوحيدة لتحليل نصوص UCI في المشروع.
UciMove? parseUci(String? uci) => UciMove.parse(uci);

/// دالة مختصرة: هل نص UCI الأول يطابق (from/to/promotion)
/// نص UCI الثاني تمامًا؟
bool isSameUciMove(String? a, String? b) {
  final pa = UciMove.parse(a);
  final pb = UciMove.parse(b);

  if (pa == null || pb == null) return false;

  return pa.sameMove(pb);
}

/// أول نقلة صالحة في قائمة PV (UCI)، أو null.
UciMove? firstValidUci(Iterable<String> pv) {
  for (final u in pv) {
    final m = UciMove.parse(u);

    if (m != null) return m;

    // أول عنصر غير صالح يقطع الخط: لا نتجاوزه إلى ما بعده.
    return null;
  }

  return null;
}
