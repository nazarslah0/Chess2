import 'package:chess/chess.dart' as ch;

/// نقلة واحدة داخل مباراة تم تفكيكها من PGN.
class PgnPly {
  final int number;
  final String color; // 'w' أو 'b'
  final String san;
  final String from;
  final String to;
  final String? promotion;
  final bool isCapture;
  final String fenBefore;
  final String fenAfter;

  const PgnPly({
    required this.number,
    required this.color,
    required this.san,
    required this.from,
    required this.to,
    required this.promotion,
    required this.isCapture,
    required this.fenBefore,
    required this.fenAfter,
  });
}

/// يقرأ حقل من عنصر نقلة قد يكون Map (كما في حزمة chess
/// الحالية) أو كائن Move في إصدارات أخرى.
String? _readField(dynamic item, String key) {
  try {
    if (item is Map) {
      final v = item[key];
      return v?.toString();
    }
  } catch (_) {}

  try {
    final d = item as dynamic;
    switch (key) {
      case 'from':
        return d.fromAlgebraic as String;
      case 'to':
        return d.toAlgebraic as String;
      case 'san':
        return d.san as String;
      default:
        return null;
    }
  } catch (_) {}

  return null;
}

bool _readCapture(dynamic item) {
  try {
    if (item is Map) {
      if (item['captured'] != null) {
        return true;
      }

      final flags = item['flags']?.toString() ?? '';

      return flags.contains('c') ||
          flags.contains('e');
    }
  } catch (_) {}

  try {
    final d = item as dynamic;
    return d.captured != null;
  } catch (_) {}

  return false;
}

/// يستخرج نص النقلات من PGN كامل (مع الرؤوس والتعليقات
/// وأزمنة الساعة كما ترسلها chess.com) ويحوّله إلى رموز SAN.
List<String> _extractSanTokens(String pgn) {
  final lines = pgn.split(RegExp(r'\r?\n'));

  final movetext = lines
      .where(
        (l) => !l.trim().startsWith('['),
      )
      .join(' ');

  // إزالة التعليقات {...}
  var cleaned = movetext.replaceAll(
    RegExp(r'\{[^}]*\}'),
    ' ',
  );

  // إزالة التعليقات ;... حتى نهاية السطر (نادر في PGN المدمج بمسافات لكن للأمان)
  cleaned = cleaned.replaceAll(
    RegExp(r';[^\n]*'),
    ' ',
  );

  // إزالة NAG مثل $1 $2
  cleaned = cleaned.replaceAll(
    RegExp(r'\$\d+'),
    ' ',
  );

  // إزالة أرقام النقلات: "12." أو "12..."
  cleaned = cleaned.replaceAll(
    RegExp(r'\d+\.(\.\.)?'),
    ' ',
  );

  final tokens = cleaned
      .split(RegExp(r'\s+'))
      .where((t) => t.trim().isNotEmpty)
      .toList();

  // إزالة رمز نتيجة المباراة إن وُجد في النهاية.
  const results = {
    '1-0',
    '0-1',
    '1/2-1/2',
    '*',
  };

  while (tokens.isNotEmpty &&
      results.contains(tokens.last)) {
    tokens.removeLast();
  }

  return tokens;
}

/// يستخرج قيمة رأس PGN مثل [FEN "..."]
String? _extractHeader(String pgn, String key) {
  final match = RegExp(
    '\\[$key\\s+"([^"]*)"\\]',
  ).firstMatch(pgn);

  return match?.group(1);
}

