import 'package:chess/chess.dart' as ch;

/// نقلة واحدة (ply) من مباراة PGN مع الوضعية قبلها وبعدها.
class PgnPly {
  /// النقلة بصيغة SAN (مثل Nf3 أو exd5 أو e8=Q+).
  final String san;

  /// لون اللاعب الذي نفّذ النقلة: 'w' أو 'b'.
  final String color;

  /// مربع الانطلاق والوصول (مثل e2 / e4).
  final String from;
  final String to;

  /// حرف الترقية بحرف صغير (q/r/b/n) أو null.
  final String? promotion;

  final String fenBefore;
  final String fenAfter;

  final bool isCapture;

  const PgnPly({
    required this.san,
    required this.color,
    required this.from,
    required this.to,
    required this.fenBefore,
    required this.fenAfter,
    this.promotion,
    this.isCapture = false,
  });
}

final RegExp _headerRe = RegExp(r'\[\s*(\w+)\s+"((?:[^"\\]|\\.)*)"\s*\]');

/// يستخرج ترويسات PGN مثل White / Black / Result / Event.
Map<String, String> extractPgnHeaders(String pgn) {
  final headers = <String, String>{};

  for (final m in _headerRe.allMatches(pgn)) {
    final key = m.group(1)!;
    final value = (m.group(2) ?? '').replaceAll(r'\"', '"').replaceAll(r'\\', r'\');
    headers[key] = value;
  }

  return headers;
}

/// يعيد نص النقلات فقط بعد حذف الترويسات والتعليقات والتفرعات
/// وعلامات NAG ورقم النقلة ونتيجة المباراة.
List<String> _tokenizeMoves(String pgn) {
  var text = pgn.replaceAll('\r', '\n');

  // الترويسات.
  text = text.replaceAll(_headerRe, ' ');

  // تعليقات { ... } (قد تحتوي [%clk ...]).
  text = text.replaceAll(RegExp(r'\{[^}]*\}', dotAll: true), ' ');

  // تعليقات ; حتى نهاية السطر.
  text = text.replaceAll(RegExp(r';[^\n]*'), ' ');

  // تفرعات ( ... ) — قد تكون متداخلة، نكرر الحذف.
  final variation = RegExp(r'\([^()]*\)');
  while (variation.hasMatch(text)) {
    text = text.replaceAll(variation, ' ');
  }

  // NAG مثل $1 $14.
  text = text.replaceAll(RegExp(r'\$\d+'), ' ');

  // أرقام النقلات: 1. و 1... و 12.
  text = text.replaceAll(RegExp(r'\d+\s*\.(\.\.)?'), ' ');

  final tokens = <String>[];

  for (final raw in text.split(RegExp(r'\s+'))) {
    final t = raw.trim();

    if (t.isEmpty) continue;

    // نتيجة المباراة.
    if (t == '1-0' || t == '0-1' || t == '1/2-1/2' || t == '*') {
      continue;
    }

    tokens.add(t);
  }

  return tokens;
}

String _normalizeSan(String san) {
  return san
      .replaceAll('0-0-0', 'O-O-O')
      .replaceAll('0-0', 'O-O')
      .replaceAll(RegExp(r'[+#!?]'), '')
      .replaceAll('e.p.', '')
      .trim();
}

String? _field(dynamic item, String key) {
  try {
    if (item is Map) {
      return item[key]?.toString();
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
        return null;
      case 'promotion':
        return d.promotion?.toString();
      case 'flags':
        return d.flags?.toString();
      case 'captured':
        return d.captured?.toString();
    }
  } catch (_) {}

  return null;
}

/// يحوّل نص PGN إلى قائمة نقلات. يعيد null إذا فشلت القراءة أو
/// وُجدت نقلة غير قانونية.
List<PgnPly>? parsePgnMoves(String pgn) {
  try {
    final headers = extractPgnHeaders(pgn);
    final game = ch.Chess();

    final startFen = headers['FEN'];

    if (startFen != null &&
        startFen.trim().isNotEmpty &&
        headers['SetUp'] != '0') {
      final loaded = game.load(startFen.trim());

      if (loaded == false) {
        return null;
      }
    }

    final tokens = _tokenizeMoves(pgn);

    if (tokens.isEmpty) {
      return null;
    }

    final plies = <PgnPly>[];

    for (final token in tokens) {
      final wanted = _normalizeSan(token);

      if (wanted.isEmpty) continue;

      final fenBefore = game.fen;
      final color = game.turn == ch.Color.WHITE ? 'w' : 'b';

      final legal = game.moves(<String, dynamic>{'verbose': true});

      dynamic match;

      for (final item in legal) {
        String? san;

        if (item is Map) {
          san = item['san']?.toString();
        } else {
          try {
            san = game.move_to_san(item);
          } catch (_) {}
        }

        if (san != null && _normalizeSan(san) == wanted) {
          match = item;
          break;
        }
      }

      if (match == null) {
        return null;
      }

      final from = _field(match, 'from');
      final to = _field(match, 'to');

      if (from == null || to == null) {
        return null;
      }

      var promotion = _field(match, 'promotion');

      if (promotion != null && promotion.isEmpty) {
        promotion = null;
      }

      promotion = promotion?.toLowerCase();

      final flags = _field(match, 'flags') ?? '';
      final captured = _field(match, 'captured');

      final isCapture = (captured != null && captured.isNotEmpty) ||
          flags.contains('c') ||
          flags.contains('e');

      final args = <String, String>{
        'from': from,
        'to': to,
      };

      if (promotion != null) {
        args['promotion'] = promotion;
      }

      final result = game.move(args);

      if (result == false) {
        return null;
      }

      var san = token.replaceAll(RegExp(r'[!?]'), '');

      if (san.contains('0-0')) {
        san = san.replaceAll('0-0-0', 'O-O-O').replaceAll('0-0', 'O-O');
      }

      plies.add(
        PgnPly(
          san: san,
          color: color,
          from: from,
          to: to,
          promotion: promotion,
          fenBefore: fenBefore,
          fenAfter: game.fen,
          isCapture: isCapture,
        ),
      );
    }

    return plies;
  } catch (_) {
    return null;
  }
}
