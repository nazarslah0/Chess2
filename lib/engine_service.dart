import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';

/// نتيجة سطر واحد من MultiPV صادر من Stockfish.
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

/// نتيجة تحليل وضعية واحدة ضمن التحليل المتوازي.
class EnginePositionResult {
  final double evalPawns;
  final String evalLabel;
  final String bestUci;
  final List<String> pv;

  const EnginePositionResult({
    required this.evalPawns,
    required this.evalLabel,
    required this.bestUci,
    required this.pv,
  });
}

class _BatchJob {
  final Completer<EnginePositionResult> completer =
      Completer<EnginePositionResult>();

  double pawns = 0;
  String label = '0.00';
  String bestUci = '';
  List<String> pv = const <String>[];
}

class EngineService {
  static const MethodChannel _methodChannel =
      MethodChannel('chess_analyzer/stockfish');

  static const EventChannel _eventChannel =
      EventChannel('chess_analyzer/stockfish/output');

  static const int _maxWorkers = 4;

  StreamSubscription<dynamic>? _outputSubscription;

  bool ready = false;
  bool analyzing = false;

  bool _starting = false;
  bool _disposed = false;

  String _analyzedFen = '';

  int _analysisId = 0;
  int _activeAnalysisId = 0;

  int _requestedDepth = 18;
  int _requestedMultiPv = 3;
  int? _requestedMovetimeMs;

  Completer<void>? _readyCompleter;

  final Map<int, bool> _workerReady = <int, bool>{};
  final Map<int, Completer<void>> _workerReadyWaiters =
      <int, Completer<void>>{};
  final Map<int, String> _workerFen = <int, String>{};
  final Map<int, _BatchJob> _batchJobs = <int, _BatchJob>{};

  int _batchGeneration = 0;

  /// عدد الأنوية المنطقية المتاحة. نستخدم حدًا أقصى 4 عمال
  /// حتى لا يتحول الهاتف إلى حمل زائد عند تحليل مباراة طويلة.
  int get recommendedWorkerCount {
    final processors = Platform.numberOfProcessors;
    return math.max(1, math.min(_maxWorkers, processors));
  }

  // ============================================================
  // Callbacks
  // ============================================================

  void Function(String status)? onStatus;
  void Function(int multipv, PvLine line)? onInfo;
  void Function(String bestUci)? onBestMove;

  // ============================================================
  // Initialization
  // ============================================================

