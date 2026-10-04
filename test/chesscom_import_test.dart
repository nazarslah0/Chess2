import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:chess_analyzer/analysis_result.dart';
import 'package:chess_analyzer/chesscom_repository.dart';
import 'package:chess_analyzer/chesscom_service.dart';
import 'package:chess_analyzer/game_library.dart';
import 'package:chess_analyzer/game_review_models.dart';
import 'package:chess_analyzer/pgn_utils.dart';
import 'package:chess_analyzer/user_stats.dart';

const String _pgn = '''
[Event "Live Chess"]
[Site "Chess.com"]
[Date "2026.09.30"]
[White "nazarslah"]
[Black "rival"]
[Result "1-0"]
[ECO "C20"]
[ECOUrl "https://www.chess.com/openings/Kings-Pawn-Opening"]
[Link "https://www.chess.com/game/live/111"]

1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 1-0
''';

Map<String, dynamic> _rawGame({
  String id = '111',
  String white = 'nazarslah',
  String black = 'rival',
  String whiteResult = 'win',
  String blackResult = 'resigned',
  int end = 1790000000,
  String rules = 'chess',
  String? pgn,
}) =>
    {
      'url': 'https://www.chess.com/game/live/$id',
      'uuid': 'uuid-$id',
      'pgn': pgn ?? _pgn.replaceAll('/live/111', '/live/$id'),
      'time_class': 'blitz',
      'time_control': '300',
      'rated': true,
      'rules': rules,
      'end_time': end,
      'white': {'username': white, 'rating': 1420, 'result': whiteResult},
      'black': {'username': black, 'rating': 1398, 'result': blackResult},
    };

ChessComService _service(
  Future<http.Response> Function(http.Request) handler, {
  int maxRetries = 1,
}) =>
    ChessComService(
      client: MockClient(handler),
      requestDelay: Duration.zero,
      retryBaseDelay: Duration.zero,
      maxRetries: maxRetries,
    );

