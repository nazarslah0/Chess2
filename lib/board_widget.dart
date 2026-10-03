import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'models.dart';
import 'game_review_models.dart';
import 'piece_painter.dart';
import 'board_geometry.dart';

class BoardArrow {
  final String from;
  final String to;
  final Color color;

  const BoardArrow({
    required this.from,
    required this.to,
    this.color = Colors.blueAccent,
  });
}

/// علامة جودة تُرسم على الزاوية العلوية اليمنى للمربع [square]
/// (فوق القطعة المتحركة) — نجمة، !!، ؟، ؟؟ ... إلخ.
class BoardBadge {
  final String square;
  final MoveQuality quality;

  const BoardBadge({
    required this.square,
    required this.quality,
  });
}

class BoardWidget extends StatelessWidget {
  final GameState state;
  final BoardTheme boardTheme;
  final PieceTheme pieceTheme;

  final String? arrowFrom;
  final String? arrowTo;

  /// أسهم إضافية (تُستخدم في مراجعة المباريات لعرض النقلة
  /// المُلعَبة وأفضل نقلة بألوان مختلفة في آنٍ واحد).
  /// إن كانت غير فارغة تُرسم بدل arrowFrom/arrowTo.
  final List<BoardArrow> arrows;

  final Set<String> targets;

  /// علامات جودة النقلة فوق القطع (مراجعة المباراة فقط).
  final List<BoardBadge> badges;

  final bool showCoordinates;

  /// عند false: الرقعة للعرض فقط (بلا Drag & Drop)، تُستخدم
  /// في شاشات المراجعة/التحليل حيث التنقل بين النقلات لا
  /// يجب أن يختلط مع محاولة تحريك القطع.
  final bool interactive;

  final void Function(String square) onTap;

  const BoardWidget({
    super.key,
    required this.state,
    required this.boardTheme,
    required this.pieceTheme,
    required this.onTap,
    this.arrowFrom,
    this.arrowTo,
    this.arrows = const [],
    this.targets = const {},
    this.badges = const [],
    this.showCoordinates = true,
    this.interactive = true,
  });

  static const String files = 'abcdefgh';

