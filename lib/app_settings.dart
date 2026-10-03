import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// إعدادات التطبيق العامة. أي شاشة فيها رقعة (تحليل وضعية، تحليل
/// مباراة، اللعب ضد Maia، التمارين...) تقرأ الثيمات من هنا، فتغييرها
/// في الإعدادات ينعكس على كل الرقع.
class AppSettings extends ChangeNotifier {
  AppSettings._();

  static final AppSettings instance = AppSettings._();

  /// الثيمات المتاحة: مظهر Chess.com أولًا (الافتراضي)، ثم بقية
  /// الثيمات.
  static final List<BoardTheme> allBoardThemes = <BoardTheme>[
    chessComBoardTheme,
    ...boardThemes,
  ];

  static final List<PieceTheme> allPieceThemes = <PieceTheme>[
    chessComPieceTheme,
    ...pieceThemes,
  ];

  static const String _kBoard = 'chess2_board_theme';
  static const String _kPiece = 'chess2_piece_theme';
  static const String _kMaia = 'chess2_maia_bucket';
  static const String _kName = 'chess2_player_name';

  int _boardIdx = 0;
  int _pieceIdx = 0;
  int _maiaBucket = 1500;
  String _playerName = '';

  int get boardThemeIndex => _boardIdx;
  int get pieceThemeIndex => _pieceIdx;

  BoardTheme get boardTheme => allBoardThemes[_boardIdx];
  PieceTheme get pieceTheme => allPieceThemes[_pieceIdx];

  /// مستوى Maia الافتراضي (1100 / 1500 / 1900).
  int get maiaBucket => _maiaBucket;

  /// اسم المستخدم في المباريات (Chess.com / Lichess)، لمعرفة أي
  /// لاعب هو أنت عند استخراج التمارين وتقييم الأداء.
  String get playerName => _playerName;

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();

      final b = p.getInt(_kBoard) ?? 0;
      final pc = p.getInt(_kPiece) ?? 0;

      _boardIdx = (b >= 0 && b < allBoardThemes.length) ? b : 0;
      _pieceIdx = (pc >= 0 && pc < allPieceThemes.length) ? pc : 0;
      _maiaBucket = p.getInt(_kMaia) ?? 1500;
      _playerName = p.getString(_kName) ?? '';

      notifyListeners();
    } catch (_) {}
  }

  Future<void> setBoardTheme(int i) async {
    if (i < 0 || i >= allBoardThemes.length) return;

    _boardIdx = i;
    notifyListeners();

    try {
      (await SharedPreferences.getInstance()).setInt(_kBoard, i);
    } catch (_) {}
  }

  Future<void> setPieceTheme(int i) async {
    if (i < 0 || i >= allPieceThemes.length) return;

    _pieceIdx = i;
    notifyListeners();

    try {
      (await SharedPreferences.getInstance()).setInt(_kPiece, i);
    } catch (_) {}
  }

  Future<void> setMaiaBucket(int b) async {
    _maiaBucket = b;
    notifyListeners();

    try {
      (await SharedPreferences.getInstance()).setInt(_kMaia, b);
    } catch (_) {}
  }

  Future<void> setPlayerName(String name) async {
    _playerName = name.trim();
    notifyListeners();

    try {
      (await SharedPreferences.getInstance())
          .setString(_kName, _playerName);
    } catch (_) {}
  }

  /// هل [name] (من ترويسة PGN) هو اسم المستخدم؟
  bool isMe(String? name) =>
      _playerName.isNotEmpty &&
      name != null &&
      name.trim().toLowerCase() == _playerName.toLowerCase();
}
