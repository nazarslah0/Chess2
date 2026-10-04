import 'package:shared_preferences/shared_preferences.dart';

/// حفظ حساب Chess.com الذي اختاره المستخدم حتى لا يضطر لإعادة
/// كتابة اسم المستخدم عند كل فتح للشاشة.
class AccountStorage {
  static const _chessComUsernameKey = 'chesscom_saved_username';

  static Future<String?> getChessComUsername() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_chessComUsernameKey)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  static Future<void> saveChessComUsername(String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_chessComUsernameKey, username.trim());
  }
}
