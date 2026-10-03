import 'package:flutter/material.dart';

import 'models.dart';
import 'piece_painter.dart';

/// ============================================================
/// PV line (جاهز للعرض)
/// ============================================================

class PvLineDisplay {
  final int depth;
  final String evalLabel;

  /// نقلات SAN (حتى 8 نقلات).
  final List<String> moves;

  /// أول نقلة بصيغة مربعين (للسهم على الرقعة).
  final String bestFrom;
  final String bestTo;

  const PvLineDisplay({
    required this.depth,
    required this.evalLabel,
    required this.moves,
    required this.bestFrom,
    required this.bestTo,
  });
}

Widget _pieceImage(PieceTheme theme, String piece, double size) {
  final color = piece.substring(0, 1);
  final type = piece.substring(1, 2);

  final fallback = SizedBox(
    width: size,
    height: size,
    child: CustomPaint(
      painter: PiecePainter(type, color, theme),
    ),
  );

  if (theme.assetFolder == null) {
    return fallback;
  }

  return Image.asset(
    theme.assetPath(color, type),
    width: size,
    height: size,
    fit: BoxFit.contain,
    errorBuilder: (context, error, stackTrace) => fallback,
  );
}

/// ============================================================
/// Setup panel — اختيار القطع، الدور، حقوق التبييت
/// ============================================================

class SetupPanel extends StatelessWidget {
  final GameState state;
  final PieceTheme pieceTheme;
  final String? selectedPiece;
  final bool eraseMode;

  final void Function(String piece) onSelectPiece;
  final VoidCallback onToggleErase;
  final VoidCallback onChanged;

  const SetupPanel({
    super.key,
    required this.state,
    required this.pieceTheme,
    required this.selectedPiece,
    required this.eraseMode,
    required this.onSelectPiece,
    required this.onToggleErase,
    required this.onChanged,
  });

  static const List<String> _types = <String>['K', 'Q', 'R', 'B', 'N', 'P'];

  Widget _paletteRow(BuildContext context, String color) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final type in _types)
          Builder(
            builder: (context) {
              final piece = '$color$type';
              final selected = selectedPiece == piece && !eraseMode;

              return InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => onSelectPiece(piece),
                child: Container(
                  width: 46,
                  height: 46,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: selected
                        ? scheme.primary.withValues(alpha: 0.18)
                        : Colors.transparent,
                    border: Border.all(
                      color: selected ? scheme.primary : Colors.grey.shade400,
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child: _pieceImage(pieceTheme, piece, 38),
                ),
              );
            },
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'إعداد الوضعية',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              eraseMode
                  ? 'وضع المسح: اضغط على مربع لإزالة القطعة.'
                  : 'اختر قطعة ثم اضغط على المربع لوضعها.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
            const SizedBox(height: 10),
            _paletteRow(context, 'w'),
            const SizedBox(height: 8),
            _paletteRow(context, 'b'),
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilterChip(
                selected: eraseMode,
                avatar: const Icon(Icons.backspace_outlined, size: 18),
                label: const Text('ممحاة'),
                onSelected: (_) => onToggleErase(),
              ),
            ),
            const Divider(height: 24),
            const Text(
              'الدور',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('دور الأبيض'),
                  selected: state.setupTurn == 'w',
                  onSelected: (_) {
                    state.setupTurn = 'w';
                    state.refresh();
                    onChanged();
                  },
                ),
                ChoiceChip(
                  label: const Text('دور الأسود'),
                  selected: state.setupTurn == 'b',
                  onSelected: (_) {
                    state.setupTurn = 'b';
                    state.refresh();
                    onChanged();
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'حقوق التبييت',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _castleChip('O-O أبيض', state.ck, (v) => state.ck = v),
                _castleChip('O-O-O أبيض', state.cq, (v) => state.cq = v),
                _castleChip('O-O أسود', state.ckb, (v) => state.ckb = v),
                _castleChip('O-O-O أسود', state.cqb, (v) => state.cqb = v),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  state.legal
                      ? Icons.check_circle_rounded
                      : Icons.error_rounded,
                  size: 18,
                  color: state.legal ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    state.legalMessage,
                    style: TextStyle(
                      color: state.legal ? Colors.green : Colors.red,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _castleChip(
    String label,
    bool value,
    void Function(bool v) setter,
  ) {
    return FilterChip(
      label: Text(label),
      selected: value,
      onSelected: (v) {
        setter(v);
        state.refresh();
        onChanged();
      },
    );
  }
}

/// ============================================================
/// Analysis panel — حالة المحرك، العمق، عدد الخطوط، نتائج PV
/// ============================================================

class AnalysisPanel extends StatelessWidget {
  final String engineStatus;
  final bool engineReady;
  final bool analyzing;

  final int multiPv;

  final Map<int, PvLineDisplay> lines;

  final VoidCallback onAnalyze;
  final VoidCallback onStop;

  final void Function(int value) onMultiPvChanged;
  final void Function(int index) onSelectLine;

  const AnalysisPanel({
    super.key,
    required this.engineStatus,
    required this.engineReady,
    required this.analyzing,
    required this.multiPv,
    required this.lines,
    required this.onAnalyze,
    required this.onStop,
    required this.onMultiPvChanged,
    required this.onSelectLine,
  });

  @override
  Widget build(BuildContext context) {
    final keys = lines.keys.toList()..sort();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // لا نعرض نص حالة المحرك إلا عند الخطأ.
            if (engineStatus.startsWith('🔴')) ...[
              Text(
                engineStatus,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
              const SizedBox(height: 10),
            ],
            Row(
              children: [
                SizedBox(
                  width: 92,
                  child: Text('الخطوط: $multiPv'),
                ),
                Expanded(
                  child: Slider(
                    min: 1,
                    max: 5,
                    divisions: 4,
                    value: multiPv.clamp(1, 5).toDouble(),
                    label: '$multiPv',
                    onChanged: analyzing
                        ? null
                        : (v) => onMultiPvChanged(v.round()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: engineReady && !analyzing ? onAnalyze : null,
                    icon: const Icon(Icons.analytics_rounded),
                    label: const Text('تحليل الوضعية'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: analyzing ? onStop : null,
                  icon: const Icon(Icons.stop_rounded),
                  label: const Text('إيقاف'),
                ),
              ],
            ),
            if (analyzing) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator(),
            ],
            if (keys.isNotEmpty) const SizedBox(height: 10),
            for (final k in keys) _lineTile(context, k, lines[k]!),
          ],
        ),
      ),
    );
  }

  Widget _lineTile(BuildContext context, int index, PvLineDisplay line) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => onSelectLine(index),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade400),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  line.evalLabel,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  textDirection: TextDirection.ltr,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      line.moves.join('  '),
                      textDirection: TextDirection.ltr,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'خط $index • عمق ${line.depth}',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ============================================================
/// Move list panel — سجل النقلات
/// ============================================================

class MoveListPanel extends StatelessWidget {
  final List<MoveEntry> history;

  const MoveListPanel({
    super.key,
    required this.history,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'سجل النقلات',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (history.isEmpty)
              Text(
                'لا توجد نقلات بعد.',
                style: TextStyle(color: Colors.grey.shade600),
              )
            else
              Wrap(
                spacing: 10,
                runSpacing: 6,
                textDirection: TextDirection.ltr,
                children: [
                  for (var i = 0; i < history.length; i++)
                    Text(
                      history[i].color == 'w'
                          ? '${(i ~/ 2) + 1}. ${history[i].san}'
                          : (i == 0
                              ? '1... ${history[i].san}'
                              : history[i].san),
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
