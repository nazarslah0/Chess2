import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:chess_analyzer/engine_service.dart';
import 'package:chess_analyzer/engine_transport.dart';

/// محرك UCI وهمي يحاكي سلوك Stockfish الفعلي:
///  - uci → uciok، isready → readyok.
///  - stop أثناء بحث → يصدر bestmove للبحث الموقوف (قبل أي أمر لاحق).
///  - go لا يردّ تلقائيًا: يتحكم الاختبار بالمخرجات.
class FakeTransport implements EngineTransport {
  final StreamController<String> _out = StreamController<String>.broadcast();

  final List<String> sent = <String>[];

  /// bestmove الذي يصدره المحرك عند stop لبحث جارٍ (بالترتيب).
  final List<String> stopReplies = <String>[];

  bool searching = false;

  /// true (الافتراضي): عند stop يصدر bestmove فورًا كما يفعل Stockfish.
  /// false: لا يصدر شيئًا، ويطلق الاختبار bestmove المتأخر يدويًا
  /// (لمحاكاة وصوله بعد أن بدأ التحليل الجديد).
  bool autoReplyOnStop = true;

  @override
  Stream<String> get output => _out.stream;

  @override
  Future<bool> start() async => true;

  void emit(String line) {
    scheduleMicrotask(() {
      if (!_out.isClosed) _out.add(line);
    });
  }

  @override
  Future<void> send(String command) async {
    sent.add(command);

    if (command == 'uci') {
      emit('uciok');
    } else if (command == 'isready') {
      emit('readyok');
    } else if (command.startsWith('go')) {
      searching = true;
    } else if (command == 'stop') {
      if (searching) {
        searching = false;

        if (!autoReplyOnStop) return;

        final reply =
            stopReplies.isNotEmpty ? stopReplies.removeAt(0) : 'a2a3';

        emit('bestmove $reply');
      }
    }
  }

  @override
  Future<void> dispose() async {
    await _out.close();
  }

  int get goCount => sent.where((c) => c.startsWith('go')).length;

  List<String> get positions =>
      sent.where((c) => c.startsWith('position')).toList();
}

const String fenWhite =
    'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
const String fenBlack =
    'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1';
const String fenC = '4k3/8/8/8/8/8/4P3/4K3 w - - 0 1';

Future<void> pump() async {
  // يسمح لأحداث microtask بالوصول إلى المحرك.
  await Future<void>.delayed(const Duration(milliseconds: 5));
}

Future<(EngineService, FakeTransport)> startEngine() async {
  final t = FakeTransport();
  final e = EngineService(transport: t);

  await e.init();

  var waited = 0;
  while (!e.ready && waited < 2000) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    waited += 5;
  }

  expect(e.ready, isTrue);

  return (e, t);
}

