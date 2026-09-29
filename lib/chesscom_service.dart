import 'dart:convert';

import 'package:http/http.dart' as http;

/// معلومات مباراة واحدة من أرشيف chess.com العام.
class ChessComGame {
  final String pgn;
  final String url;
  final String whiteUsername;
  final String blackUsername;
  final String whiteResult;
  final String blackResult;
  final int? whiteRating;
  final int? blackRating;
  final String timeClass;
  final DateTime? endTime;

  const ChessComGame({
    required this.pgn,
    required this.url,
    required this.whiteUsername,
    required this.blackUsername,
    required this.whiteResult,
    required this.blackResult,
    required this.whiteRating,
    required this.blackRating,
    required this.timeClass,
    required this.endTime,
  });

  /// نتيجة المباراة من منظور صاحب المعرّف الذي بحثنا عنه.
  /// 'win' / 'loss' / 'draw' / غير معروف.
  String outcomeFor(String username) {
    final isWhite = whiteUsername.toLowerCase() ==
        username.toLowerCase();

    final myResult =
        isWhite ? whiteResult : blackResult;

    if (myResult == 'win') {
      return 'win';
    }

    const draws = {
      'agreed',
      'repetition',
      'stalemate',
      'insufficient',
      'fiftymove',
      'timevsinsufficient',
    };

    if (draws.contains(myResult)) {
      return 'draw';
    }

    return 'loss';
  }

  String opponentOf(String username) {
    final isWhite = whiteUsername.toLowerCase() ==
        username.toLowerCase();

    return isWhite ? blackUsername : whiteUsername;
  }
}

class ChessComException implements Exception {
  final String message;

  const ChessComException(this.message);

  @override
  String toString() => message;
}

class ChessComService {
  static const _userAgent =
      'ChessAnalyzerFlutterApp/1.0 '
      '(personal chess analysis app)';

  Map<String, String> get _headers => {
        'User-Agent': _userAgent,
        'Accept': 'application/json',
      };

  /// يتحقق من وجود المستخدم ويعيد بياناته الأساسية.
  Future<void> verifyUsername(String username) async {
    final uri = Uri.parse(
      'https://api.chess.com/pub/player/'
      '${Uri.encodeComponent(username.trim().toLowerCase())}',
    );

    late final http.Response res;

    try {
      res = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      throw const ChessComException(
        'تعذر الاتصال بـ Chess.com — تحقق من الإنترنت.',
      );
    }

    if (res.statusCode == 404) {
      throw const ChessComException(
        'لا يوجد مستخدم بهذا المعرّف على Chess.com.',
      );
    }

    if (res.statusCode != 200) {
      throw ChessComException(
        'خطأ من Chess.com (رمز ${res.statusCode}).',
      );
    }
  }

  /// روابط أرشيف الأشهر لكل الألعاب (من الأقدم إلى الأحدث).
  Future<List<String>> fetchArchiveUrls(
    String username,
  ) async {
    final uri = Uri.parse(
      'https://api.chess.com/pub/player/'
      '${Uri.encodeComponent(username.trim().toLowerCase())}'
      '/games/archives',
    );

    final res = await http
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 15));

    if (res.statusCode == 404) {
      throw const ChessComException(
        'لا يوجد مستخدم بهذا المعرّف على Chess.com.',
      );
    }

    if (res.statusCode != 200) {
      throw ChessComException(
        'تعذر جلب أرشيف المباريات (رمز ${res.statusCode}).',
      );
    }

    final data =
        jsonDecode(res.body) as Map<String, dynamic>;

    final archives =
        (data['archives'] as List?) ?? [];

    return archives
        .map((e) => e.toString())
        .toList();
  }

  ChessComGame? _parseGame(Map<String, dynamic> g) {
    try {
      final pgn = g['pgn']?.toString() ?? '';

      if (pgn.trim().isEmpty) {
        return null;
      }

      final white =
          g['white'] as Map<String, dynamic>? ?? {};

      final black =
          g['black'] as Map<String, dynamic>? ?? {};

      DateTime? endTime;

      final endTimeRaw = g['end_time'];

      if (endTimeRaw is int) {
        endTime = DateTime.fromMillisecondsSinceEpoch(
          endTimeRaw * 1000,
        );
      }

      return ChessComGame(
        pgn: pgn,
        url: g['url']?.toString() ?? '',
        whiteUsername:
            white['username']?.toString() ?? '?',
        blackUsername:
            black['username']?.toString() ?? '?',
        whiteResult:
            white['result']?.toString() ?? '',
        blackResult:
            black['result']?.toString() ?? '',
        whiteRating: white['rating'] is int
            ? white['rating'] as int
            : int.tryParse(
                '${white['rating'] ?? ''}',
              ),
        blackRating: black['rating'] is int
            ? black['rating'] as int
            : int.tryParse(
                '${black['rating'] ?? ''}',
              ),
        timeClass:
            g['time_class']?.toString() ?? '',
        endTime: endTime,
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<ChessComGame>> fetchGamesFromArchive(
    String archiveUrl,
  ) async {
    final res = await http
        .get(Uri.parse(archiveUrl), headers: _headers)
        .timeout(const Duration(seconds: 20));

    if (res.statusCode != 200) {
      return <ChessComGame>[];
    }

    final data =
        jsonDecode(res.body) as Map<String, dynamic>;

    final games =
        (data['games'] as List?) ?? [];

    final result = <ChessComGame>[];

    for (final g in games) {
      if (g is Map<String, dynamic>) {
        final parsed = _parseGame(g);

        if (parsed != null) {
          result.add(parsed);
        }
      }
    }

    return result;
  }

  /// يجلب أحدث [limit] مباراة لهذا المستخدم (تصفّح الأرشيف
  /// من الأحدث إلى الأقدم حتى نجمع العدد المطلوب).
  Future<List<ChessComGame>> fetchRecentGames(
    String username, {
    int limit = 20,
  }) async {
    final archives = await fetchArchiveUrls(username);

    if (archives.isEmpty) {
      return <ChessComGame>[];
    }

    final result = <ChessComGame>[];

    for (var i = archives.length - 1; i >= 0; i--) {
      final games =
          await fetchGamesFromArchive(archives[i]);

      // الأحدث أولًا داخل الشهر نفسه.
      result.addAll(games.reversed);

      if (result.length >= limit) {
        break;
      }
    }

    if (result.length > limit) {
      return result.sublist(0, limit);
    }

    return result;
  }
}
