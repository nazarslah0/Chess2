import 'package:flutter/material.dart';
import 'models.dart';

/// Draws a real chess-piece silhouette (not a text glyph) for one square.
class PiecePainter extends CustomPainter {
  final String type; // K,Q,R,B,N,P (uppercase)
  final String color; // 'w' or 'b'
  final PieceTheme theme;
  PiecePainter(this.type, this.color, this.theme);

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = color == 'w' ? theme.whiteFill : theme.blackFill;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.045
      ..strokeJoin = StrokeJoin.round
      ..color = color == 'w' ? theme.whiteStroke : theme.blackStroke;

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    final s = size.width; // unit scale

    void drawPath(Path p) {
      canvas.drawPath(p, fill);
      canvas.drawPath(p, stroke);
    }

    switch (type) {
      case 'P':
        drawPath(_pawnPath(s));
        break;
      case 'R':
        drawPath(_rookPath(s));
        break;
      case 'N':
        drawPath(_knightPath(s));
        break;
      case 'B':
        drawPath(_bishopPath(s));
        break;
      case 'Q':
        drawPath(_queenPath(s));
        break;
      case 'K':
        drawPath(_kingPath(s));
        break;
    }
    canvas.restore();
  }

  Path _base(double s) {
    // shared trapezoid base used by most pieces
    final p = Path();
    p.moveTo(-0.30 * s, 0.36 * s);
    p.lineTo(0.30 * s, 0.36 * s);
    p.lineTo(0.24 * s, 0.28 * s);
    p.lineTo(-0.24 * s, 0.28 * s);
    p.close();
    return p;
  }

  Path _pawnPath(double s) {
    final p = Path()
      ..addOval(Rect.fromCircle(center: Offset(0, -0.16 * s), radius: 0.13 * s));
    p.addPath(_neckToBase(s, -0.06, 0.20, 0.13, 0.30), Offset.zero);
    p.addPath(_base(s), Offset.zero);
    return p;
  }

  Path _neckToBase(double s, double topY, double botY, double topHalf, double botHalf) {
    final p = Path();
    p.moveTo(-topHalf * s, topY * s);
    p.quadraticBezierTo(-botHalf * s, (topY + botY) / 2 * s, -botHalf * s, botY * s);
    p.lineTo(botHalf * s, botY * s);
    p.quadraticBezierTo(botHalf * s, (topY + botY) / 2 * s, topHalf * s, topY * s);
    p.close();
    return p;
  }

  Path _rookPath(double s) {
    final p = Path();
    p.moveTo(-0.26 * s, -0.34 * s);
    p.lineTo(-0.26 * s, -0.22 * s);
    p.lineTo(-0.15 * s, -0.22 * s);
    p.lineTo(-0.15 * s, -0.30 * s);
    p.lineTo(-0.05 * s, -0.30 * s);
    p.lineTo(-0.05 * s, -0.22 * s);
    p.lineTo(0.05 * s, -0.22 * s);
    p.lineTo(0.05 * s, -0.30 * s);
    p.lineTo(0.15 * s, -0.30 * s);
    p.lineTo(0.15 * s, -0.22 * s);
    p.lineTo(0.26 * s, -0.22 * s);
    p.lineTo(0.26 * s, -0.34 * s);
    p.lineTo(0.26 * s, -0.10 * s);
    p.lineTo(0.18 * s, -0.02 * s);
    p.lineTo(0.18 * s, 0.20 * s);
    p.lineTo(-0.18 * s, 0.20 * s);
    p.lineTo(-0.18 * s, -0.02 * s);
    p.lineTo(-0.26 * s, -0.10 * s);
    p.close();
    p.addPath(_base(s), Offset.zero);
    return p;
  }

  Path _bishopPath(double s) {
    final p = Path();
    p.addOval(Rect.fromCenter(center: Offset(0, -0.28 * s), width: 0.10 * s, height: 0.10 * s));
    p.moveTo(0, -0.22 * s);
    p.quadraticBezierTo(0.22 * s, -0.05 * s, 0.16 * s, 0.14 * s);
    p.lineTo(-0.16 * s, 0.14 * s);
    p.quadraticBezierTo(-0.22 * s, -0.05 * s, 0, -0.22 * s);
    p.close();
    // mitre slit
    p.moveTo(-0.03 * s, -0.14 * s);
    p.lineTo(0.03 * s, -0.02 * s);
    p.moveTo(0.03 * s, -0.14 * s);
    p.lineTo(-0.03 * s, -0.02 * s);
    p.addPath(_neckToBase(s, 0.14, 0.28, 0.18, 0.26), Offset.zero);
    p.addPath(_base(s), Offset.zero);
    return p;
  }

  Path _knightPath(double s) {
    final p = Path();
    p.moveTo(-0.20 * s, 0.20 * s);
    p.lineTo(-0.20 * s, -0.02 * s);
    p.quadraticBezierTo(-0.22 * s, -0.20 * s, -0.06 * s, -0.30 * s);
    p.quadraticBezierTo(0.04 * s, -0.36 * s, 0.14 * s, -0.30 * s);
    p.quadraticBezierTo(0.20 * s, -0.26 * s, 0.14 * s, -0.20 * s);
    p.quadraticBezierTo(0.08 * s, -0.22 * s, 0.06 * s, -0.16 * s);
    p.quadraticBezierTo(0.20 * s, -0.12 * s, 0.24 * s, 0.02 * s);
    p.quadraticBezierTo(0.26 * s, 0.10 * s, 0.20 * s, 0.20 * s);
    p.close();
    p.addPath(_base(s), Offset.zero);
    // eye + nostril accents
    return p;
  }

  Path _queenPath(double s) {
    final p = Path();
    const pts = [-0.24, -0.14, -0.04, 0.06, 0.16, 0.24];
    p.moveTo(-0.24 * s, -0.04 * s);
    for (int i = 0; i < pts.length; i++) {
      final x = pts[i] * s;
      final topY = (i.isOdd ? -0.34 : -0.24) * s;
      p.lineTo(x, topY);
      p.addOval(Rect.fromCircle(center: Offset(x, topY - 0.02 * s), radius: 0.03 * s));
    }
    p.lineTo(0.24 * s, -0.04 * s);
    p.addPath(_neckToBase(s, -0.02, 0.20, 0.22, 0.27), Offset.zero);
    p.addPath(_base(s), Offset.zero);
    return p;
  }

  Path _kingPath(double s) {
    final p = Path();
    // cross on top
    p.addRect(Rect.fromCenter(center: Offset(0, -0.40 * s), width: 0.05 * s, height: 0.13 * s));
    p.addRect(Rect.fromCenter(center: Offset(0, -0.37 * s), width: 0.13 * s, height: 0.05 * s));
    p.moveTo(-0.20 * s, -0.28 * s);
    p.lineTo(0.20 * s, -0.28 * s);
    p.lineTo(0.18 * s, -0.08 * s);
    p.quadraticBezierTo(0.24 * s, 0.02 * s, 0.20 * s, 0.14 * s);
    p.lineTo(-0.20 * s, 0.14 * s);
    p.quadraticBezierTo(-0.24 * s, 0.02 * s, -0.18 * s, -0.08 * s);
    p.close();
    p.addPath(_base(s), Offset.zero);
    return p;
  }

  @override
  bool shouldRepaint(covariant PiecePainter oldDelegate) =>
      oldDelegate.type != type || oldDelegate.color != color || oldDelegate.theme != theme;
}