void main() {
  group('عزل الجلسات', () {
    test('السيناريو الأساسي: #10 يُوقف ثم #11 — bestmove المتأخر يُتجاهل',
        () async {
      final (e, t) = await startEngine();

      final bestMoves = <String>[];
      final bestRequests = <AnalysisRequest>[];

      e.onBestMoveFor = (req, uci) {
        bestMoves.add(uci);
        bestRequests.add(req);
      };

      // bestmove الموقوف يصل متأخرًا، بعد أن يبدأ #11.
      t.autoReplyOnStop = false;

      final r10 = await e.analyze(fenWhite, depth: 10, multiPv: 1);
      expect(r10, isNotNull);

      // #10 يُوقف ثم #11 يبدأ.
      await e.stop();
      final r11 = await e.analyze(fenBlack, depth: 10, multiPv: 1);

      expect(r11!.id, greaterThan(r10!.id));

      // bestmove المتأخر لـ #10 يصل الآن (بعد أن بدأ #11).
      t.emit('bestmove e2e4');
      await pump();

      expect(bestMoves, isEmpty,
          reason: 'bestmove قديم لا يجوز أن يصل إلى التحليل الجديد');

      // bestmove الخاص بـ #11.
      t.emit('bestmove e7e5');
      await pump();

      expect(bestMoves, ['e7e5']);
      expect(bestRequests.single.id, r11.id);
      expect(bestRequests.single.fen, fenBlack);

      await e.dispose();
    });

    test('analyze جديد مباشرة بدون stop: stop يُرسل والقديم يُتجاهل',
        () async {
      final (e, t) = await startEngine();

      final bestMoves = <String>[];
      e.onBestMove = bestMoves.add;

      t.stopReplies.add('d2d4'); // bestmove البحث الأول عند stop.

      await e.analyze(fenWhite, depth: 12, multiPv: 1);
      await e.analyze(fenBlack, depth: 12, multiPv: 1);
      await pump();

      expect(t.sent.contains('stop'), isTrue);
      expect(bestMoves, isEmpty,
          reason: 'bestmove الناتج عن stop يخص البحث الأول فقط');

      t.emit('bestmove g8f6');
      await pump();

      expect(bestMoves, ['g8f6']);

      await e.dispose();
    });

    test('أسطر info القديمة لا تدخل في التحليل الجديد', () async {
      final (e, t) = await startEngine();

      final infos = <(String fen, int multipv, double eval)>[];

      e.onInfoFor = (req, multipv, line) {
        infos.add((req.fen, multipv, line.evalPawns));
      };

      // لا نريد أن يُصدر stop أي bestmove تلقائي هنا.
      await e.analyze(fenWhite, depth: 12, multiPv: 1);

      // التحليل الثاني يبدأ، وأقدم بحث لم ينتهِ بعد في المحرك.
      // (نمنع الرد التلقائي على stop لنحاكي تأخره.)
      t.searching = false;
      await e.analyze(fenBlack, depth: 12, multiPv: 1);

      // مخرجات البحث الأول القديمة (من منظور الأبيض +0.30).
      t.emit('info depth 8 multipv 1 score cp 30 pv e2e4 e7e5');
      await pump();

      expect(infos, isEmpty,
          reason: 'info قديم يُرفض ما دام bestmove القديم لم يصل');

      // وصل bestmove القديم → يُستهلك.
      t.emit('bestmove e2e4');
      await pump();

      // الآن info الخاص بالتحليل الجديد (الأسود يلعب: +40 للأسود).
      t.emit('info depth 9 multipv 1 score cp 40 pv e7e5 g1f3');
      await pump();

      expect(infos.length, 1);
      expect(infos.single.$1, fenBlack);
      // الدور للأسود: +0.40 من منظوره = -0.40 من منظور الأبيض.
      expect(infos.single.$3, closeTo(-0.40, 1e-9));

      await e.dispose();
    });

    test('stop ثم بدء: لا يتأثر الطلب الجديد بـ bestmove الموقوف',
        () async {
      final (e, t) = await startEngine();

      final bestMoves = <String>[];
      e.onBestMove = bestMoves.add;

      t.stopReplies.add('b1c3');

      await e.analyze(fenWhite, depth: 20, multiPv: 1);
      await e.stop();
      await pump();

      expect(e.analyzing, isFalse);
      expect(bestMoves, isEmpty, reason: 'نتيجة الموقوف لا تُعرض');

      await e.analyze(fenC, depth: 20, multiPv: 1);

      t.emit('bestmove e2e4');
      await pump();

      expect(bestMoves, ['e2e4']);
      expect(e.analyzing, isFalse);

      await e.dispose();
    });

    test('تحليل جديد بعد اكتمال السابق بشكل طبيعي', () async {
      final (e, t) = await startEngine();

      final bestMoves = <String>[];
      e.onBestMove = bestMoves.add;

      await e.analyze(fenWhite, depth: 10, multiPv: 1);
      t.emit('bestmove e2e4');
      await pump();

      expect(bestMoves, ['e2e4']);

      t.searching = false;

      await e.analyze(fenBlack, depth: 10, multiPv: 1);
      t.emit('bestmove c7c5');
      await pump();

      expect(bestMoves, ['e2e4', 'c7c5']);
      // لم يكن هناك بحث جارٍ، فلا حاجة لـ stop.
      expect(t.sent.contains('stop'), isFalse);

      await e.dispose();
    });

    test('طلب تجاوزه طلب أحدث أثناء الانتظار لا يرسل go', () async {
      final (e, t) = await startEngine();

      final f1 = e.analyze(fenWhite, depth: 10, multiPv: 1);
      final f2 = e.analyze(fenC, depth: 10, multiPv: 1);

      final r1 = await f1;
      final r2 = await f2;

      expect(r1, isNotNull);
      expect(r2, isNotNull);
      expect(t.goCount, 1, reason: 'go واحد فقط للطلب الأحدث');
      expect(t.positions.last, 'position fen $fenC');
      expect(e.currentRequest!.id, r2!.id);

      await e.dispose();
    });

    test('stop أثناء انتظار readyok يمنع إرسال go', () async {
      final (e, t) = await startEngine();

      final f = e.analyze(fenWhite, depth: 10, multiPv: 1);

      await e.stop();
      await f;
      await pump();

      expect(t.goCount, 0);

      await e.dispose();
    });

    test('هوية الطلب تحمل fen وdepth وmultipv وply', () async {
      final (e, _) = await startEngine();

      final r = await e.analyze(
        fenWhite,
        depth: 14,
        multiPv: 3,
        ply: 7,
      );

      expect(r!.fen, fenWhite);
      expect(r.depth, 14);
      expect(r.multiPv, 3);
      expect(r.ply, 7);
      expect(r.startedAt, isNotNull);

      await e.dispose();
    });

    test('bestmove بلا بحث جارٍ يُتجاهل', () async {
      final (e, t) = await startEngine();

      final bestMoves = <String>[];
      e.onBestMove = bestMoves.add;

      t.emit('bestmove e2e4');
      await pump();

      expect(bestMoves, isEmpty);

      await e.dispose();
    });
  });

  group('parseInfoLine', () {
    test('تحويل التقييم إلى منظور الأبيض', () {
      final w = EngineService.parseInfoLine(
        'info depth 10 multipv 1 score cp 50 pv e2e4',
        fenWhite,
      )!;

      expect(w.line.evalPawns, closeTo(0.5, 1e-9));
      expect(w.line.evalLabel, '+0.50');

      final b = EngineService.parseInfoLine(
        'info depth 10 multipv 1 score cp 50 pv e7e5',
        fenBlack,
      )!;

      expect(b.line.evalPawns, closeTo(-0.5, 1e-9));
      expect(b.line.evalLabel, '-0.50');
    });

    test('المات', () {
      final w = EngineService.parseInfoLine(
        'info depth 10 multipv 2 score mate 3 pv e2e4',
        fenWhite,
      )!;

      expect(w.multipv, 2);
      expect(w.line.evalLabel, 'M3');
      expect(w.line.evalPawns, 100.0);

      final b = EngineService.parseInfoLine(
        'info depth 10 multipv 1 score mate 3 pv e7e5',
        fenBlack,
      )!;

      expect(b.line.evalLabel, 'M-3');
      expect(b.line.evalPawns, -100.0);
    });

    test('تقييم حدّي (lowerbound/upperbound) يُهمل', () {
      expect(
        EngineService.parseInfoLine(
          'info depth 10 score cp 50 lowerbound pv e2e4',
          fenWhite,
        ),
        isNull,
      );

      expect(
        EngineService.parseInfoLine(
          'info depth 10 score cp 50 upperbound pv e2e4',
          fenWhite,
        ),
        isNull,
      );
    });

    test('أسطر بلا عمق أو تقييم أو pv تُهمل', () {
      expect(
        EngineService.parseInfoLine('info string NNUE evaluation', fenWhite),
        isNull,
      );

      expect(
        EngineService.parseInfoLine(
          'info depth 5 score cp 10',
          fenWhite,
        ),
        isNull,
      );
    });

    test('يحتفظ بخط PV كاملًا', () {
      final p = EngineService.parseInfoLine(
        'info depth 12 multipv 1 score cp 20 pv e2e4 e7e5 g1f3',
        fenWhite,
      )!;

      expect(p.line.uciMoves, ['e2e4', 'e7e5', 'g1f3']);
      expect(p.line.depth, 12);
    });
  });
}
