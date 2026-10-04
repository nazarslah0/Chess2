import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// خطأ مفهوم للمستخدم عند التعامل مع Lichess.
class LichessException implements Exception {
  final String message;

  const LichessException(this.message);

  @override
  String toString() => message;
}

/// مباراة واحدة من Lichess.
class LichessGame {
  final String pgn;
  final String whiteUsername;
  final String blackUsername;

  /// '1-0' أو '0-1' أو '1/2-1/2'.
  final String result;

  final String timeClass;
  final DateTime? endTime;

  const LichessGame({
    required this.pgn,
    required this.whiteUsername,
    required this.blackUsername,
    required this.result,
    this.timeClass = '',
    this.endTime,
  });

  bool _isWhite(String username) =>
      whiteUsername.toLowerCase() == username.trim().toLowerCase();

  String opponentOf(String username) =>
      _isWhite(username) ? blackUsername : whiteUsername;

  /// 'win' أو 'draw' أو 'loss' بالنسبة للاعب [username].
  String outcomeFor(String username) {
    if (result == '1/2-1/2') {
      return 'draw';
    }

    final whiteWon = result == '1-0';
    final blackWon = result == '0-1';

    if (_isWhite(username)) {
      return whiteWon ? 'win' : 'loss';
    }

    return blackWon ? 'win' : 'loss';
  }
}

class LichessService {
  static const String _base = 'https://lichess.org/api';

  static const Duration _timeout = Duration(seconds: 25);

  Future<http.Response> _get(
    String url, {
    String accept = 'application/json',
  }) async {
    try {
      return await http.get(
        Uri.parse(url),
        headers: <String, String>{
          'Accept': accept,
          'User-Agent': 'ChessAnalyzer/1.0 (Flutter)',
        },
      ).timeout(_timeout);
    } on TimeoutException {
      throw const LichessException(
        'انتهت مهلة الاتصال بـ Lichess. حاول مرة أخرى.',
      );
    } catch (_) {
      throw const LichessException(
        'تعذر الاتصال بـ Lichess. تحقق من الإنترنت.',
      );
    }
  }

  /// يتأكد أن الحساب موجود على Lichess.
  Future<void> verifyUsername(String username) async {
    final u = Uri.encodeComponent(username.trim());
    final res = await _get('$_base/user/$u');

    if (res.statusCode == 404) {
      throw const LichessException('اسم المستخدم غير موجود على Lichess.');
    }

    if (res.statusCode == 429) {
      throw const LichessException(
        'عدد الطلبات كبير على Lichess. انتظر قليلًا ثم أعد المحاولة.',
      );
    }

    if (res.statusCode != 200) {
      throw LichessException(
        'تعذر التحقق من الحساب (رمز ${res.statusCode}).',
      );
    }
  }

  /// يجلب أحدث [limit] مباراة (الأحدث أولًا).
  Future<List<LichessGame>> fetchRecentGames(
    String username, {
    int limit = 10,
  }) async {
    final u = Uri.encodeComponent(username.trim());

    final url = '$_base/games/user/$u'
        '?max=$limit&pgnInJson=true&clocks=false&evals=false&opening=false';

    final res = await _get(url, accept: 'application/x-ndjson');

    if (res.statusCode == 404) {
      throw const LichessException('اسم المستخدم غير موجود على Lichess.');
    }

    if (res.statusCode == 429) {
      throw const LichessException(
        'عدد الطلبات كبير على Lichess. انتظر قليلًا ثم أعد المحاولة.',
      );
    }

    if (res.statusCode != 200) {
      throw LichessException(
        'تعذر جلب المباريات (رمز ${res.statusCode}).',
      );
    }

    final games = <LichessGame>[];

    for (final line in const LineSplitter().convert(utf8.decode(res.bodyBytes))) {
      final trimmed = line.trim();

      if (trimmed.isEmpty) continue;

      try {
        final game = _parseGame(jsonDecode(trimmed));

        if (game != null) {
          games.add(game);
        }
      } catch (_) {
        // نتجاوز أي سطر تالف.
      }
    }

    return games;
  }

  String _playerName(dynamic player) {
    if (player is! Map) return '?';

    final user = player['user'];

    if (user is Map && user['name'] != null) {
      return user['name'].toString();
    }

    if (player['aiLevel'] != null) {
      return 'Stockfish ${player['aiLevel']}';
    }

    return 'Anonymous';
  }

  LichessGame? _parseGame(dynamic raw) {
    if (raw is! Map) return null;

    final variant = raw['variant']?.toString() ?? 'standard';
    if (variant != 'standard') return null;

    final pgn = raw['pgn']?.toString() ?? '';
    if (pgn.trim().isEmpty) return null;

    final players = raw['players'];
    if (players is! Map) return null;

    final winner = raw['winner']?.toString();

    final result = winner == 'white'
        ? '1-0'
        : winner == 'black'
            ? '0-1'
            : '1/2-1/2';

    final endMs = raw['lastMoveAt'] ?? raw['createdAt'];

    return LichessGame(
      pgn: pgn,
      whiteUsername: _playerName(players['white']),
      blackUsername: _playerName(players['black']),
      result: result,
      timeClass: raw['speed']?.toString() ?? '',
      endTime: endMs is num
          ? DateTime.fromMillisecondsSinceEpoch(endMs.toInt())
          : null,
    );
  }
}
