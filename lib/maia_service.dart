import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:lc0/lc0.dart';
import 'package:path_provider/path_provider.dart';

// ================================================================
// Maia: شبكات عصبية تتنبأ بما يلعبه البشر حسب التصنيف.
//
// لا نستخدمها للبحث: تمريرة واحدة (go nodes 1) تعطي احتمال كل نقلة
// قانونية عند لاعب بذلك التصنيف. تُشغَّل عبر حزمة lc0 (Dart FFI) على
// المعالج فقط. أي فشل (ملف أوزان ناقص، تعذّر تشغيل المحرك...) يعيد
// null ويتخطى المستدعي Maia بصمت.
//
// الأوزان تُوضع في assets/maia/ (انظر README.txt هناك).
// ================================================================

class MaiaService {
  MaiaService._();

  /// المستويات المضمّنة. أي تصنيف يُقرَّب لأقربها.
  static const List<int> buckets = <int>[1100, 1500, 1900];

  /// النقلة الأفضل تُرفع إلى "رائعة" إذا وجدها أقل من هذه النسبة من
  /// اللاعبين بتصنيف اللاعب (0.10 = 10%).
  static const double greatMaxProb = 0.10;

  /// وكان تفوقها على ثاني أفضل نقلة (باحتمال الفوز %) لا يقل عن هذا،
  /// كي لا تُرفع نقلة لمجرد أنها واحدة من عدة بدائل متكافئة.
  static const double greatMinGapWinPct = 7;

  static int bucketForElo(int? elo) {
    if (elo == null || elo <= 0) return 1500;

    var best = buckets.first;

    for (final b in buckets) {
      if ((b - elo).abs() < (best - elo).abs()) best = b;
    }

    return best;
  }

  static String assetPath(int bucket) =>
      'assets/maia/maia-$bucket.pb.gz';

  /// ينسخ ملف الأوزان من الـ assets إلى مجلد التطبيق (lc0 يحتاج مسار
  /// ملف حقيقي). يعيد null إن لم يكن الملف مضمَّنًا.
  static Future<String?> _materialize(int bucket) async {
    try {
      final data = await rootBundle.load(assetPath(bucket));

      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );

      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/maia/maia-$bucket.pb.gz');

      if (await file.exists() && await file.length() == bytes.length) {
        return file.path;
      }

      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);

      return file.path;
    } catch (_) {
      return null;
    }
  }
}

/// جلسة Maia واحدة بأوزان مستوى واحد. lc0 يسمح بمحرك واحد حي في كل
/// وقت، فأغلق الجلسة قبل فتح أخرى.
class MaiaSession {
  final Lc0 _engine;

  StreamSubscription<String>? _sub;
  void Function(String line)? _onLine;

  MaiaSession._(this._engine);

  static final RegExp _moveLine = RegExp(
    r'info string (\S+)\s+\(\s*\d+\s*\)\s+N:.*?\(P:\s*([\d.]+)%\)',
  );

  static Future<MaiaSession?> open(int bucket) async {
    final path = await MaiaService._materialize(bucket);

    if (path == null) return null;

    Lc0? engine;

    try {
      engine = await Lc0.create();

      final session = MaiaSession._(engine);

      session._sub = engine.stdout.listen(session._dispatch);

      engine.stdin = 'setoption name WeightsFile value $path';
      engine.stdin = 'setoption name VerboseMoveStats value true';
      engine.stdin = 'setoption name Threads value 1';

      final ready = Completer<bool>();

      session._onLine = (line) {
        if (line == 'readyok' && !ready.isCompleted) {
          ready.complete(true);
        }
      };

      engine.stdin = 'isready';

      final ok = await ready.future.timeout(
        const Duration(seconds: 25),
        onTimeout: () => false,
      );

      session._onLine = null;

      if (!ok) {
        await session.close();
        return null;
      }

      return session;
    } catch (_) {
      try {
        await engine?.dispose();
      } catch (_) {}

      return null;
    }
  }

  void _dispatch(String line) => _onLine?.call(line.trim());

  /// احتمال كل نقلة (UCI → 0..1) عند لاعب هذا المستوى. نمرّر كل
  /// نقلات المباراة السابقة (وليس FEN فقط) لأن Maia دُرِّبت على
  /// وضعيات مع تاريخها، فدقتها أعلى معها.
  Future<Map<String, double>?> policy({
    required String startFen,
    required List<String> movesUci,
  }) async {
    final result = <String, double>{};
    final done = Completer<bool>();

    _onLine = (line) {
      final m = _moveLine.firstMatch(line);

      if (m != null) {
        result[m.group(1)!] =
            (double.tryParse(m.group(2)!) ?? 0) / 100.0;
        return;
      }

      if (line.startsWith('bestmove') && !done.isCompleted) {
        done.complete(true);
      }
    };

    try {
      _engine.stdin = 'position fen $startFen'
          '${movesUci.isEmpty ? '' : ' moves ${movesUci.join(' ')}'}';
      _engine.stdin = 'go nodes 1';

      final ok = await done.future.timeout(
        const Duration(seconds: 6),
        onTimeout: () => false,
      );

      return ok && result.isNotEmpty ? result : null;
    } catch (_) {
      return null;
    } finally {
      _onLine = null;
    }
  }

  Future<void> close() async {
    try {
      await _sub?.cancel();
    } catch (_) {}

    _sub = null;

    try {
      await _engine.dispose();
    } catch (_) {}
  }
}
