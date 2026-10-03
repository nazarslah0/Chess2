import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:chess_analyzer/analysis_cache.dart';
import 'package:chess_analyzer/analysis_result.dart';
import 'package:chess_analyzer/game_review_models.dart';

const SavedGame game = SavedGame(
  pgn: '1. e4 e5 *',
  white: 'A',
  black: 'B',
  result: '*',
  date: '2026.10.03',
);

GameAnalysis analysis({int version = kAnalysisVersion, int plies = 2}) {
  return GameAnalysis(
    analysisVersion: version,
    engineVersion: kEngineVersion,
    depth: 14,
    multiPv: 2,
    settingsKey: '',
    createdAt: DateTime.now().millisecondsSinceEpoch,
    explorerAvailable: false,
    positions: [
      for (var i = 0; i <= plies; i++)
        PositionAnalysis(
          fen: 'fen$i',
          evalPawns: i * 0.1,
          evalLabel: '+${(i * 0.1).toStringAsFixed(2)}',
          bestUci: 'e2e4',
          pv: const ['e2e4'],
        ),
    ],
    moves: [
      for (var i = 0; i < plies; i++)
        MoveAnalysisResult(
          ply: i,
          moveNumber: i ~/ 2 + 1,
          side: i.isEven ? 'w' : 'b',
          san: 'e4',
          uci: 'e2e4',
          fenBefore: 'fen$i',
          fenAfter: 'fen${i + 1}',
          evaluationBeforeCp: 0,
          evaluationAfterCp: 0,
          evaluationLossCp: 0,
          bestMoveSan: 'e4',
          bestMoveUci: 'e2e4',
          principalVariationUci: const ['e2e4'],
          classification: MoveQuality.best,
          phase: 'opening',
          materialBefore: 0,
          materialAfter: 0,
          isCritical: false,
          isBestMove: true,
          isBrilliant: false,
          isMistake: false,
          isBlunder: false,
          isMissedOpportunity: false,
        ),
    ],
  );
}

void main() {
  late Directory dir;
  late AnalysisCache cache;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('chess2_cache_test_');
    cache = AnalysisCache(directoryProvider: () async => dir);
  });

  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('مفتاح الكاش', () {
    test('ثابت لنفس المدخلات', () {
      final a = cache.keyFor(pgn: '1. e4 *', depth: 14, multiPv: 2);
      final b = cache.keyFor(pgn: '1. e4 *', depth: 14, multiPv: 2);

      expect(a, b);
      expect(a.length, 16);
    });

    test('يتغير مع كل عنصر من عناصره', () {
      final base = cache.keyFor(pgn: '1. e4 *', depth: 14, multiPv: 2);

      expect(cache.keyFor(pgn: '1. d4 *', depth: 14, multiPv: 2), isNot(base));
      expect(cache.keyFor(pgn: '1. e4 *', depth: 18, multiPv: 2), isNot(base));
      expect(cache.keyFor(pgn: '1. e4 *', depth: 14, multiPv: 3), isNot(base));
      expect(
        cache.keyFor(
          pgn: '1. e4 *',
          depth: 14,
          multiPv: 2,
          engineVersion: 'stockfish20',
        ),
        isNot(base),
      );
      expect(
        cache.keyFor(
          pgn: '1. e4 *',
          depth: 14,
          multiPv: 2,
          settings: 'maia:1500',
        ),
        isNot(base),
      );
    });

    test('stableHash حتمية', () {
      expect(stableHash('abc'), stableHash('abc'));
      expect(stableHash('abc'), isNot(stableHash('abd')));
    });
  });

  group('التخزين الدائم', () {
    test('حفظ ثم تحميل من القرص بعد مسح الذاكرة', () async {
      await cache.save('k1', game, analysis());

      cache.clearMemory(); // محاكاة إعادة تشغيل التطبيق

      final loaded = await cache.load('k1');

      expect(loaded, isNotNull);
      expect(loaded!.moves.length, 2);
      expect(loaded.positions.length, 3);
      expect(loaded.analysisVersion, kAnalysisVersion);
    });

    test('مفتاح غير موجود => null', () async {
      expect(await cache.load('nope'), isNull);
    });

    test('إصدار تحليل مختلف يُتجاهل ويُحذف', () async {
      await cache.save('old', game, analysis(version: kAnalysisVersion - 1));

      cache.clearMemory();

      expect(await cache.load('old'), isNull);

      final files = dir
          .listSync()
          .where((e) => e.path.endsWith('old.json.gz'))
          .toList();

      expect(files, isEmpty);
    });

    test('ملف تالف => null بلا استثناء', () async {
      await cache.save('bad', game, analysis());
      cache.clearMemory();

      File('${dir.path}/bad.json.gz').writeAsBytesSync([1, 2, 3, 4]);

      expect(await cache.load('bad'), isNull);
    });

    test('تحليل غير متناسق الأطوال يُرفض', () async {
      final good = analysis();
      final broken = GameAnalysis(
        analysisVersion: good.analysisVersion,
        engineVersion: good.engineVersion,
        depth: good.depth,
        multiPv: good.multiPv,
        settingsKey: good.settingsKey,
        createdAt: good.createdAt,
        explorerAvailable: false,
        positions: good.positions,
        moves: good.moves.take(1).toList(),
      );

      await cache.save('inc', game, broken);
      cache.clearMemory();

      expect(await cache.load('inc'), isNull);
    });

    test('قائمة المباريات المحفوظة', () async {
      await cache.save('a', game, analysis());
      await cache.save('b', game, analysis());

      final list = await cache.list();

      expect(list.length, 2);
      expect(list.first.game.white, 'A');
    });

    test('سياسة LRU: يُحذف الأقدم عند تجاوز الحد', () async {
      final small = AnalysisCache(
        directoryProvider: () async => dir,
        maxEntries: 2,
      );

      await small.save('k1', game, analysis());
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await small.save('k2', game, analysis());
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await small.save('k3', game, analysis());

      small.clearMemory();

      expect(await small.load('k1'), isNull);
      expect(await small.load('k2'), isNotNull);
      expect(await small.load('k3'), isNotNull);
    });

    test('clear يمسح كل شيء', () async {
      await cache.save('a', game, analysis());
      await cache.clear();

      cache.clearMemory();

      expect(await cache.load('a'), isNull);
    });
  });
}
