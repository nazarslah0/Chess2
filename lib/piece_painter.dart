import 'package:flutter/material.dart';

import 'models.dart';

/// رسم احتياطي للقطعة بالرموز (Unicode) عندما لا تتوفر صورة PNG
/// للثيم، أو تفشل صورة الأصول في التحميل.
///
/// [type] حرف القطعة: K Q R B N P
/// [color] حرف اللون: w أو b
class PiecePainter extends CustomPainter {
  final String type;
  final String color;
  final PieceTheme theme;

  const PiecePainter(
    this.type,
    this.color,
    this.theme,
  );

  static const Map<String, String> _glyphs = <String, String>{
    'K': '\u265A',
    'Q': '\u265B',
    'R': '\u265C',
    'B': '\u265D',
    'N': '\u265E',
    'P': '\u265F',
  };

  @override
  void paint(Canvas canvas, Size size) {
    final glyph = _glyphs[type.toUpperCase()];

    if (glyph == null) {
      return;
    }

    final isWhite = color == 'w';

    final fill = isWhite ? theme.whiteFill : theme.blackFill;
    final stroke = isWhite ? theme.whiteStroke : theme.blackStroke;

    final side = size.shortestSide;
    final fontSize = side * 0.86;

    final strokePainter = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: glyph,
        style: TextStyle(
          fontSize: fontSize,
          height: 1,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = side * 0.045
            ..strokeJoin = StrokeJoin.round
            ..color = stroke,
        ),
      ),
    )..layout();

    final fillPainter = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: glyph,
        style: TextStyle(
          fontSize: fontSize,
          height: 1,
          color: fill,
        ),
      ),
    )..layout();

    final offset = Offset(
      (size.width - fillPainter.width) / 2,
      (size.height - fillPainter.height) / 2,
    );

    strokePainter.paint(canvas, offset);
    fillPainter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant PiecePainter oldDelegate) {
    return oldDelegate.type != type ||
        oldDelegate.color != color ||
        oldDelegate.theme != theme;
  }
}
