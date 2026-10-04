import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'pgn_utils.dart' show extractPgnHeaders;

enum ChessComErrorKind { notFound, network, rateLimit, other }

/// خطأ مفهوم للمستخدم عند التعامل مع Chess.com.
class ChessComException implements Exception {
  final String message;
  final ChessComErrorKind kind;

  const ChessComException(
    this.message, {
    this.kind = ChessComErrorKind.other,
  });

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

  /// بيانات إضافية من Public API (كلها اختيارية للتوافق مع الكود القديم).
  final String url;
  final String uuid;
  final int? whiteRating;
  final int? blackRating;
  final bool rated;
  final String timeControl;
  final String eco;
  final String opening;

  const ChessComGame({
    required this.pgn,
    required this.whiteUsername,
    required this.blackUsername,
    required this.whiteResult,
    required this.blackResult,
    this.timeClass = '',
    this.endTime,
    this.url = '',
    this.uuid = '',
    this.whiteRating,
    this.blackRating,
    this.rated = true,
    this.timeControl = '',
    this.eco = '',
    this.opening = '',
  });

  /// معرّف المباراة على Chess.com (آخر جزء من الرابط، أو uuid).
  String get gameId {
    final segs = url.split('/').where((e) => e.isNotEmpty).toList();

    if (segs.isNotEmpty && RegExp(r'^\d+$').hasMatch(segs.last)) {
      return segs.last;
    }

    return uuid;
  }

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
  ChessComService({
    http.Client? client,
    this.requestDelay = const Duration(milliseconds: 400),
    this.maxRetries = 2,
    this.retryBaseDelay = const Duration(seconds: 2),
  }) : _client = client ?? http.Client();

  final http.Client _client;

  /// أدنى فاصل بين طلبين متتاليين (الطلبات متسلسلة دائمًا).
  final Duration requestDelay;

  /// عدد إعادة المحاولة عند 429 / 5xx (محدود، بلا حلقة لا نهائية).
  final int maxRetries;
  final Duration retryBaseDelay;

  DateTime? _lastRequestAt;

  static const String _base = 'https://api.chess.com/pub';

  static const Map<String, String> _headers = <String, String>{
    'User-Agent': 'ChessAnalyzer/1.0 (Flutter)',
    'Accept': 'application/json',
  };

  static const Duration _timeout = Duration(seconds: 20);

  static const String _networkMsg =
      'تعذر الاتصال بـ Chess.com\nتحقق من اتصال الإنترنت وحاول مرة أخرى.';
  static const String _rateMsg =
      'تم الوصول إلى حد الطلبات.\nانتظر قليلًا ثم حاول مرة أخرى.';

  Future<void> _throttle() async {
    final last = _lastRequestAt;

    if (last != null && requestDelay > Duration.zero) {
      final wait = requestDelay - DateTime.now().difference(last);

      if (wait > Duration.zero) await Future<void>.delayed(wait);
    }

    _lastRequestAt = DateTime.now();
  }

  Future<http.Response> _get(String url) async {
    for (var attempt = 0;; attempt++) {
      await _throttle();

      http.Response res;

      try {
        res = await _client
            .get(Uri.parse(url), headers: _headers)
            .timeout(_timeout);
      } on TimeoutException {
        throw const ChessComException(
          'انتهت مهلة الاتصال بـ Chess.com. حاول مرة أخرى.',
          kind: ChessComErrorKind.network,
        );
      } catch (_) {
        throw const ChessComException(
          _networkMsg,
          kind: ChessComErrorKind.network,
        );
      }

      final retryable = res.statusCode == 429 || res.statusCode >= 500;

      if (!retryable) return res;

      if (attempt >= maxRetries) {
        if (res.statusCode == 429) {
          throw const ChessComException(
            _rateMsg,
            kind: ChessComErrorKind.rateLimit,
          );
        }

        return res;
      }

      // backoff أسّي: 2s ثم 4s ...
      await Future<void>.delayed(retryBaseDelay * (1 << attempt));
    }
  }

  String _enc(String username) =>
      Uri.encodeComponent(username.trim().toLowerCase());

