import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// خطأ مفهوم للمستخدم عند التعامل مع Chess.com.
class ChessComException implements Exception {
  final String message;

  const ChessComException(this.message);

  @override
  String toString() => message;
}

/// مباراة واحدة من Chess.com.
class ChessComGame {
  final String pgn;
  final String whiteUsername;
  final String blackUsername;
  final String whiteResult;
  final String blackResult;
  final String timeClass;
  final DateTime? endTime;

  const ChessComGame({
    required this.pgn,
    required this.whiteUsername,
    required this.blackUsername,
    required this.whiteResult,
    required this.blackResult,
    this.timeClass = '',
    this.endTime,
  });

  bool _isWhite(String username) =>
      whiteUsername.toLowerCase() == username.trim().toLowerCase();

  /// اسم الخصم بالنسبة للاعب [username].
  String opponentOf(String username) =>
      _isWhite(username) ? blackUsername : whiteUsername;

  /// 'win' أو 'draw' أو 'loss' بالنسبة للاعب [username].
  String outcomeFor(String username) {
    final result = _isWhite(username) ? whiteResult : blackResult;

    if (result == 'win') {
      return 'win';
    }

    const drawResults = <String>{
      'agreed',
      'repetition',
      'stalemate',
      'insufficient',
      '50move',
      'timevsinsufficient',
    };

    if (drawResults.contains(result)) {
      return 'draw';
    }

    return 'loss';
  }
}

class ChessComService {
  static const String _base = 'https://api.chess.com/pub';

  static const Map<String, String> _headers = <String, String>{
    'User-Agent': 'ChessAnalyzer/1.0 (Flutter)',
    'Accept': 'application/json',
  };

  static const Duration _timeout = Duration(seconds: 20);

  Future<http.Response> _get(String url) async {
    try {
      return await http
          .get(Uri.parse(url), headers: _headers)
          .timeout(_timeout);
    } on TimeoutException {
      throw const ChessComException(
        'انتهت مهلة الاتصال بـ Chess.com. حاول مرة أخرى.',
      );
    } catch (_) {
      throw const ChessComException(
        'تعذر الاتصال بـ Chess.com. تحقق من الإنترنت.',
      );
    }
  }

  /// يتأكد أن اسم المستخدم موجود على Chess.com.
  Future<void> verifyUsername(String username) async {
    final u = Uri.encodeComponent(username.trim().toLowerCase());
    final res = await _get('$_base/player/$u');

    if (res.statusCode == 404) {
      throw const ChessComException('اسم المستخدم غير موجود على Chess.com.');
    }

    if (res.statusCode == 429) {
      throw const ChessComException(
        'عدد الطلبات كبير على Chess.com. انتظر قليلًا ثم أعد المحاولة.',
      );
    }

    if (res.statusCode != 200) {
      throw ChessComException(
        'تعذر التحقق من الحساب (رمز ${res.statusCode}).',
      );
    }
  }

  /// يجلب أحدث [limit] مباراة (الأحدث أولًا).
  Future<List<ChessComGame>> fetchRecentGames(
    String username, {
    int limit = 50,
  }) async {
    final u = Uri.encodeComponent(username.trim().toLowerCase());

    final archivesRes = await _get('$_base/player/$u/games/archives');

    if (archivesRes.statusCode != 200) {
      throw ChessComException(
        'تعذر جلب أرشيف المباريات (رمز ${archivesRes.statusCode}).',
      );
    }

    final archivesJson = jsonDecode(archivesRes.body);

    final archives = <String>[
      if (archivesJson is Map && archivesJson['archives'] is List)
        for (final a in archivesJson['archives'] as List) a.toString(),
    ];

    final games = <ChessComGame>[];

    // الأرشيف مرتب من الأقدم للأحدث، نبدأ من الأحدث.
    for (final url in archives.reversed) {
      if (games.length >= limit) break;

      final res = await _get(url);

      if (res.statusCode != 200) continue;

      final decoded = jsonDecode(res.body);

      if (decoded is! Map || decoded['games'] is! List) continue;

      final monthGames = <ChessComGame>[];

      for (final raw in decoded['games'] as List) {
        final game = _parseGame(raw);

        if (game != null) {
          monthGames.add(game);
        }
      }

      monthGames.sort((a, b) {
        final ta = a.endTime?.millisecondsSinceEpoch ?? 0;
        final tb = b.endTime?.millisecondsSinceEpoch ?? 0;
        return tb.compareTo(ta);
      });

      games.addAll(monthGames);
    }

    return games.length > limit ? games.sublist(0, limit) : games;
  }

  ChessComGame? _parseGame(dynamic raw) {
    if (raw is! Map) return null;

    // نتجاهل المتغيرات (chess960 وغيرها) لأن التحليل يفترض الشطرنج العادي.
    final rules = raw['rules']?.toString() ?? 'chess';
    if (rules != 'chess') return null;

    final pgn = raw['pgn']?.toString() ?? '';
    if (pgn.trim().isEmpty) return null;

    final white = raw['white'];
    final black = raw['black'];

    if (white is! Map || black is! Map) return null;

    final endSeconds = raw['end_time'];

    return ChessComGame(
      pgn: pgn,
      whiteUsername: white['username']?.toString() ?? '?',
      blackUsername: black['username']?.toString() ?? '?',
      whiteResult: white['result']?.toString() ?? '',
      blackResult: black['result']?.toString() ?? '',
      timeClass: raw['time_class']?.toString() ?? '',
      endTime: endSeconds is num
          ? DateTime.fromMillisecondsSinceEpoch(endSeconds.toInt() * 1000)
          : null,
    );
  }
}
