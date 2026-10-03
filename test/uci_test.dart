import 'package:flutter_test/flutter_test.dart';

import 'package:chess_analyzer/uci_utils.dart';

void main() {
  group('parseUci', () {
    test('نقلة عادية', () {
      final m = parseUci('e2e4')!;

      expect(m.from, 'e2');
      expect(m.to, 'e4');
      expect(m.promotion, isNull);
      expect(m.uci, 'e2e4');
    });

    test('التبييت يُقرأ كنقلة ملك عادية', () {
      for (final u in ['e1g1', 'e1c1', 'e8g8', 'e8c8']) {
        final m = parseUci(u)!;

        expect(m.from, u.substring(0, 2));
        expect(m.to, u.substring(2, 4));
        expect(m.promotion, isNull);
      }
    });

    test('الترقية بكل القطع', () {
      for (final p in ['q', 'r', 'b', 'n']) {
        final m = parseUci('a7a8$p')!;

        expect(m.from, 'a7');
        expect(m.to, 'a8');
        expect(m.promotion, p);
      }

      expect(parseUci('e7e8q')!.promotion, 'q');
    });

    test('حرف الترقية الكبير يُوحَّد', () {
      expect(parseUci('a7a8Q')!.promotion, 'q');
    });

    test('نص غير صالح يعيد null', () {
      expect(parseUci(null), isNull);
      expect(parseUci(''), isNull);
      expect(parseUci('e2'), isNull);
      expect(parseUci('e2e'), isNull);
      expect(parseUci('e2e4qq'), isNull);
      expect(parseUci('i2e4'), isNull);
      expect(parseUci('e9e4'), isNull);
      expect(parseUci('a7a8k'), isNull);
      expect(parseUci('(none)'), isNull);
    });
  });

  group('isSameUciMove', () {
    test('نفس النقلة', () {
      expect(isSameUciMove('e2e4', 'e2e4'), isTrue);
      expect(isSameUciMove('e2e4', ' e2e4 '), isTrue);
    });

    test('نقلتان مختلفتان', () {
      expect(isSameUciMove('e2e4', 'e2e3'), isFalse);
      expect(isSameUciMove('g1f3', 'f3g1'), isFalse);
    });

    test('الترقيات المختلفة ليست نفس النقلة', () {
      expect(isSameUciMove('a7a8q', 'a7a8n'), isFalse);
      expect(isSameUciMove('a7a8q', 'a7a8q'), isTrue);
      expect(isSameUciMove('a7a8q', 'A7A8Q'), isTrue);
    });

    test('ترقية وغير ترقية ليستا متطابقتين', () {
      expect(isSameUciMove('a7a8', 'a7a8q'), isFalse);
    });

    test('أي طرف غير صالح => false', () {
      expect(isSameUciMove(null, 'e2e4'), isFalse);
      expect(isSameUciMove('e2e4', null), isFalse);
      expect(isSameUciMove('xx', 'xx'), isFalse);
    });
  });

  group('firstValidUci', () {
    test('أول نقلة صالحة', () {
      expect(firstValidUci(['e2e4', 'e7e5'])!.uci, 'e2e4');
    });

    test('أول عنصر غير صالح يقطع الخط', () {
      expect(firstValidUci(['zz', 'e7e5']), isNull);
      expect(firstValidUci(const <String>[]), isNull);
    });
  });
}
