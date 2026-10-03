import 'models.dart';

/// معالجة لمسات الرقعة (اختيار قطعة ثم وجهتها) بشكل مشترك بين
/// شاشات اللعب (ضد Maia، التمارين...).
class BoardInput {
  final GameState state;

  Set<String> targets = <String>{};

  /// آخر نقلة نُفِّذت عبر [tap] بصيغة UCI (مثل e7e8q)، أو null.
  String? lastUci;

  BoardInput(this.state);

  String _turn() {
    final parts = state.currentFen.split(' ');

    return parts.length > 1 ? parts[1] : 'w';
  }

  void clear() {
    targets = <String>{};
    state.tapSetupSelect(null);
  }

  /// يعالج لمسة على [square]. يعيد true إذا نُفِّذت نقلة.
  /// [side]: إن حُدِّد ('w' أو 'b') فلا يُسمح إلا بتحريك قطع هذا
  /// اللون وفي دوره.
  Future<bool> tap(
    String square,
    Future<String?> Function() askPromotion, {
    String? side,
  }) async {
    final turn = _turn();

    if (side != null && side != turn) {
      return false;
    }

    final board = GameState.parseBoard(
      state.currentFen.split(' ').first,
    );

    final selected = state.selectedSquare;

    // تنفيذ النقلة.
    if (selected != null && targets.contains(square)) {
      final moving = board[selected];

      final isPromotion = moving != null &&
          moving.length >= 2 &&
          moving.substring(1) == 'P' &&
          ((moving.startsWith('w') && square.endsWith('8')) ||
              (moving.startsWith('b') && square.endsWith('1')));

      targets = <String>{};

      String? promotion;

      if (isPromotion) {
        promotion = await askPromotion() ?? 'q';
      }

      final ok = state.tryMove(
        selected,
        square,
        promotion: promotion,
      );

      if (ok) lastUci = '$selected$square${promotion ?? ''}';

      return ok;
    }

    // إلغاء التحديد بلمس نفس المربع.
    if (selected == square) {
      clear();
      return false;
    }

    // اختيار قطعة جديدة.
    final piece = board[square];

    if (piece != null && piece.startsWith(turn)) {
      state.tapSetupSelect(square);
      targets = state.legalTargets(square).toSet();
    } else {
      clear();
    }

    return false;
  }
}
