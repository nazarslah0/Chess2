import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_analyzer/analysis_cache.dart';
import 'package:chess_analyzer/analysis_controller.dart';
import 'package:chess_analyzer/engine_service.dart';
import 'package:chess_analyzer/engine_transport.dart';

/// محرك UCI وهمي: يردّ على كل `go` بسطري info ثم bestmove.
class ScriptedTransport implements EngineTransport {
  final StreamController<String> _out = StreamController<String>.broadcast();

  final List<String> sent = <String>[];

  @override
  Stream<String> get output => _out.stream;

  @override
  Future<bool> start() async => true;

  void _emit(String line) {
    scheduleMicrotask(() {
      if (!_out.isClosed) _out.add(line);
    });
  }

  @override
  Future<void> send(String command) async {
    sent.add(command);

    if (command == 'uci') {
      _emit('uciok');
    } else if (command == 'isready') {
      _emit('readyok');
    } else if (command.startsWith('go')) {
      _emit('info depth 14 multipv 1 score cp 20 pv e2e4 e7e5');
      _emit('info depth 14 multipv 2 score cp 5 pv d2d4 d7d5');
      _emit('bestmove e2e4');
    }
  }

  @override
  Future<void> dispose() async {
    await _out.close();
  }

  int get goCount => sent.where((c) => c.startsWith('go')).length;
}

const String pgn = '''
[Event "T"]
[White "A"]
[Black "B"]
[Result "*"]

1. e4 e5 2. Nf3 Nc6 *
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late AnalysisCache cache;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    dir = Directory.systemTemp.createTempSync('chess2_ctrl_test_');
    cache = AnalysisCache(directoryProvider: () async => dir);
  });

  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('تحليل كامل ثم فتح المباراة ثانية من الكاش بلا Stockfish', () async {
    // --- المرة الأولى: يعمل المحرك ويُحفظ التحليل ---
    final t1 = ScriptedTransport();

    final c1 = GameAnalysisController(
      pgn: pgn,
      engine: EngineService(transport: t1),
      cache: cache,
    );

    await c1.start();

    expect(c1.parseError, isNull);
    expect(c1.analyzing, isFalse);
    expect(c1.servedFromCache, isFalse);
    expect(t1.goCount, 5, reason: '4 نقلات = 5 وضعيات');
    expect(c1.results.length, 4);
    expect(c1.qualities.length, 4);
    expect(c1.analysis, isNotNull);
    expect(c1.analysis!.isConsistent, isTrue);
    expect(c1.progress, 1);

    final qualities1 = List.of(c1.qualities);
    final evals1 = List.of(c1.evalPawns);

    c1.dispose();

    // --- إغلاق وإعادة فتح: الذاكرة تُفرَّغ، يبقى القرص فقط ---
    cache.clearMemory();

    final t2 = ScriptedTransport();

    final c2 = GameAnalysisController(
      pgn: pgn,
      engine: EngineService(transport: t2),
      cache: cache,
    );

    await c2.start();

    expect(c2.servedFromCache, isTrue);
    expect(c2.analyzing, isFalse);
    expect(t2.sent, isEmpty,
        reason: 'لا يجوز تشغيل Stockfish إذا كان التحليل المحفوظ صالحًا');
    expect(c2.qualities, qualities1);
    expect(c2.evalPawns, evals1);
    expect(c2.results.length, 4);

    c2.dispose();
  });

  test('عمق مختلف => لا يُستخدم التحليل القديم', () async {
    final t1 = ScriptedTransport();

    final c1 = GameAnalysisController(
      pgn: pgn,
      depth: 14,
      engine: EngineService(transport: t1),
      cache: cache,
    );

    await c1.start();
    c1.dispose();

    final t2 = ScriptedTransport();

    final c2 = GameAnalysisController(
      pgn: pgn,
      depth: 20,
      engine: EngineService(transport: t2),
      cache: cache,
    );

    await c2.start();

    expect(c2.servedFromCache, isFalse);
    expect(t2.goCount, 5);

    c2.dispose();
  });

  test('PGN غير صالح: خطأ قراءة بلا تحليل', () async {
    final t = ScriptedTransport();

    final c = GameAnalysisController(
      pgn: '1. e4 e4 *',
      engine: EngineService(transport: t),
      cache: cache,
    );

    expect(c.parseError, isNotNull);

    await c.start();

    expect(t.sent, isEmpty);
    expect(c.analyzing, isFalse);

    c.dispose();
  });

  test('كل MoveAnalysisResult يطابق جداول المتحكم', () async {
    final c = GameAnalysisController(
      pgn: pgn,
      engine: EngineService(transport: ScriptedTransport()),
      cache: cache,
    );

    await c.start();

    for (var i = 0; i < c.results.length; i++) {
      final r = c.results[i];

      expect(r.ply, i);
      expect(r.classification, c.qualities[i]);
      expect(r.fenBefore, c.fens[i]);
      expect(r.fenAfter, c.fens[i + 1]);
      expect(r.evaluationBeforeWhiteCp, c.cpAt(i));
      expect(r.evaluationAfterWhiteCp, c.cpAt(i + 1));
      expect(r.evaluationLossCp, c.lossAt(i));
      expect(r.bestMoveUci, c.bestUci[i]);
    }

    c.dispose();
  });
}
