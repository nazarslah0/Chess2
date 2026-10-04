import 'package:flutter_test/flutter_test.dart';

import 'package:chess_analyzer/sacrifice_detector.dart';

void main() {
  test('materialBalanceFromFen: بداية المباراة متعادلة', () {
    const start = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

    expect(materialBalanceFromFen(start, 'w'), 0);
    expect(materialBalanceFromFen(start, 'b'), 0);
  });

  test('materialBalanceFromFen: رخ مقابل بيدق', () {
    const fen = '4k3/1p6/8/8/8/8/8/R3K3 w - - 0 1';

    expect(materialBalanceFromFen(fen, 'w'), 4);
    expect(materialBalanceFromFen(fen, 'b'), -4);
  });

  test('تضحية بالرخ تُسترد بوزير: تضحية + زيادة => مؤهَّلة', () {
    // 1.Ra6 bxa6 2.Bxg7 (يأخذ الوزير) Kd7 3.Kd2
    final r = analyzeSacrificeLine(
      fenBefore: '4k3/1p4q1/8/8/8/2B5/8/R3K3 w - - 0 1',
      moverColor: 'w',
      lineUci: <String>['a1a6', 'b7a6', 'c3g7', 'e8d7', 'e1d2'],
    );

    expect(r, isNotNull);
    expect(r!.isSacrifice, isTrue);
    expect(r.maxDeficit, 5);
    expect(r.netGain, 4);
    expect(r.recoveredWithSurplus, isTrue);
  });

  test('تضحية لا تُسترد: ليست بريلينت', () {
    // 1.Ra6 bxa6 2.Kd2 Kd7
    final r = analyzeSacrificeLine(
      fenBefore: '4k3/1p6/8/8/8/8/8/R3K3 w - - 0 1',
      moverColor: 'w',
      lineUci: <String>['a1a6', 'b7a6', 'e1d2', 'e8d7'],
    );

    expect(r, isNotNull);
    expect(r!.isSacrifice, isTrue);
    expect(r.netGain, -5);
    expect(r.recoveredWithSurplus, isFalse);
  });

  test('تبادل متكافئ ليس تضحية', () {
    // 1.Nxd5 exd5 2.Kd2 Kd7
    final r = analyzeSacrificeLine(
      fenBefore: '4k3/8/4p3/3n4/8/2N5/8/4K3 w - - 0 1',
      moverColor: 'w',
      lineUci: <String>['c3d5', 'e6d5', 'e1d2', 'e8d7'],
    );

    expect(r, isNotNull);
    expect(r!.isSacrifice, isFalse);
    expect(r.recoveredWithSurplus, isFalse);
  });

  test('خط أقصر من 3 أنصاف نقلات بلا مات => null', () {
    final r = analyzeSacrificeLine(
      fenBefore: '4k3/1p6/8/8/8/8/8/R3K3 w - - 0 1',
      moverColor: 'w',
      lineUci: <String>['a1a6', 'b7a6'],
    );

    expect(r, isNull);
  });

  test('نقلة غير قانونية توقف المحاكاة بأمان', () {
    final r = analyzeSacrificeLine(
      fenBefore: '4k3/1p6/8/8/8/8/8/R3K3 w - - 0 1',
      moverColor: 'w',
      lineUci: <String>['a1a9', 'b7a6'],
    );

    expect(r, isNull);
  });
}
