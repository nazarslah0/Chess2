import 'dart:async';
import 'dart:collection';

import 'engine_transport.dart';

/// نتيجة سطر واحد من MultiPV صادر من Stockfish.
///
/// مثال:
/// depth 18
/// eval +0.42
/// pv e2e4 e7e5 g1f3 ...
class PvLine {
  final int depth;
  final double evalPawns;
  final String evalLabel;
  final List<String> uciMoves;

  const PvLine({
    required this.depth,
    required this.evalPawns,
    required this.evalLabel,
    required this.uciMoves,
  });
}

/// هوية طلب تحليل واحد. كل `analyze()` ينشئ طلبًا جديدًا بمعرّف
/// فريد، وكل نتيجة (info / bestmove) لا تُقبل إلا إذا كانت تخص
/// الطلب الحالي نفسه.
class AnalysisRequest {
  /// معرّف تصاعدي فريد داخل هذه النسخة من [EngineService].
  final int id;

  final String fen;
  final int depth;
  final int multiPv;
  final int? movetimeMs;

  /// رقم نصف النقلة في المباراة (اختياري، يحدده المستدعي).
  final int? ply;

  final DateTime startedAt;

  AnalysisRequest({
    required this.id,
    required this.fen,
    required this.depth,
    required this.multiPv,
    this.movetimeMs,
    this.ply,
  }) : startedAt = DateTime.now();

  @override
  String toString() =>
      'AnalysisRequest(#$id ply=$ply depth=$depth multipv=$multiPv)';
}

/// خدمة Stockfish.
///
/// ضمان عزل الجلسات (لا يصل bestmove قديم إلى تحليل جديد):
///
/// 1. كل أمر `go` نرسله يُسجَّل في طابور FIFO ([_pending]) مع الطلب
///    [AnalysisRequest] الذي أرسله. UCI يردّ على كل `go` بـ`bestmove`
///    واحد بالضبط وبنفس ترتيب الإرسال، فكل `bestmove` يصل يُنسب إلى
///    أقدم عنصر في الطابور.
/// 2. [_current] هو الطلب الحالي الوحيد المسموح بقبول نتائجه. أي
///    `analyze()` أو `stop()` جديد يغيّره (أو يمسحه) فورًا، فيصبح كل ما
///    يخص الطلبات السابقة قديمًا.
/// 3. `bestmove` يُقبل فقط إذا كان الطلب المنسوب إليه هو [_current].
///    وإلا يُستهلك من الطابور ويُتجاهل.
/// 4. أسطر `info` تُقبل فقط ما دام أقدم عنصر في الطابور هو
///    [_current]؛ أي أن أي بحث أقدم لا يزال يُنهي عمله لا تدخل
///    مخرجاته في الطلب الجديد. ويُحسب لون الدور من FEN الطلب نفسه
///    وليس من آخر FEN طُلب.
/// 5. لا نرسل `go` لطلب تجاوزه طلب أحدث أثناء انتظار `readyok`.
class EngineService {
  EngineService({EngineTransport? transport})
      : _transport = transport ?? PlatformEngineTransport();

  final EngineTransport _transport;

  // ============================================================
  // State
  // ============================================================

  StreamSubscription<String>? _outputSubscription;

  bool ready = false;

  /// true ما دام الطلب الحالي يبحث (من بدايته حتى bestmove الخاص به
  /// أو حتى إيقافه).
  bool analyzing = false;

  bool _starting = false;
  bool _disposed = false;

  int _nextId = 0;

  /// الطلب الحالي الوحيد الذي تُقبل نتائجه. null = لا شيء مقبول.
  AnalysisRequest? _current;

  /// طلبات أُرسل لها `go` ولم يصل `bestmove` الخاص بها بعد.
  final Queue<AnalysisRequest> _pending = Queue<AnalysisRequest>();

  /// منتظرو `readyok` أثناء التحليل (مزامنة حقيقية مع المحرك).
  final Queue<Completer<void>> _syncWaiters = Queue<Completer<void>>();

  Completer<void>? _readyCompleter;

  /// الطلب الحالي (للقراءة فقط).
  AnalysisRequest? get currentRequest => _current;

