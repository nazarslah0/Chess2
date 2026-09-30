import 'package:http/http.dart' as http;

import 'pgn_utils.dart';

/// معلومات مباراة واحدة من Lichess (PGN عام، بدون تسجيل دخول).
class LichessGame {
  final String pgn;
  final String whiteUsername;
  final String blackUsername;
  final String result; // '1-0' / '0-1' / '1/2-1/2' / '*'
  final String timeClass;
  final DateTime? endTime;

  const LichessGame({
    required this.pgn,
    required this.whiteUsername,
    required this.blackUsername,
    required this.result,
    required this.timeClass,
    required this.endTime,
  });

  String outcomeFor(String username) {
    final isWhite = whiteUsername.toLowerCase() ==
        username.toLowerCase();

    if (result == '1/2-1/2') {
      return 'draw';
    }

    final whiteWon = result == '1-0';

    if (isWhite) {
      return whiteWon ? 'win' : 'loss';
    }

    return whiteWon ? 'loss' : 'win';
  }

  String opponentOf(String username) {
    final isWhite = whiteUsername.toLowerCase() ==
        username.toLowerCase();

    return isWhite ? blackUsername : whiteUsername;
  }
}

class LichessException implements Exception {
  final String message;

  const LichessException(this.message);

  @override
  String toString() => message;
}

class LichessService {
  static const _userAgent =
      'ChessAnalyzerFlutterApp/1.0 '
      '(personal chess analysis app)';

  Future<void> verifyUsername(String username) async {
    final uri = Uri.parse(
      'https://lichess.org/api/user/'
      '${Uri.encodeComponent(username.trim())}',
    );

    late final http.Response res;

    try {
      res = await http
          .get(
            uri,
            headers: {'User-Agent': _userAgent},
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const LichessException(
        'تعذر الاتصال بـ Lichess — تحقق من الإنترنت.',
      );
    }

    if (res.statusCode == 404) {
      throw const LichessException(
        'لا يوجد مستخدم بهذا المعرّف على Lichess.',
      );
    }

    if (res.statusCode != 200) {
      throw LichessException(
        'خطأ من Lichess (رمز ${res.statusCode}).',
      );
    }
  }

  List<String> _splitPgns(String text) {
    final starts = RegExp(
      r'(?=^\[Event )',
      multiLine: true,
    ).allMatches(text).map((m) => m.start).toList();

    if (starts.isEmpty) {
      final trimmed = text.trim();
      return trimmed.isEmpty ? <String>[] : [trimmed];
    }

    final games = <String>[];

    for (var i = 0; i < starts.length; i++) {
      final start = starts[i];
      final end = i + 1 < starts.length
          ? starts[i + 1]
          : text.length;

      final chunk = text.substring(start, end).trim();

      if (chunk.isNotEmpty) {
        games.add(chunk);
      }
    }

    return games;
  }

  String _guessTimeClass(String pgn) {
    final event =
        (extractPgnHeaders(pgn)['Event'] ?? '')
            .toLowerCase();

    for (final k in [
      'bullet',
      'blitz',
      'rapid',
      'classical',
      'correspondence',
    ]) {
      if (event.contains(k)) {
        return k;
      }
    }

    return '';
  }

  LichessGame? _parseOne(String pgn) {
    try {
      final h = extractPgnHeaders(pgn);

      final white = h['White'] ?? '?';
      final black = h['Black'] ?? '?';
      final result = h['Result'] ?? '*';

      DateTime? endTime;

      final utcDate = h['UTCDate'];
      final utcTime = h['UTCTime'];

      if (utcDate != null) {
        try {
          final dateParts =
              utcDate.split('.').map(int.parse).toList();

          final timeParts = (utcTime ?? '00:00:00')
              .split(':')
              .map(int.parse)
              .toList();

          endTime = DateTime.utc(
            dateParts[0],
            dateParts.length > 1 ? dateParts[1] : 1,
            dateParts.length > 2 ? dateParts[2] : 1,
            timeParts.isNotEmpty ? timeParts[0] : 0,
            timeParts.length > 1 ? timeParts[1] : 0,
          );
        } catch (_) {}
      }

      return LichessGame(
        pgn: pgn,
        whiteUsername: white,
        blackUsername: black,
        result: result,
        timeClass: _guessTimeClass(pgn),
        endTime: endTime,
      );
    } catch (_) {
      return null;
    }
  }

  /// يجلب أحدث [limit] مباراة لهذا المستخدم من Lichess
  /// (لا يتطلب أي تسجيل دخول — بيانات عامة فقط).
  Future<List<LichessGame>> fetchRecentGames(
    String username, {
    int limit = 20,
  }) async {
    final uri = Uri.parse(
      'https://lichess.org/api/games/user/'
      '${Uri.encodeComponent(username.trim())}'
      '?max=$limit&opening=true',
    );

    late final http.Response res;

    try {
      res = await http
          .get(
            uri,
            headers: {
              'User-Agent': _userAgent,
              'Accept': 'application/x-chess-pgn',
            },
          )
          .timeout(const Duration(seconds: 30));
    } catch (_) {
      throw const LichessException(
        'تعذر الاتصال بـ Lichess — تحقق من الإنترنت.',
      );
    }

    if (res.statusCode == 404) {
      throw const LichessException(
        'لا يوجد مستخدم بهذا المعرّف على Lichess.',
      );
    }

    if (res.statusCode != 200) {
      throw LichessException(
        'تعذر جلب مباريات Lichess (رمز ${res.statusCode}).',
      );
    }

    final chunks = _splitPgns(res.body);

    final games = <LichessGame>[];

    for (final chunk in chunks) {
      final g = _parseOne(chunk);

      if (g != null) {
        games.add(g);
      }
    }

    return games;
  }
}
