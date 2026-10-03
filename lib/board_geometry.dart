/// هندسة الرقعة: تحويل اسم المربع إلى خانة (عمود، صف) على الشاشة.
/// دالة نقية بلا اعتماد على Flutter، فتُختبر مباشرة، وتستعملها
/// الأسهم وعلامات الجودة لضمان اتجاه واحد صحيح.
///
/// col = 0 هو أقصى اليسار، row = 0 هو أعلى الرقعة.
///
/// - الأبيض في الأسفل: a1 → (0, 7)، h8 → (7, 0).
/// - الأسود في الأسفل (flipped): a1 → (7, 0)، h8 → (0, 7).
({int col, int row})? squareToGrid(
  String? square, {
  bool flipped = false,
}) {
  if (square == null || square.length != 2) return null;

  final file = square.codeUnitAt(0) - 'a'.codeUnitAt(0);
  final rank = square.codeUnitAt(1) - '1'.codeUnitAt(0);

  if (file < 0 || file > 7 || rank < 0 || rank > 7) return null;

  return (
    col: flipped ? 7 - file : file,
    row: flipped ? rank : 7 - rank,
  );
}