  /// عدد أوامر `go` التي لم يصلها bestmove بعد (للاختبار والتشخيص).
  int get pendingSearches => _pending.length;

  // ============================================================
  // Callbacks
  // ============================================================

  void Function(String status)? onStatus;

  void Function(int multipv, PvLine line)? onInfo;

  void Function(String bestUci)? onBestMove;

  /// نسخ تحمل هوية الطلب، لمن يريد التحقق من مطابقة FEN/ply.
  void Function(AnalysisRequest request, int multipv, PvLine line)?
      onInfoFor;

  void Function(AnalysisRequest request, String bestUci)? onBestMoveFor;

  // ============================================================
  // Initialization
  // ============================================================

  Future<void> init() async {
    if (_disposed) {
      return;
    }

    if (ready) {
      onStatus?.call('🟢 Stockfish جاهز');
      return;
    }

    if (_starting) {
      return;
    }

    _starting = true;

    onStatus?.call('🟡 جاري تشغيل Stockfish 19...');

    try {
      await _outputSubscription?.cancel();

      _outputSubscription = _transport.output.listen(
        _handleLine,
        onError: (Object error) {
          ready = false;
          analyzing = false;
          _starting = false;
          _current = null;

          final completer = _readyCompleter;
          if (completer != null && !completer.isCompleted) {
            completer.completeError(error);
          }

          onStatus?.call('🔴 خطأ في اتصال Stockfish: $error');
        },
        onDone: () {
          if (!_disposed) {
            ready = false;
            analyzing = false;
            _current = null;

            onStatus?.call('🟡 تم إغلاق Stockfish');
          }
        },
        cancelOnError: false,
      );

      final started = await _transport.start();

      if (!started) {
        ready = false;
        _starting = false;

        onStatus?.call('🔴 فشل تشغيل Stockfish 19');

        return;
      }

      // إعطاء الجسر وقتًا لفتح العملية.
      await Future<void>.delayed(const Duration(milliseconds: 100));

      await _send('uci');

      _starting = false;
    } catch (e) {
      ready = false;
      analyzing = false;
      _starting = false;

      onStatus?.call('🔴 فشل تشغيل Stockfish 19: $e');
    }
  }

  // ============================================================
  // Send command to Stockfish
  // ============================================================

  Future<void> _send(String command) async {
    if (_disposed) {
      return;
    }

    try {
      await _transport.send(command);
    } catch (e) {
      onStatus?.call('🔴 فشل إرسال أمر Stockfish: $e');
    }
  }

  /// مزامنة حقيقية: نرسل `isready` وننتظر `readyok` المقابل له بالذات
  /// (وليس أي readyok سابق). المنتظرون يبقون في الطابور حتى لو انتهت
  /// مهلتهم، كي يمتص كل منهم readyok الخاص به ولا ينزاح الترتيب.
  Future<bool> _sync({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final waiter = Completer<void>();

    _syncWaiters.addLast(waiter);

    await _send('isready');

    try {
      await waiter.future.timeout(timeout);

      return !_disposed;
    } catch (_) {
      return false;
    }
  }

  // ============================================================
  // Stockfish output parser
  // ============================================================

  void _handleLine(String raw) {
    if (_disposed) {
      return;
    }

    final line = raw.trim();

    if (line.isEmpty) {
      return;
    }

    if (line.startsWith('id ') ||
        line.startsWith('option ') ||
        line == 'uciok') {
      if (line == 'uciok') {
        _onUciReady();
      }

      return;
    }

    if (line == 'readyok') {
      _onReadyOk();
      return;
    }

    if (line.startsWith('info ')) {
      _onInfoLine(line);
      return;
    }

    if (line.startsWith('bestmove')) {
      _onBestMoveLine(line);
      return;
    }
  }

  void _onUciReady() {
    onStatus?.call('🟡 Stockfish 19 متصل...');

    // بعد uciok يجب انتظار readyok قبل إرسال position/go.
    _readyCompleter ??= Completer<void>();
    _send('isready');
  }

  void _onReadyOk() {
    // readyok خاص بمزامنة أثناء التحليل.
    if (_syncWaiters.isNotEmpty) {
      final waiter = _syncWaiters.removeFirst();

      if (!waiter.isCompleted) {
        waiter.complete();
      }

      return;
    }

    // readyok الخاص بالتهيئة الأولى.
    ready = true;
    _starting = false;

    final completer = _readyCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }

    onStatus?.call('🟢 Stockfish 19 جاهز');
  }