/// يفكك مباراة PGN كاملة إلى قائمة نقلات مع FEN قبل/بعد كل
/// نقلة، بإعادة تشغيلها على رقعة حقيقية بدل الاعتماد على
/// نص PGN وحده (لضمان صحة from/to/SAN حتى مع اختلافات
/// التهجئة الطفيفة).
///
/// يعيد null إن تعذّر تفكيك المباراة (تنسيق غير متوقع).
List<PgnPly>? parsePgnMoves(String pgn) {
  try {
    final tokens = _extractSanTokens(pgn);

    if (tokens.isEmpty) {
      return <PgnPly>[];
    }

    final game = ch.Chess();

    final startFen = _extractHeader(pgn, 'FEN');

    if (startFen != null &&
        startFen.trim().isNotEmpty) {
      game.load(startFen.trim());
    }

    final plies = <PgnPly>[];

    for (final token in tokens) {
      final fenBefore = game.fen;

      final turn =
          fenBefore.split(' ').length > 1
              ? fenBefore.split(' ')[1]
              : 'w';

      // نبحث عن النقلة القانونية المطابقة لهذا الرمز SAN من
      // بين النقلات القانونية الفعلية، بدل تمريره مباشرة إلى
      // move()، لضمان الحصول على from/to/isCapture بدقة.
      List<dynamic> legalMoves = [];

      try {
        legalMoves = game.moves(
          <String, dynamic>{'verbose': true},
        );
      } catch (_) {
        legalMoves = [];
      }

      final cleanToken = token
          .replaceAll('+', '')
          .replaceAll('#', '')
          .replaceAll('!', '')
          .replaceAll('?', '');

      dynamic matched;

      for (final item in legalMoves) {
        final san =
            _readField(item, 'san') ?? '';

        final cleanSan = san
            .replaceAll('+', '')
            .replaceAll('#', '')
            .replaceAll('!', '')
            .replaceAll('?', '');

        if (cleanSan == cleanToken) {
          matched = item;
          break;
        }
      }

      String from;
      String to;
      String? promotion;
      bool isCapture;
      String sanFinal;

      if (matched != null) {
        from = _readField(matched, 'from') ?? '';
        to = _readField(matched, 'to') ?? '';

        promotion =
            matched is Map
                ? matched['promotion']?.toString()
                : null;

        isCapture = _readCapture(matched);

        sanFinal =
            _readField(matched, 'san') ?? token;

        final args = <String, dynamic>{
          'from': from,
          'to': to,
        };

        if (promotion != null &&
            promotion.isNotEmpty) {
          args['promotion'] = promotion;
        }

        final ok = game.move(args);

        if (ok == false) {
          // فشل غير متوقع رغم المطابقة: نتوقف بأمان.
          return plies.isEmpty ? null : plies;
        }
      } else {
        // fallback: نجرّب السماحية المدمجة في الحزمة نفسها.
        final ok = game.move(token);

        if (ok == false) {
          // لا يمكن تفسير هذه النقلة، نوقف التفكيك هنا
          // ونعيد ما تم تجميعه حتى الآن بدل فشل كل شيء.
          return plies.isEmpty ? null : plies;
        }

        String fallbackSan = token;
        String fallbackFrom = '';
        String fallbackTo = '';
        bool fallbackCapture = false;

        try {
          final hist = game.getHistory(
            <String, dynamic>{'verbose': true},
          );

          if (hist.isNotEmpty) {
            final last = hist.last;

            fallbackFrom =
                _readField(last, 'from') ?? '';

            fallbackTo =
                _readField(last, 'to') ?? '';

            fallbackSan =
                _readField(last, 'san') ?? token;

            fallbackCapture =
                _readCapture(last);
          }
        } catch (_) {}

        from = fallbackFrom;
        to = fallbackTo;
        promotion = null;
        isCapture = fallbackCapture;
        sanFinal = fallbackSan;
      }

      final fenAfter = game.fen;

      plies.add(
        PgnPly(
          number: plies.length,
          color: turn == 'w' ? 'w' : 'b',
          san: sanFinal,
          from: from,
          to: to,
          promotion: promotion,
          isCapture: isCapture,
          fenBefore: fenBefore,
          fenAfter: fenAfter,
        ),
      );
    }

    return plies;
  } catch (_) {
    return null;
  }
}