  @override
  Widget build(BuildContext context) {
    final fen = state.currentFen;

    final fenParts = fen.split(' ');

    final boardFen =
        fenParts.isNotEmpty ? fenParts.first : '';

    final board = GameState.parseBoard(boardFen);

    final flipped = state.flipped;

    final effectiveArrows = arrows.isNotEmpty
        ? arrows
        : (_validSquare(arrowFrom) &&
                _validSquare(arrowTo) &&
                arrowFrom != arrowTo)
            ? [
                BoardArrow(
                  from: arrowFrom!,
                  to: arrowTo!,
                ),
              ]
            : const <BoardArrow>[];

    final turn =
        fenParts.length > 1 ? fenParts[1] : 'w';

    bool isKingInCheck(String square) {
      if (state.mode != 'play') {
        return false;
      }

      bool inCheck = false;

      try {
        inCheck = state.chess.in_check == true;
      } catch (_) {
        inCheck = false;
      }

      if (!inCheck) {
        return false;
      }

      return board[square] == '${turn}K';
    }

    bool isKingCheckmated(String square) {
      if (state.mode != 'play') {
        return false;
      }

      bool mated = false;

      try {
        mated = state.chess.in_checkmate == true;
      } catch (_) {
        mated = false;
      }

      if (!mated) {
        return false;
      }

      return board[square] == '${turn}K';
    }

    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = math.min(
            constraints.maxWidth,
            constraints.maxHeight,
          );

          final cell = size / 8;

          return Center(
            child: SizedBox(
              width: size,
              height: size,
              // الرقعة يجب أن تبقى LTR دائمًا حتى في الواجهة العربية،
              // وإلا ينعكس ترتيب الأعمدة في GridView بينما يُرسم السهم
              // بإحداثيات LTR، فيظهر السهم معكوسًا.
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Stack(
                children: [
                  // ==================================================
                  // الرقعة
                  // ==================================================

                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: boardTheme.border,
                        width: 2,
                      ),
                      borderRadius:
                          BorderRadius.circular(6),
                    ),
                    child: ClipRRect(
                      borderRadius:
                          BorderRadius.circular(4),
                      child: GridView.builder(
                        padding: EdgeInsets.zero,
                        physics:
                            const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 8,
                        ),
                        itemCount: 64,
                        itemBuilder:
                            (context, index) {
                          final col = index % 8;
                          final row = index ~/ 8;

                          // تحويل موضع Grid إلى مربع شطرنج.
                          final fileIndex =
                              flipped
                                  ? 7 - col
                                  : col;

                          final rankIndex =
                              flipped
                                  ? row
                                  : 7 - row;

                          final square =
                              files[fileIndex] +
                                  (rankIndex + 1)
                                      .toString();

                          final isDark =
                              (fileIndex +
                                      rankIndex) %
                                  2 !=
                              0;

                          final piece =
                              board[square];

                          final isLastMove =
                              square ==
                                      state.lastFrom ||
                                  square ==
                                      state.lastTo;

                          final isSelected =
                              square ==
                                  state.selectedSquare;

                          final isTarget =
                              targets.contains(square);

                          final isCheck =
                              isKingInCheck(square);

                          final isMated =
                              isKingCheckmated(square);

                          return DragTarget<String>(
                            onWillAcceptWithDetails:
                                (details) =>
                                    interactive &&
                                    state.mode ==
                                        'play',
                            onAcceptWithDetails:
                                (details) {
                              onTap(square);
                            },
                            builder: (
                              context,
                              candidateData,
                              rejectedData,
                            ) {
                              return GestureDetector(
                            behavior:
                                HitTestBehavior.opaque,
                            onTap: () =>
                                onTap(square),
                            child: Container(
                              color: isDark
                                  ? boardTheme.dark
                                  : boardTheme.light,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  // آخر نقلة
                                  if (isLastMove)
                                    Positioned.fill(
                                      child: Container(
                                        color: boardTheme
                                            .lastMove,
                                      ),
                                    ),

                                  // المربع المحدد
                                  if (isSelected)
                                    Positioned.fill(
                                      child: Container(
                                        color: boardTheme
                                            .selected,
                                      ),
                                    ),

                                  // الملك في كش
                                  if (isCheck && !isMated)
                                    Positioned.fill(
                                      child: Container(
                                        decoration:
                                            BoxDecoration(
                                          border:
                                              Border.all(
                                            color: boardTheme
                                                .checkColor,
                                            width: 3,
                                          ),
                                        ),
                                      ),
                                    ),

                                  // الملك في كش مات — توهج نابض
                                  if (isMated)
                                    const Positioned.fill(
                                      child: _CheckmateGlow(),
                                    ),

                                  // القطعة
                                  if (piece != null)
                                    Positioned.fill(
                                      child: Padding(
                                        padding:
                                            const EdgeInsets
                                                .all(3),
                                        child: interactive &&
                                                state
                                                        .mode ==
                                                    'play'
                                            ? Draggable<
                                                String>(
                                                data:
                                                    square,
                                                feedback:
                                                    SizedBox(
                                                  width:
                                                      cell,
                                                  height:
                                                      cell,
                                                  child: Opacity(
                                                    opacity:
                                                        0.85,
                                                    child:
                                                        _buildPiece(
                                                      piece,
                                                    ),
                                                  ),
                                                ),
                                                childWhenDragging:
                                                    Opacity(
                                                  opacity:
                                                      0.25,
                                                  child:
                                                      _buildPiece(
                                                    piece,
                                                  ),
                                                ),
                                                onDragStarted:
                                                    () =>
                                                        onTap(
                                                  square,
                                                ),
                                                child:
                                                    _buildPiece(
                                                  piece,
                                                ),
                                              )
                                            : _buildPiece(
                                                piece,
                                              ),
                                      ),
                                    ),

                                  // هدف النقلة
                                  if (isTarget)
                                    Center(
                                      child: Container(
                                        width: cell *
                                            0.18,
                                        height: cell *
                                            0.18,
                                        decoration:
                                            BoxDecoration(
                                          color: boardTheme
                                              .target,
                                          shape:
                                              BoxShape.circle,
                                        ),
                                      ),
                                    ),

                                  // أرقام الصفوف
                                  if (col == 0 &&
                                      showCoordinates)
                                    Positioned(
                                      top: 2,
                                      left: 3,
                                      child: Text(
                                        '${rankIndex + 1}',
                                        style:
                                            TextStyle(
                                          fontSize: 9,
                                          fontWeight:
                                              FontWeight
                                                  .bold,
                                          color: boardTheme
                                              .border
                                              .withValues(alpha: 
                                                  0.75),
                                        ),
                                      ),
                                    ),

                                  // أسماء الأعمدة
                                  if (row == 7 &&
                                      showCoordinates)
                                    Positioned(
                                      bottom: 1,
                                      right: 3,
                                      child: Text(
                                        files[fileIndex],
                                        style:
                                            TextStyle(
                                          fontSize: 9,
                                          fontWeight:
                                              FontWeight
                                                  .bold,
                                          color: boardTheme
                                              .border
                                              .withValues(alpha: 
                                                  0.75),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ),

                  // ==================================================
                  // الأسهم (أفضل نقلة / النقلة المُلعَبة...)
                  // ==================================================

                  for (final arrow in effectiveArrows)
                    if (_validSquare(arrow.from) &&
                        _validSquare(arrow.to) &&
                        arrow.from != arrow.to)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: _ArrowPainter(
                              from: arrow.from,
                              to: arrow.to,
                              flipped: flipped,
                              color: arrow.color,
                            ),
                          ),
                        ),
                      ),

                  // ==================================================
                  // علامات جودة النقلة (الزاوية العلوية اليمنى للقطعة)
                  // ==================================================

                  for (final badge in badges)
                    if (_validSquare(badge.square))
                      _badgePositioned(
                        badge: badge,
                        cell: cell,
                        size: size,
                        flipped: flipped,
                      ),
                ],
              ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _badgePositioned({
    required BoardBadge badge,
    required double cell,
    required double size,
    required bool flipped,
  }) {
    final grid = squareToGrid(badge.square, flipped: flipped);

    if (grid == null) return const SizedBox.shrink();

    final col = grid.col;
    final row = grid.row;

    final d = cell * 0.44;

    final left = ((col + 1) * cell - d * 0.80)
        .clamp(0.0, size - d)
        .toDouble();

    final top = (row * cell - d * 0.20)
        .clamp(0.0, size - d)
        .toDouble();

    return Positioned(
      left: left,
      top: top,
      width: d,
      height: d,
      child: IgnorePointer(
        child: QualityBadge(
          quality: badge.quality,
          size: d,
        ),
      ),
    );
  }

  Widget _buildPiece(String piece) {
    if (piece.length != 2) {
      return const SizedBox.shrink();
    }

    final color = piece.substring(0, 1);
    final type = piece.substring(1, 2);

    if (pieceTheme.assetFolder != null) {
      return Image.asset(
        pieceTheme.assetPath(
          color,
          type,
        ),
        fit: BoxFit.contain,
        errorBuilder:
            (context, error, stackTrace) {
          return CustomPaint(
            painter: PiecePainter(
              type,
              color,
              pieceTheme,
            ),
          );
        },
      );
    }

    return CustomPaint(
      painter: PiecePainter(
        type,
        color,
        pieceTheme,
      ),
    );
  }

  static bool _validSquare(String? square) {
    if (square == null ||
        square.length != 2) {
      return false;
    }

    final file =
        square.codeUnitAt(0);

    final rank =
        square.codeUnitAt(1);

    return file >= 97 &&
        file <= 104 &&
        rank >= 49 &&
        rank <= 56;
  }
}


// ============================================================
// رسم سهم أفضل نقلة
// ============================================================

class _ArrowPainter extends CustomPainter {
  final String from;
  final String to;
  final bool flipped;
  final Color color;

  const _ArrowPainter({
    required this.from,
    required this.to,
    required this.flipped,
    required this.color,
  });

  Offset _center(
    String square,
    double cell,
  ) {
    final g = squareToGrid(square, flipped: flipped);

    if (g == null) {
      return Offset.zero;
    }

    return Offset(
      g.col * cell + cell / 2,
      g.row * cell + cell / 2,
    );
  }

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    if (size.width <= 0 ||
        size.height <= 0) {
      return;
    }

    final cell = size.width / 8;

    final startCenter =
        _center(from, cell);

    final endCenter =
        _center(to, cell);

    final delta =
        endCenter - startCenter;

    final distance =
        delta.distance;

    if (distance < 1) {
      return;
    }

    final direction =
        delta / distance;

    // لا نجعل السهم يبدأ من مركز القطعة.
    final startPadding =
        cell * 0.22;

    // نترك مساحة قبل رأس السهم.
    final endPadding =
        cell * 0.28;

    final start =
        startCenter +
            direction *
                startPadding;

    final end =
        endCenter -
            direction *
                endPadding;

    // ==========================================================
    // جسم السهم
    // ==========================================================

    final shaftPaint = Paint()
      ..color =
          color.withValues(alpha: 0.82)
      ..strokeWidth =
          cell * 0.115
      ..strokeCap =
          StrokeCap.round
      ..style =
          PaintingStyle.stroke;

    canvas.drawLine(
      start,
      end,
      shaftPaint,
    );

    // ==========================================================
    // رأس السهم
    // ==========================================================

    final headLength =
        cell * 0.30;

    final headWidth =
        cell * 0.18;

    final tip =
        end +
            direction *
                (cell * 0.08);

    final perpendicular =
        Offset(
      -direction.dy,
      direction.dx,
    );

    final base =
        tip -
            direction *
                headLength;

    final left =
        base +
            perpendicular *
                headWidth;

    final right =
        base -
            perpendicular *
                headWidth;

    final path = Path()
      ..moveTo(
        tip.dx,
        tip.dy,
      )
      ..lineTo(
        left.dx,
        left.dy,
      )
      ..lineTo(
        right.dx,
        right.dy,
      )
      ..close();

    final headPaint = Paint()
      ..color =
          color.withValues(alpha: 0.92)
      ..style =
          PaintingStyle.fill;

    canvas.drawPath(
      path,
      headPaint,
    );
  }

  @override
  bool shouldRepaint(
    covariant _ArrowPainter oldDelegate,
  ) {
    return oldDelegate.from != from ||
        oldDelegate.to != to ||
        oldDelegate.flipped != flipped ||
        oldDelegate.color != color;
  }
}


// ============================================================
// توهج نابض على مربع الملك عند الكش مات
// ============================================================

class _CheckmateGlow extends StatefulWidget {
  const _CheckmateGlow();

  @override
  State<_CheckmateGlow> createState() =>
      _CheckmateGlowState();
}

class _CheckmateGlowState extends State<_CheckmateGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    )..repeat(reverse: true);

    _pulse = Tween<double>(
      begin: 0.35,
      end: 0.9,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        return Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: Colors.red
                  .withValues(alpha: _pulse.value),
              width: 3,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.red
                    .withValues(alpha: _pulse.value * 0.75),
                blurRadius: 14,
                spreadRadius: 2,
              ),
            ],
          ),
        );
      },
    );
  }
}