void main() {
  group('ChessComApiService', () {
    test('archives', () async {
      final s = _service((r) async {
        expect(r.url.path, '/pub/player/nazarslah/games/archives');

        return http.Response(
          jsonEncode({
            'archives': [
              'https://api.chess.com/pub/player/nazarslah/games/2026/08',
              'https://api.chess.com/pub/player/nazarslah/games/2026/09',
            ],
          }),
          200,
        );
      });

      final a = await s.getGameArchives('NazarSlah');

      expect(a.length, 2);
      expect(ArchiveMonth.parse(a.last)!.label, '2026/09');
    });

    test('games for month + metadata', () async {
      final s = _service((r) async {
        expect(r.url.path, '/pub/player/nazarslah/games/2026/09');

        return http.Response(
          jsonEncode({
            'games': [_rawGame(), _rawGame(id: '2', rules: 'chess960')],
          }),
          200,
        );
      });

      final games = await s.getGamesForMonth('nazarslah', 2026, 9);

      // المتغيرات (chess960) تُستبعد.
      expect(games.length, 1);
      expect(games.first.gameId, '111');
      expect(games.first.whiteRating, 1420);
      expect(games.first.eco, 'C20');
      expect(games.first.timeClass, 'blitz');
    });

    test('invalid username → notFound', () async {
      final s = _service((r) async => http.Response('{}', 404));

      expect(
        () => s.getGameArchives('nobody'),
        throwsA(isA<ChessComException>().having(
          (e) => e.kind,
          'kind',
          ChessComErrorKind.notFound,
        )),
      );
    });

    test('empty games', () async {
      final s = _service((r) async => http.Response(jsonEncode({'games': []}), 200));

      expect(await s.getGamesForMonth('a', 2026, 9), isEmpty);
    });

    test('network error', () async {
      final s = _service((r) async => throw const SocketException('x'));

      expect(
        () => s.getGameArchives('a'),
        throwsA(isA<ChessComException>().having(
          (e) => e.kind,
          'kind',
          ChessComErrorKind.network,
        )),
      );
    });

    test('rate limit: محاولات محدودة بلا حلقة لا نهائية', () async {
      var calls = 0;

      final s = _service((r) async {
        calls++;

        return http.Response('', 429);
      });

      await expectLater(
        s.getGameArchives('a'),
        throwsA(isA<ChessComException>().having(
          (e) => e.kind,
          'kind',
          ChessComErrorKind.rateLimit,
        )),
      );

      expect(calls, 2); // المحاولة الأولى + إعادة واحدة
    });
  });

  group('Chess.com game → LibraryGame', () {
    test('الحقول الأساسية والمعرّف', () async {
      final s = _service((r) async =>
          http.Response(jsonEncode({'games': [_rawGame()]}), 200));

      final g = (await s.getGamesForMonth('nazarslah', 2026, 9)).first;
      final lib = LibraryGame.fromChessCom(g, 'NazarSlah');

      expect(lib.id, 'cc_111');
      expect(lib.chessComGameId, '111');
      expect(lib.source, kSourceChessCom);
      expect(lib.username, 'nazarslah');
      expect(lib.userColor, 'w');
      expect(lib.outcome, 'win');
      expect(lib.result, '1-0');
      expect(lib.rated, isTrue);

      final back = LibraryGame.fromJson(lib.toJson())!;

      expect(back.id, lib.id);
      expect(back.pgn, lib.pgn);
    });

    test('PGN يُحلَّل بالـparser الحالي', () {
      final plies = parsePgnMoves(_pgn)!;

      expect(plies.length, 6);
      expect(plies.first.san, 'e4');
      expect(plies.first.fenBefore.startsWith('rnbqkbnr'), isTrue);
    });

    test('معرّف بديل (hash) ثابت وفريد بدون Link', () {
      const a = '[White "A"]\n[Black "B"]\n[Result "1-0"]\n\n1. e4 e5 1-0';
      const b = '[White "A"]\n[Black "B"]\n[Result "0-1"]\n\n1. e4 e5 0-1';

      expect(libraryGameIdFromPgn(a), libraryGameIdFromPgn(a));
      expect(libraryGameIdFromPgn(a), isNot(libraryGameIdFromPgn(b)));
      expect(libraryGameIdFromPgn(a).startsWith('h_'), isTrue);
    });
  });

  group('منع التكرار + التخزين الدائم', () {
    late Directory dir;
    late GameLibraryStorage storage;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('chess2_lib_test_');
      storage = GameLibraryStorage(directoryProvider: () async => dir);
    });

    tearDown(() => dir.deleteSync(recursive: true));

    LibraryGame mk(String id) => LibraryGame.fromChessCom(
          ChessComGame(
            pgn: _pgn.replaceAll('/live/111', '/live/$id'),
            whiteUsername: 'nazarslah',
            blackUsername: 'rival',
            whiteResult: 'win',
            blackResult: 'resigned',
            url: 'https://www.chess.com/game/live/$id',
          ),
          'nazarslah',
        );

    test('نفس المباراة لا تُضاف مرتين', () async {
      expect(await storage.add([mk('1'), mk('2')]), 2);
      expect(await storage.add([mk('2'), mk('3')]), 1);
      expect((await storage.all()).length, 3);
    });

    test('تبقى بعد إعادة تشغيل التطبيق', () async {
      await storage.add([mk('1')]);
      await storage.saveSyncState(
        'nazarslah',
        const SyncState(lastSyncMs: 5, lastMonth: '2026/09'),
      );

      storage.resetMemory();

      expect((await storage.all()).length, 1);
      expect((await storage.syncState('NazarSlah'))!.lastMonth, '2026/09');
    });

    test('المزامنة تحفظ الجديد فقط وتتجاهل الموجود', () async {
      var month9 = [_rawGame(id: '1'), _rawGame(id: '2')];

      final client = MockClient((r) async {
        if (r.url.path.endsWith('/archives')) {
          return http.Response(
            jsonEncode({
              'archives': [
                'https://api.chess.com/pub/player/nazarslah/games/2026/09',
              ],
            }),
            200,
          );
        }

        if (r.url.path.contains('/games/2026/09')) {
          return http.Response(jsonEncode({'games': month9}), 200);
        }

        return http.Response('{}', 200); // /player/<u>
      });

      final repo = ChessComRepository(
        service: ChessComService(
          client: client,
          requestDelay: Duration.zero,
          retryBaseDelay: Duration.zero,
        ),
        storage: storage,
        now: () => DateTime(2026, 10, 4),
      );

      final first = await repo.sync('nazarslah');

      expect(first.added, 2);

      month9 = [_rawGame(id: '1'), _rawGame(id: '2'), _rawGame(id: '3')];

      final second = await repo.sync('nazarslah');

      expect(second.added, 1);
      expect(second.skipped, 2);
      expect((await storage.all()).length, 3);
    });
  });

  group('اختيار الفترة', () {
    final all = [
      for (final m in [1, 5, 8, 9])
        ArchiveMonth.parse('https://x/pub/player/u/games/2026/${m.toString().padLeft(2, '0')}')!,
    ];
    final now = DateTime(2026, 10, 4);

    test('آخر شهر / 3 أشهر / السنة / شهر محدد / الكل', () {
      List<String> sel(ImportPeriod p, {({int year, int month})? month}) => [
            for (final a in ChessComRepository.selectMonths(all, p, now: now, month: month))
              a.label,
          ];

      expect(sel(ImportPeriod.lastMonth), ['2026/09']);
      expect(sel(ImportPeriod.last3Months), ['2026/09', '2026/08']);
      expect(sel(ImportPeriod.thisYear).length, 4);
      expect(sel(ImportPeriod.month, month: (year: 2026, month: 5)), ['2026/05']);
      expect(sel(ImportPeriod.all).first, '2026/09');
    });
  });

  group('Analysis → MoveAnalysisResult → إحصائيات', () {
    MoveAnalysisResult mv(int i, String side, MoveQuality q, int before, int after) =>
        MoveAnalysisResult(
          ply: i,
          moveNumber: i ~/ 2 + 1,
          side: side,
          san: 'e4',
          uci: 'e2e4',
          fenBefore: 'f$i',
          fenAfter: 'f${i + 1}',
          evaluationBeforeCp: before,
          evaluationAfterCp: after,
          evaluationLossCp: 0,
          evaluationBeforeWhiteCp: side == 'w' ? before : -before,
          evaluationAfterWhiteCp: side == 'w' ? after : -after,
          bestMoveSan: 'e4',
          bestMoveUci: 'e2e4',
          principalVariationUci: const ['e2e4'],
          classification: q,
          phase: 'middlegame',
          materialBefore: 0,
          materialAfter: 0,
          isCritical: false,
          isBestMove: false,
          isBrilliant: q == MoveQuality.brilliant,
          isMistake: q == MoveQuality.mistake,
          isBlunder: q == MoveQuality.blunder,
          isMissedOpportunity: false,
        );

    test('يحسب ACPL والتصنيفات للمستخدم فقط', () {
      final game = LibraryGame.fromChessCom(
        ChessComGame(
          pgn: _pgn,
          whiteUsername: 'nazarslah',
          blackUsername: 'rival',
          whiteResult: 'win',
          blackResult: 'resigned',
          timeClass: 'blitz',
          url: 'https://www.chess.com/game/live/111',
        ),
        'nazarslah',
      );

      final analysis = GameAnalysis(
        analysisVersion: kAnalysisVersion,
        engineVersion: kEngineVersion,
        depth: 14,
        multiPv: 2,
        settingsKey: '',
        createdAt: 0,
        explorerAvailable: false,
        positions: const [],
        moves: [
          mv(0, 'w', MoveQuality.best, 0, 0), // خسارة 0
          mv(1, 'b', MoveQuality.blunder, 0, -500), // للخصم: يُتجاهل
          mv(2, 'w', MoveQuality.blunder, 50, -150), // خسارة 200
        ],
      );

      final s = computeUserStats([(game: game, analysis: analysis)]);

      expect(s.total.games, 1);
      expect(s.total.wins, 1);
      expect(s.total.winRate, 100);
      expect(s.total.analyzed, 1);
      expect(s.total.acpl, 100); // (0 + 200) / 2
      expect(s.qualities[MoveQuality.blunder], 1); // نقلتك فقط
      expect(s.byTimeClass['blitz']!.games, 1);
    });
  });
}
