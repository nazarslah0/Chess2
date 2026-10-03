import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:chess_analyzer/analysis_result.dart';
import 'package:chess_analyzer/game_review_models.dart';
import 'package:chess_analyzer/lichess_data_service.dart';

MoveAnalysisResult sampleMove({
  int ply = 0,
  MoveQuality q = MoveQuality.best,
}) =>
    MoveAnalysisResult(
      ply: ply,
      moveNumber: ply ~/ 2 + 1,
      side: ply.isEven ? 'w' : 'b',
      san: 'e4',
      uci: 'e2e4',
      fenBefore: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
      fenAfter: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1',
      evaluationBeforeCp: 20,
      evaluationAfterCp: 25,
      evaluationLossCp: -5,
      evaluationBeforeWhiteCp: 20,
      evaluationAfterWhiteCp: 25,
      bestMoveSan: 'e4',
      bestMoveUci: 'e2e4',
      principalVariationUci: const ['e2e4', 'e7e5'],
      classification: q,
      phase: 'opening',
      materialBefore: 62,
      materialAfter: 62,
      isCritical: false,
      isBestMove: true,
      isBrilliant: q == MoveQuality.brilliant,
      isMistake: false,
      isBlunder: false,
      isMissedOpportunity: false,
      isGreat: q == MoveQuality.great,
      bestMoveGapCp: 40,
      tablebaseWdlBeforeWhite: 1,
      tablebaseWdlAfterWhite: 0,
      bookInfo: const BookMoveInfo(
        isBook: true,
        mastersGames: 120,
        mastersPositionGames: 200,
        lichessGames: 5000,
        lichessPositionGames: 9000,
      ),
      maiaProbability: 0.07,
      maiaBestProbability: 0.31,
      maiaTopUci: 'd2d4',
      maiaBucket: 1500,
    );

void main() {
  test('PositionAnalysis: ذهاب وإياب JSON', () {
    const p = PositionAnalysis(
      fen: '8/8/8/8/8/8/8/K6k w - - 0 1',
      evalPawns: -1.25,
      evalLabel: '-1.25',
      bestUci: 'a1a2',
      pv: ['a1a2', 'h1h2'],
      secondBestCpWhite: -90,
      tbWdlWhite: 0,
    );

    final back = PositionAnalysis.fromJson(
      jsonDecode(jsonEncode(p.toJson())),
    );

    expect(back.fen, p.fen);
    expect(back.evalPawns, p.evalPawns);
    expect(back.evalLabel, p.evalLabel);
    expect(back.bestUci, p.bestUci);
    expect(back.pv, p.pv);
    expect(back.secondBestCpWhite, -90);
    expect(back.tbWdlWhite, 0);
  });

  test('MoveAnalysisResult: كل الحقول تنجو من JSON', () {
    final m = sampleMove(q: MoveQuality.great);

    final b = MoveAnalysisResult.fromJson(
      jsonDecode(jsonEncode(m.toJson())),
    );

    expect(b.ply, m.ply);
    expect(b.side, 'w');
    expect(b.uci, 'e2e4');
    expect(b.classification, MoveQuality.great);
    expect(b.isGreat, isTrue);
    expect(b.evaluationBeforeWhiteCp, 20);
    expect(b.evaluationAfterWhiteCp, 25);
    expect(b.evaluationLossCp, -5);
    expect(b.principalVariationUci, ['e2e4', 'e7e5']);
    expect(b.bestMoveGapCp, 40);
    expect(b.tablebaseWdlBeforeWhite, 1);
    expect(b.tablebaseWdlAfterWhite, 0);
    expect(b.bookInfo!.isBook, isTrue);
    expect(b.bookInfo!.mastersGames, 120);
    expect(b.bookInfo!.lichessPositionGames, 9000);
    expect(b.maiaProbability, 0.07);
    expect(b.maiaBestProbability, 0.31);
    expect(b.maiaTopUci, 'd2d4');
    expect(b.maiaBucket, 1500);
  });

  test('تصنيف مجهول في JSON يعود إلى good ولا ينهار', () {
    final j = sampleMove().toJson()..['q'] = 'غير-موجود';

    expect(
      MoveAnalysisResult.fromJson(j).classification,
      MoveQuality.good,
    );
  });

  test('نتيجة Tablebase من منظور اللاعب', () {
    // أبيض: بعد النقلة تعادل.
    expect(sampleMove().tablebaseOutcomeForMover, 'draw');

    final black = MoveAnalysisResult.fromJson(
      (sampleMove(ply: 1).toJson())..['tba'] = 1,
    );

    // WDL الأبيض = 1 (فوز الأبيض) → الأسود خاسر.
    expect(black.tablebaseOutcomeForMover, 'loss');
  });

  test('GameAnalysis: ذهاب وإياب وتناسق الأطوال', () {
    final a = GameAnalysis(
      analysisVersion: kAnalysisVersion,
      engineVersion: kEngineVersion,
      depth: 14,
      multiPv: 2,
      settingsKey: 'maia:1500',
      createdAt: 123,
      explorerAvailable: true,
      positions: const [
        PositionAnalysis(
          fen: 'f0',
          evalPawns: 0.2,
          evalLabel: '+0.20',
          bestUci: 'e2e4',
          pv: ['e2e4'],
        ),
        PositionAnalysis(
          fen: 'f1',
          evalPawns: 0.25,
          evalLabel: '+0.25',
          bestUci: 'e7e5',
          pv: ['e7e5'],
        ),
      ],
      moves: [sampleMove()],
    );

    expect(a.isConsistent, isTrue);

    final b = GameAnalysis.fromJson(jsonDecode(jsonEncode(a.toJson())));

    expect(b.analysisVersion, kAnalysisVersion);
    expect(b.engineVersion, 'stockfish19');
    expect(b.depth, 14);
    expect(b.multiPv, 2);
    expect(b.settingsKey, 'maia:1500');
    expect(b.explorerAvailable, isTrue);
    expect(b.positions.length, 2);
    expect(b.moves.length, 1);
    expect(b.isConsistent, isTrue);
  });
}