  Future<bool> _waitUntilReady({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (ready) {
      return true;
    }

    _readyCompleter ??= Completer<void>();

    try {
      await _readyCompleter!.future.timeout(timeout);
      return ready;
    } catch (_) {
      return ready;
    }
  }

  // ============================================================
  // bestmove
  // ============================================================

  void _onBestMoveLine(String line) {
    // كل bestmove ينتمي لأقدم go لم يُجَب بعد.
    if (_pending.isEmpty) {
      return;
    }

    final request = _pending.removeFirst();

    // قديم: أُلغي أو تجاوزه طلب أحدث → يُستهلك ويُتجاهل.
    if (!identical(request, _current)) {
      return;
    }

    final parts = line.split(RegExp(r'\s+'));

    final bestMove = parts.length >= 2 ? parts[1].trim() : '';

    analyzing = false;
    _current = null;

    if (bestMove.isEmpty || bestMove == '(none)') {
      onStatus?.call('🟡 لا توجد نقلة');
      return;
    }

    onBestMove?.call(bestMove);
    onBestMoveFor?.call(request, bestMove);

    onStatus?.call('🟢 اكتمل التحليل');
  }

  // ============================================================
  // info
  // ============================================================

  void _onInfoLine(String line) {
    if (_pending.isEmpty) {
      return;
    }

    final request = _pending.first;

    // أقدم بحث لم ينتهِ ليس الطلب الحالي → هذه مخرجات قديمة.
    if (!identical(request, _current)) {
      return;
    }

    final parsed = parseInfoLine(line, request.fen);

    if (parsed == null) {
      return;
    }

    onInfo?.call(parsed.multipv, parsed.line);
    onInfoFor?.call(request, parsed.multipv, parsed.line);
  }

  /// يحلّل سطر `info` من Stockfish إلى (multipv، PvLine) بتقييم من
  /// منظور الأبيض. يعيد null للأسطر غير المفيدة (بلا عمق/تقييم/PV،
  /// أو تقييم حدّي lowerbound/upperbound غير نهائي).
  ///
  /// تقييم Stockfish دائمًا من منظور اللاعب الذي عليه الدور؛ نحوّله
  /// لمنظور الأبيض اعتمادًا على [fen] الخاص بالطلب.
  static ({int multipv, PvLine line})? parseInfoLine(
    String line,
    String fen,
  ) {
    final parts = line.trim().split(RegExp(r'\s+'));

    if (parts.contains('lowerbound') || parts.contains('upperbound')) {
      return null;
    }

    int? depth;
    int multipv = 1;

    String? scoreType;
    int? scoreValue;

    final List<String> pv = <String>[];

    for (int i = 0; i < parts.length; i++) {
      final part = parts[i];

      if (part == 'depth' && i + 1 < parts.length) {
        depth = int.tryParse(parts[i + 1]);
      }

      if (part == 'multipv' && i + 1 < parts.length) {
        multipv = int.tryParse(parts[i + 1]) ?? 1;
      }

      if (part == 'score' && i + 2 < parts.length) {
        final type = parts[i + 1];
        final value = int.tryParse(parts[i + 2]);

        if (type == 'cp' || type == 'mate') {
          scoreType = type;
          scoreValue = value;
        }
      }

      if (part == 'pv' && i + 1 < parts.length) {
        pv.addAll(parts.sublist(i + 1));

        break;
      }
    }

    if (depth == null || scoreType == null || scoreValue == null) {
      return null;
    }

    if (pv.isEmpty) {
      return null;
    }

    final fenParts = fen.trim().split(RegExp(r'\s+'));

    final sideToMove = fenParts.length > 1 ? fenParts[1] : 'w';

    final sign = sideToMove == 'w' ? 1 : -1;

    double evalPawns;
    String evalLabel;

    if (scoreType == 'mate') {
      final mate = scoreValue * sign;

      if (mate > 0) {
        evalLabel = 'M${mate.abs()}';
        evalPawns = 100.0;
      } else {
        evalLabel = 'M-${mate.abs()}';
        evalPawns = -100.0;
      }
    } else {
      final cp = scoreValue * sign;

      evalPawns = cp / 100.0;

      evalLabel = '${evalPawns >= 0 ? '+' : ''}'
          '${evalPawns.toStringAsFixed(2)}';
    }

    return (
      multipv: multipv,
      line: PvLine(
        depth: depth,
        evalPawns: evalPawns,
        evalLabel: evalLabel,
        uciMoves: List<String>.unmodifiable(pv),
      ),
    );
  }

  // ============================================================
  // Analyze position
  // ============================================================

  /// يبدأ تحليلًا جديدًا ويبطل أي تحليل سابق فورًا. يعيد هوية الطلب
  /// (أو null إن لم يبدأ).
  Future<AnalysisRequest?> analyze(
    String fen, {
    required int depth,
    required int multiPv,
    int? movetimeMs,
    int? ply,
  }) async {
    final cleanFen = fen.trim();

    if (cleanFen.isEmpty) {
      onStatus?.call('🔴 FEN فارغ');

      return null;
    }

    if (!ready) {
      onStatus?.call('🟡 Stockfish لم يصبح جاهزًا بعد');

      await init();

      if (!await _waitUntilReady()) {
        onStatus?.call('🔴 Stockfish لم يرسل readyok خلال المهلة');

        return null;
      }
    }

    // ----------------------------------------------------------
    // طلب جديد: يصبح هو الحالي فورًا، فتُبطَل نتائج كل ما قبله.
    // ----------------------------------------------------------

    final request = AnalysisRequest(
      id: ++_nextId,
      fen: cleanFen,
      depth: depth.clamp(1, 60),
      multiPv: multiPv.clamp(1, 10),
      movetimeMs:
          (movetimeMs != null && movetimeMs > 0) ? movetimeMs : null,
      ply: ply,
    );

    _current = request;
    analyzing = true;

    // بحث سابق لم يصل bestmove الخاص به: نوقفه. (bestmove القديم
    // سيصل لاحقًا ويُتجاهل لأنه لا يخص الطلب الحالي.)
    if (_pending.isNotEmpty) {
      await _send('stop');
    }

    onStatus?.call('🔵 جاري تحليل الوضعية...');

    // مهم للوضعيات الخاصة: لعبة UCI جديدة ثم FEN كامل.
    await _send('ucinewgame');

    await _send('setoption name MultiPV value ${request.multiPv}');

    final synced = await _sync();

    if (!identical(_current, request)) {
      // تجاوزه طلب أحدث أو أُوقف أثناء الانتظار: لا نرسل go.
      return request;
    }

    if (!synced) {
      analyzing = false;
      _current = null;

      onStatus?.call('🔴 Stockfish لم يصبح جاهزًا للتحليل');

      return null;
    }

    await _send('position fen ${request.fen}');

    if (!identical(_current, request)) {
      return request;
    }

    // من هنا فصاعدًا هذا الطلب "في الطابور" بانتظار bestmove الخاص به.
    _pending.addLast(request);

    if (request.movetimeMs != null) {
      await _send('go movetime ${request.movetimeMs}');
    } else {
      await _send('go depth ${request.depth}');
    }

    return request;
  }

  // ============================================================
  // Stop analysis
  // ============================================================

  Future<void> stop() async {
    if (!analyzing) {
      return;
    }

    // إبطال الطلب الحالي فورًا: bestmove الخاص به (إن وصل) سيُتجاهل.
    _current = null;
    analyzing = false;

    if (_pending.isNotEmpty) {
      await _send('stop');
    }

    onStatus?.call('🟡 تم إيقاف التحليل');
  }

  // ============================================================
  // Dispose
  // ============================================================

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;

    _current = null;
    _pending.clear();

    for (final w in _syncWaiters) {
      if (!w.isCompleted) {
        w.complete();
      }
    }
    _syncWaiters.clear();

    analyzing = false;
    ready = false;
    _starting = false;
    _readyCompleter = null;

    await _transport.dispose();

    await _outputSubscription?.cancel();

    _outputSubscription = null;

    onStatus = null;
    onInfo = null;
    onBestMove = null;
    onInfoFor = null;
    onBestMoveFor = null;
  }
}
