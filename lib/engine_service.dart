import 'dart:async';



import 'package:flutter/services.dart';

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

class EngineService {
  // ============================================================
  // Android channels
  // ============================================================

  static const MethodChannel _methodChannel =
      MethodChannel('chess_analyzer/stockfish');

  static const EventChannel _eventChannel =
      EventChannel('chess_analyzer/stockfish/output');

  // ============================================================
  // State
  // ============================================================

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

  Completer<void>? _readyCompleter;

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

          onStatus?.call(
            '🔴 خطأ في اتصال Stockfish: $error',
          );
        },
        onDone: () {
          if (!_disposed) {
            ready = false;
            analyzing = false;

            onStatus?.call(
              '🟡 تم إغلاق Stockfish',
            );
          }
        },
        cancelOnError: false,
      );

      final started =
          await _methodChannel.invokeMethod<bool>('start') ?? false;

      if (!started) {
        ready = false;
        _starting = false;

        onStatus?.call(
          '🔴 فشل تشغيل Stockfish 19',
        );

        return;
      }

      // إعطاء الجسر وقتًا لفتح العملية.
      await Future.delayed(
        const Duration(milliseconds: 100),
      );

      await _send('uci');

      _starting = false;
    } catch (e) {
      ready = false;
      analyzing = false;
      _starting = false;

      onStatus?.call(
        '🔴 فشل تشغيل Stockfish 19: $e',
      );
    }
  }

  // ============================================================
  // Native output
  // ============================================================

  void _handleNativeOutput(dynamic value) {
    if (_disposed) {
      return;
    }

    if (value == null) {
      return;
    }

    final line = value.toString().trim();

    if (line.isEmpty) {
      return;
    }

    _handleLine(line);
  }

  // ============================================================
  // Send command to Stockfish
  // ============================================================

  Future<void> _send(String command) async {
    if (_disposed) {
      return;
    }

    try {
      await _methodChannel.invokeMethod<void>(
        'send',
        <String, dynamic>{
          'command': command,
        },
      );
    } catch (e) {
      onStatus?.call(
        '🔴 فشل إرسال أمر Stockfish: $e',
      );
    }
  }

  // ============================================================
  // Stockfish output parser
  // ============================================================

  void _handleLine(String raw) {
    final line = raw.trim();

    if (line.isEmpty) {
      return;
    }

    // ----------------------------------------------------------
    // UCI identification
    // ----------------------------------------------------------

    if (line.startsWith('id ') ||
        line.startsWith('option ') ||
        line == 'uciok') {
      if (line == 'uciok') {
        _onUciReady();
      }

      return;
    }

    // ----------------------------------------------------------
    // Ready
    // ----------------------------------------------------------

    if (line == 'readyok') {
      ready = true;
      _starting = false;

      final completer = _readyCompleter;
      if (completer != null && !completer.isCompleted) {
        completer.complete();
      }

      onStatus?.call(
        '🟢 Stockfish 19 جاهز',
      );

      return;
    }

    // ----------------------------------------------------------
    // Analysis info
    // ----------------------------------------------------------

    if (line.startsWith('info ')) {
      if (!analyzing) {
        return;
      }

      _parseInfo(line);

      return;
    }

    // ----------------------------------------------------------
    // Best move
    // ----------------------------------------------------------

    if (line.startsWith('bestmove ')) {
      _handleBestMove(line);
      return;
    }
  }

  void _onUciReady() {
    onStatus?.call(
      '🟡 Stockfish 19 متصل...',
    );

    // بعد uciok يجب انتظار readyok قبل إرسال position/go.
    _readyCompleter ??= Completer<void>();
    _send('isready');
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
  // Parse bestmove
  // ============================================================

  void _handleBestMove(String line) {
    final parts = line.split(RegExp(r'\s+'));

    final bestMove =
        parts.length >= 2 ? parts[1].trim() : '';

    if (bestMove.isEmpty ||
        bestMove == '(none)') {
      analyzing = false;

      onStatus?.call(
        '🟡 لا توجد نقلة',
      );

      return;
    }

    final currentId = _analysisId;

    // إذا كان التحليل قد تغير أثناء وصول bestmove
    // فلا نعرض النتيجة القديمة.
    if (_activeAnalysisId != currentId) {
      return;
    }

    analyzing = false;

    onBestMove?.call(bestMove);

    onStatus?.call(
      '🟢 اكتمل التحليل',
    );
  }

  // ============================================================
  // Parse Stockfish info
  // ============================================================

  void _parseInfo(String line) {
    final parts = line.split(RegExp(r'\s+'));

    int? depth;
    int multipv = 1;

    String? scoreType;
    int? scoreValue;

    final List<String> pv = <String>[];

    for (int i = 0; i < parts.length; i++) {
      final part = parts[i];

      // depth
      if (part == 'depth' &&
          i + 1 < parts.length) {
        depth = int.tryParse(
          parts[i + 1],
        );
      }

      // multipv
      if (part == 'multipv' &&
          i + 1 < parts.length) {
        multipv =
            int.tryParse(parts[i + 1]) ?? 1;
      }

      // score cp / mate
      if (part == 'score' &&
          i + 2 < parts.length) {
        final type = parts[i + 1];
        final value = int.tryParse(
          parts[i + 2],
        );

        if (type == 'cp' ||
            type == 'mate') {
          scoreType = type;
          scoreValue = value;
        }
      }

      // principal variation
      if (part == 'pv' &&
          i + 1 < parts.length) {
        pv.addAll(
          parts.sublist(i + 1),
        );

        break;
      }
    }

    if (depth == null) {
      return;
    }

    if (scoreType == null ||
        scoreValue == null) {
      return;
    }

    if (pv.isEmpty) {
      return;
    }

    // ----------------------------------------------------------
    // Ignore old analysis
    // ----------------------------------------------------------

    final currentId = _analysisId;

    if (_activeAnalysisId != currentId) {
      return;
    }

    // ----------------------------------------------------------
    // Determine side to move
    // ----------------------------------------------------------

    final fenParts =
        _analyzedFen.trim().split(
              RegExp(r'\s+'),
            );

    final sideToMove =
        fenParts.length > 1
            ? fenParts[1]
            : 'w';

    // Stockfish cp/mate is from the side to move.
    //
    // We convert it to White's perspective:
    //
    // White to move:
    //     +0.50 = White advantage
    //
    // Black to move:
    //     +0.50 from Stockfish = Black advantage
    //     therefore White perspective = -0.50
    //
    final sign =
        sideToMove == 'w' ? 1 : -1;

    double evalPawns;
    String evalLabel;

    // ----------------------------------------------------------
    // Mate
    // ----------------------------------------------------------

    if (scoreType == 'mate') {
      final mate =
          scoreValue * sign;

      if (mate > 0) {
        evalLabel =
            'M${mate.abs()}';

        evalPawns = 100.0;
      } else {
        evalLabel =
            'M-${mate.abs()}';

        evalPawns = -100.0;
      }
    }

    // ----------------------------------------------------------
    // Centipawn evaluation
    // ----------------------------------------------------------

    else if (scoreType == 'cp') {
      final cp =
          scoreValue * sign;

      evalPawns =
          cp / 100.0;

      evalLabel =
          '${evalPawns >= 0 ? '+' : ''}'
          '${evalPawns.toStringAsFixed(2)}';
    }

    // Unknown score
    else {
      return;
    }

    // ----------------------------------------------------------
    // Send result to UI
    // ----------------------------------------------------------

    onInfo?.call(
      multipv,
      PvLine(
        depth: depth,
        evalPawns: evalPawns,
        evalLabel: evalLabel,
        uciMoves:
            List<String>.unmodifiable(
          pv,
        ),
      ),
    );
  }

  // ============================================================
  // Analyze position
  // ============================================================

  Future<void> analyze(
    String fen, {
    required int depth,
    required int multiPv,
  }) async {
    final cleanFen = fen.trim();

    if (cleanFen.isEmpty) {
      onStatus?.call(
        '🔴 FEN فارغ',
      );

      return;
    }

    if (!ready) {
      onStatus?.call(
        '🟡 Stockfish لم يصبح جاهزًا بعد',
      );

      // محاولة تشغيله تلقائيًا.
      await init();

      if (!await _waitUntilReady()) {
        onStatus?.call(
          '🔴 Stockfish لم يرسل readyok خلال المهلة',
        );
        return;
      }
    }

    // ----------------------------------------------------------
    // New analysis ID
    // ----------------------------------------------------------

    _analysisId++;

    _activeAnalysisId =
        _analysisId;

    _requestedDepth =
        depth.clamp(1, 60);

    _requestedMultiPv =
        multiPv.clamp(1, 10);

    _analyzedFen =
        cleanFen;

    // ----------------------------------------------------------
    // Stop previous analysis
    // ----------------------------------------------------------

    if (analyzing) {
      await _send('stop');

      // وقت صغير حتى يعالج Stockfish stop.
      await Future.delayed(
        const Duration(milliseconds: 30),
      );
    }

    // ----------------------------------------------------------
    // Start new analysis
    // ----------------------------------------------------------

    analyzing = true;

    onStatus?.call(
      '🔵 جاري تحليل الوضعية...',
    );

    // مهم جدًا للوضعيات الخاصة:
    // نبدأ لعبة UCI جديدة ثم نرسل FEN كامل.
    await _send('ucinewgame');

    await _send('setoption name MultiPV value $_requestedMultiPv');

    // مزامنة حقيقية مع المحرك: لا نرسل position/go قبل readyok.
    _readyCompleter = Completer<void>();
    await _send('isready');

    if (!await _waitUntilReady()) {
      analyzing = false;
      onStatus?.call(
        '🔴 Stockfish لم يصبح جاهزًا للتحليل',
      );
      return;
    }

    await _send(
      'position fen $_analyzedFen',
    );

    await _send(
      'go depth $_requestedDepth',
    );
  }

  // ============================================================
  // Stop analysis
  // ============================================================

  Future<void> stop() async {
    if (!analyzing) {
      return;
    }

    // إبطال نتائج التحليل السابق.
    _analysisId++;

    _activeAnalysisId =
        _analysisId;

    try {
      await _send('stop');
    } catch (_) {}

    analyzing = false;

    onStatus?.call(
      '🟡 تم إيقاف التحليل',
    );
  }

  // ============================================================
  // Dispose
  // ============================================================

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;

    _analysisId++;

    _activeAnalysisId =
        _analysisId;

    analyzing = false;
    ready = false;
    _starting = false;
    _readyCompleter = null;

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