  Future<void> init() async {
    if (_disposed) return;

    if (ready) {
      onStatus?.call('🟢 Stockfish جاهز');
      return;
    }

    if (_starting) return;

    _starting = true;
    onStatus?.call('🟡 جاري تشغيل Stockfish 19...');

    try {
      await _outputSubscription?.cancel();

      _outputSubscription = _eventChannel
          .receiveBroadcastStream()
          .listen(
        _handleNativeOutput,
        onError: (Object error) {
          ready = false;
          analyzing = false;
          _starting = false;

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
            _starting = false;
            onStatus?.call('🟡 تم إغلاق Stockfish');
          }
        },
        cancelOnError: false,
      );

      await _ensureWorker(0);
      ready = _workerReady[0] ?? false;
      _starting = false;
    } catch (e) {
      ready = false;
      analyzing = false;
      _starting = false;
      onStatus?.call('🔴 فشل تشغيل Stockfish 19: $e');
    }
  }

  Future<void> _ensureWorker(int workerId) async {
    if (_disposed) return;
    if (workerId < 0 || workerId >= _maxWorkers) {
      throw ArgumentError('Invalid Stockfish worker: $workerId');
    }

    if (_workerReady[workerId] == true) {
      return;
    }

    _workerReady[workerId] = false;

    final started = await _methodChannel.invokeMethod<bool>(
          'start',
          <String, dynamic>{'worker': workerId},
        ) ??
        false;

    if (!started) {
      throw StateError(
        'تعذر تشغيل Stockfish worker $workerId',
      );
    }

    // جهّز انتظار readyok قبل إرسال uci.
    final waiter = Completer<void>();
    _workerReadyWaiters[workerId] = waiter;

    await _sendToWorker(workerId, 'uci');

    try {
      await waiter.future.timeout(
        const Duration(seconds: 8),
      );
    } catch (_) {}

    if (_workerReady[workerId] != true) {
      throw StateError(
        'Stockfish worker $workerId لم يرسل readyok',
      );
    }

    // نستخدم خيط CPU واحد لكل عملية. وبما أننا نشغّل عدة
    // عمليات، تنتشر عمليات Stockfish على عدة أنوية بدل أن
    // نخلق oversubscription داخل كل عملية.
    await _setWorkerOption(
      workerId,
      'Threads',
      '1',
    );

    await _setWorkerOption(
      workerId,
      'Hash',
      '16',
    );

    await _syncWorker(workerId);
  }

  Future<void> _setWorkerOption(
    int workerId,
    String name,
    String value,
  ) async {
    await _sendToWorker(
      workerId,
      'setoption name $name value $value',
    );
  }

  Future<void> _syncWorker(int workerId) async {
    _workerReady[workerId] = false;

    final waiter = Completer<void>();
    _workerReadyWaiters[workerId] = waiter;

    await _sendToWorker(workerId, 'isready');

    try {
      await waiter.future.timeout(
        const Duration(seconds: 8),
      );
    } catch (_) {}

    if (_workerReady[workerId] != true) {
      throw StateError(
        'Stockfish worker $workerId غير جاهز',
      );
    }
  }

  // ============================================================
  // Native output
  // ============================================================

  void _handleNativeOutput(dynamic value) {
    if (_disposed || value == null) return;

    final raw = value.toString().trim();
    if (raw.isEmpty) return;

    int workerId = 0;
    String line = raw;

    // النسخة الجديدة من MainActivity ترسل:
    // workerId|stockfish-line
    final separator = raw.indexOf('|');
    if (separator > 0) {
      final possibleWorker =
          int.tryParse(raw.substring(0, separator));
      if (possibleWorker != null) {
        workerId = possibleWorker;
        line = raw.substring(separator + 1);
      }
    } else {
      // دعم احتياطي إذا أرسل الجسر JSON.
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map &&
            decoded['worker'] != null &&
            decoded['line'] != null) {
          workerId =
              int.tryParse(decoded['worker'].toString()) ?? 0;
          line = decoded['line'].toString();
        }
      } catch (_) {}
    }

    _handleLine(workerId, line.trim());
  }

  // ============================================================
  // Send command
  // ============================================================

  Future<void> _sendToWorker(
    int workerId,
    String command,
  ) async {
    if (_disposed) return;

    try {
      await _methodChannel.invokeMethod<void>(
        'send',
        <String, dynamic>{
          'worker': workerId,
          'command': command,
        },
      );
    } catch (e) {
      onStatus?.call(
        '🔴 فشل إرسال أمر Stockfish: $e',
      );
    }
  }

  Future<void> _send(String command) =>
      _sendToWorker(0, command);

  // ============================================================
  // Output parser
  // ============================================================

  void _handleLine(int workerId, String raw) {
    final line = raw.trim();
    if (line.isEmpty) return;

    if (line.startsWith('id ') ||
        line.startsWith('option ') ||
        line == 'uciok') {
      if (line == 'uciok') {
        _onUciReady(workerId);
      }
      return;
    }

    if (line == 'readyok') {
      _workerReady[workerId] = true;

      if (workerId == 0) {
        ready = true;
        _starting = false;

        final completer = _readyCompleter;
        if (completer != null && !completer.isCompleted) {
          completer.complete();
        }

        onStatus?.call('🟢 Stockfish 19 جاهز');
      }

      final waiter = _workerReadyWaiters[workerId];
      if (waiter != null && !waiter.isCompleted) {
        waiter.complete();
      }

      return;
    }

    if (line.startsWith('info ')) {
      _parseInfo(line, workerId);
      return;
    }

    if (line.startsWith('bestmove ')) {
      _handleBestMove(line, workerId);
    }
  }

  void _onUciReady(int workerId) {
    if (workerId == 0) {
      onStatus?.call('🟡 Stockfish 19 متصل...');
    }

    _sendToWorker(workerId, 'isready');
  }

  Future<bool> _waitUntilReady({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (ready) return true;

    _readyCompleter ??= Completer<void>();

    try {
      await _readyCompleter!.future.timeout(timeout);
      return ready;
    } catch (_) {
      return ready;
    }
  }

  // ============================================================
  // Parse bestmove
  // ============================================================

  void _handleBestMove(
    String line,
    int workerId,
  ) {
    final parts = line.split(RegExp(r'\s+'));
    final bestMove =
        parts.length >= 2 ? parts[1].trim() : '';

    final job = _batchJobs[workerId];

    if (job != null) {
      job.bestUci =
          bestMove == '(none)' ? '' : bestMove;

      if (!job.completer.isCompleted) {
        job.completer.complete(
          EnginePositionResult(
            evalPawns: job.pawns,
            evalLabel: job.label,
            bestUci: job.bestUci,
            pv: job.pv,
          ),
        );
      }

      _batchJobs.remove(workerId);
      return;
    }

    if (bestMove.isEmpty || bestMove == '(none)') {
      analyzing = false;
      onStatus?.call('🟡 لا توجد نقلة');
      return;
    }

    final currentId = _analysisId;
    if (_activeAnalysisId != currentId) return;

    analyzing = false;
    onBestMove?.call(bestMove);
    onStatus?.call('🟢 اكتمل التحليل');
  }

  // ============================================================
  // Parse info
  // ============================================================

  void _parseInfo(
    String line,
    int workerId,
  ) {
    final parts = line.split(RegExp(r'\s+'));

    int? depth;
    int multipv = 1;
    String? scoreType;
    int? scoreValue;
    final pv = <String>[];

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

    if (depth == null ||
        scoreType == null ||
        scoreValue == null ||
        pv.isEmpty) {
      return;
    }

    final fen = _workerFen[workerId] ?? _analyzedFen;
    final fenParts = fen.trim().split(RegExp(r'\s+'));
    final sideToMove =
        fenParts.length > 1 ? fenParts[1] : 'w';

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
      evalLabel =
          '${evalPawns >= 0 ? '+' : ''}'
          '${evalPawns.toStringAsFixed(2)}';
    }

    final job = _batchJobs[workerId];

    if (job != null) {
      // نحتفظ بآخر info، وعادة يكون الأعلى عمقًا قبل bestmove.
      if (depth >= 1) {
        job.pawns = evalPawns;
        job.label = evalLabel;
        job.pv = List<String>.unmodifiable(pv);
      }
      return;
    }

    if (!analyzing) return;

    if (_activeAnalysisId != _analysisId) return;

    onInfo?.call(
      multipv,
      PvLine(
        depth: depth,
        evalPawns: evalPawns,
        evalLabel: evalLabel,
        uciMoves: List<String>.unmodifiable(pv),
      ),
    );
  }

  // ============================================================
  // Single-position analysis — API القديمة محفوظة
  // ============================================================

  Future<void> analyze(
    String fen, {
    required int depth,
    required int multiPv,
    int? movetimeMs,
  }) async {
    final cleanFen = fen.trim();

    if (cleanFen.isEmpty) {
      onStatus?.call('🔴 FEN فارغ');
      return;
    }

    if (!ready) {
      await init();

      if (!await _waitUntilReady()) {
        onStatus?.call(
          '🔴 Stockfish لم يرسل readyok خلال المهلة',
        );
        return;
      }
    }

    _analysisId++;
    _activeAnalysisId = _analysisId;

    _requestedDepth = depth.clamp(1, 60);
    _requestedMultiPv = multiPv.clamp(1, 10);
    _requestedMovetimeMs =
        movetimeMs != null && movetimeMs > 0
            ? movetimeMs
            : null;

    _analyzedFen = cleanFen;
    _workerFen[0] = cleanFen;

    if (analyzing) {
      await _send('stop');
      await Future.delayed(
        const Duration(milliseconds: 30),
      );
    }

    analyzing = true;
    onStatus?.call('🔵 جاري تحليل الوضعية...');

    await _send('ucinewgame');
    await _setWorkerOption(
      0,
      'MultiPV',
      '$_requestedMultiPv',
    );
    await _syncWorker(0);

    await _send(
      'position fen $_analyzedFen',
    );

    if (_requestedMovetimeMs != null) {
      await _send(
        'go movetime $_requestedMovetimeMs',
      );
    } else {
      await _send(
        'go depth $_requestedDepth',
      );
    }
  }

  // ============================================================
  // Fast multi-core analysis
  // ============================================================

  /// يحلل مجموعة وضعيات باستخدام عدة عمليات Stockfish مستقلة.
  ///
  /// كل Worker يستخدم Thread=1، وبالتالي:
  /// Worker 0 -> CPU core
  /// Worker 1 -> CPU core
  /// Worker 2 -> CPU core
  /// Worker 3 -> CPU core
  ///
  /// هذا مناسب للهواتف أكثر من تشغيل عشرات المحركات.
  Future<List<EnginePositionResult>> analyzePositionsParallel(
    List<String> fens, {
    int? workerCount,
    int depth = 11,
    int? movetimeMs = 120,
    void Function(int completed, int total)? onProgress,
  }) async {
    if (fens.isEmpty) {
      return const <EnginePositionResult>[];
    }

    await init();

    final requestedWorkers =
        workerCount ?? recommendedWorkerCount;

    final count = math.max(
      1,
      math.min(
        _maxWorkers,
        math.min(requestedWorkers, fens.length),
      ),
    );

    for (int i = 0; i < count; i++) {
      await _ensureWorker(i);
    }

    final results =
        List<EnginePositionResult?>.filled(
      fens.length,
      null,
    );

    int nextIndex = 0;
    int completed = 0;
    final generation = ++_batchGeneration;

    Future<void> workerLoop(int workerId) async {
      while (true) {
        if (_disposed || generation != _batchGeneration) {
          return;
        }

        if (nextIndex >= fens.length) {
          return;
        }

        final index = nextIndex++;
        final fen = fens[index].trim();

        final result = await _analyzeOnWorker(
          workerId,
          fen,
          depth: depth,
          movetimeMs: movetimeMs,
          generation: generation,
        );

        results[index] = result;
        completed++;

        onProgress?.call(
          completed,
          fens.length,
        );
      }
    }

    await Future.wait(
      List<Future<void>>.generate(
        count,
        (workerId) => workerLoop(workerId),
      ),
    );

    return results
        .map(
          (r) =>
              r ??
              const EnginePositionResult(
                evalPawns: 0,
                evalLabel: '0.00',
                bestUci: '',
                pv: <String>[],
              ),
        )
        .toList(growable: false);
  }

  Future<EnginePositionResult> _analyzeOnWorker(
    int workerId,
    String fen, {
    required int depth,
    required int? movetimeMs,
    required int generation,
  }) async {
    final oldJob = _batchJobs.remove(workerId);
    if (oldJob != null &&
        !oldJob.completer.isCompleted) {
      oldJob.completer.complete(
        const EnginePositionResult(
          evalPawns: 0,
          evalLabel: '0.00',
          bestUci: '',
          pv: <String>[],
        ),
      );
    }

    final job = _BatchJob();
    _batchJobs[workerId] = job;
    _workerFen[workerId] = fen;

    await _sendToWorker(
      workerId,
      'ucinewgame',
    );

    await _setWorkerOption(
      workerId,
      'MultiPV',
      '1',
    );

    await _sendToWorker(
      workerId,
      'position fen $fen',
    );

    if (movetimeMs != null && movetimeMs > 0) {
      await _sendToWorker(
        workerId,
        'go movetime $movetimeMs',
      );
    } else {
      await _sendToWorker(
        workerId,
        'go depth ${depth.clamp(1, 60)}',
      );
    }

    try {
      final result = await job.completer.future.timeout(
        Duration(
          milliseconds: math.max(
            2500,
            (movetimeMs ?? 1000) + 1800,
          ),
        ),
      );

      return result;
    } catch (_) {
      // إذا طال التحليل، أوقف هذا العامل فقط.
      await _sendToWorker(workerId, 'stop');

      if (_batchJobs[workerId] == job) {
        _batchJobs.remove(workerId);
      }

      return EnginePositionResult(
        evalPawns: job.pawns,
        evalLabel: job.label,
        bestUci: job.bestUci,
        pv: job.pv,
      );
    } finally {
      if (_batchJobs[workerId] == job) {
        _batchJobs.remove(workerId);
      }
    }
  }

  // ============================================================
  // Stop
  // ============================================================

  Future<void> stop() async {
    _analysisId++;
    _activeAnalysisId = _analysisId;
    _batchGeneration++;

    final workers =
        <int>{0, ..._batchJobs.keys};

    for (final worker in workers) {
      try {
        await _sendToWorker(worker, 'stop');
      } catch (_) {}
    }

    for (final job in _batchJobs.values.toList()) {
      if (!job.completer.isCompleted) {
        job.completer.complete(
          EnginePositionResult(
            evalPawns: job.pawns,
            evalLabel: job.label,
            bestUci: job.bestUci,
            pv: job.pv,
          ),
        );
      }
    }

    _batchJobs.clear();
    analyzing = false;
    onStatus?.call('🟡 تم إيقاف التحليل');
  }

  // ============================================================
  // Dispose
  // ============================================================

  Future<void> dispose() async {
    if (_disposed) return;

    _disposed = true;
    _analysisId++;
    _activeAnalysisId = _analysisId;
    _batchGeneration++;

    analyzing = false;
    ready = false;
    _starting = false;

    for (final job in _batchJobs.values.toList()) {
      if (!job.completer.isCompleted) {
        job.completer.complete(
          const EnginePositionResult(
            evalPawns: 0,
            evalLabel: '0.00',
            bestUci: '',
            pv: <String>[],
          ),
        );
      }
    }

    _batchJobs.clear();

    try {
      await _methodChannel.invokeMethod<void>(
        'dispose',
      );
    } catch (_) {}

    await _outputSubscription?.cancel();
    _outputSubscription = null;

    onStatus = null;
    onInfo = null;
    onBestMove = null;
  }
}