  ChessComException _notFound() => const ChessComException(
        'لم يتم العثور على هذا المستخدم في Chess.com',
        kind: ChessComErrorKind.notFound,
      );

  /// بيانات اللاعب العامة. يرمي notFound إن لم يوجد.
  Future<Map<String, dynamic>> getPlayer(String username) async {
    final res = await _get('$_base/player/${_enc(username)}');

    if (res.statusCode == 404) throw _notFound();

    if (res.statusCode != 200) {
      throw ChessComException(
        'تعذر التحقق من الحساب (رمز ${res.statusCode}).',
      );
    }

    final decoded = jsonDecode(res.body);

    return decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
  }

  /// روابط أرشيف الأشهر (الأقدم أولًا).
  Future<List<String>> getGameArchives(String username) async {
    final res = await _get('$_base/player/${_enc(username)}/games/archives');

    if (res.statusCode == 404) throw _notFound();

    if (res.statusCode != 200) {
      throw ChessComException(
        'تعذر جلب أرشيف المباريات (رمز ${res.statusCode}).',
      );
    }

    final decoded = jsonDecode(res.body);

    return <String>[
      if (decoded is Map && decoded['archives'] is List)
        for (final a in decoded['archives'] as List) a.toString(),
    ];
  }

  /// مباريات شهر واحد (قائمة فارغة إن لم توجد).
  Future<List<ChessComGame>> getGamesForMonth(
    String username,
    int year,
    int month,
  ) {
    final mm = month.toString().padLeft(2, '0');

    return getGamesFromArchiveUrl('$_base/player/${_enc(username)}/games/$year/$mm');
  }

  Future<List<ChessComGame>> getGamesFromArchiveUrl(String url) async {
    final res = await _get(url);

    if (res.statusCode == 404) return <ChessComGame>[];

    if (res.statusCode != 200) {
      throw ChessComException(
        'تعذر جلب المباريات (رمز ${res.statusCode}).',
      );
    }

    final decoded = jsonDecode(res.body);

    if (decoded is! Map || decoded['games'] is! List) {
      return <ChessComGame>[];
    }

    final out = <ChessComGame>[];

    for (final raw in decoded['games'] as List) {
      final g = _parseGame(raw);

      if (g != null) out.add(g);
    }

    out.sort((a, b) => (b.endTime?.millisecondsSinceEpoch ?? 0)
        .compareTo(a.endTime?.millisecondsSinceEpoch ?? 0));

    return out;
  }

  /// يتأكد أن اسم المستخدم موجود على Chess.com.
  Future<void> verifyUsername(String username) async {
    final u = Uri.encodeComponent(username.trim().toLowerCase());
    final res = await _get('$_base/player/$u');

    if (res.statusCode == 404) {
      throw _notFound();
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

    final headers = extractPgnHeaders(pgn);

    int? rating(Map side) => side['rating'] is num
        ? (side['rating'] as num).toInt()
        : null;

    return ChessComGame(
      pgn: pgn,
      whiteUsername: white['username']?.toString() ?? '?',
      blackUsername: black['username']?.toString() ?? '?',
      whiteResult: white['result']?.toString() ?? '',
      blackResult: black['result']?.toString() ?? '',
      timeClass: raw['time_class']?.toString() ?? '',
      url: raw['url']?.toString() ?? '',
      uuid: raw['uuid']?.toString() ?? '',
      whiteRating: rating(white),
      blackRating: rating(black),
      rated: raw['rated'] != false,
      timeControl: raw['time_control']?.toString() ?? '',
      eco: headers['ECO'] ?? '',
      opening: _openingName(headers),
      endTime: endSeconds is num
          ? DateTime.fromMillisecondsSinceEpoch(endSeconds.toInt() * 1000)
          : null,
    );
  }

  /// اسم الافتتاح من ECOUrl (مثل .../openings/Sicilian-Defense-...).
  static String _openingName(Map<String, String> headers) {
    final u = headers['ECOUrl'] ?? '';

    if (u.isEmpty) return '';

    final slug = u.split('/').where((e) => e.isNotEmpty).last;

    return slug.replaceAll('-', ' ');
  }
}

/// اسم بديل يطابق التسمية المطلوبة في المواصفات.
typedef ChessComApiService = ChessComService;
