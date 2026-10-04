import 'dart:async';
import 'dart:math' as math;

import 'package:chess/chess.dart' as ch;
import 'package:flutter/foundation.dart';

import 'analysis_cache.dart';
import 'analysis_result.dart';
import 'analysis_rules.dart';
import 'app_settings.dart';
import 'engine_service.dart';
import 'game_review_models.dart';
import 'lichess_data_service.dart';
import 'maia_service.dart';
import 'models.dart';
import 'pgn_utils.dart';
import 'puzzle_storage.dart';
import 'pv_material.dart';
import 'pv_utils.dart';
import 'uci_utils.dart';

/// ناتج المحرك لوضعية واحدة أثناء الجمع (قبل تثبيته في الجداول).
class _Eval {
  final double pawns;
  final String label;
  final String bestUci;
  final List<String> pv;

  /// تقييم ثاني أفضل نقلة (منظور الأبيض، بالقرن) إن توفرت
  /// (multiPV=2)، وإلا null.
  final int? secondBestCpWhite;
  final String? secondBestUci;

  const _Eval(
    this.pawns,
    this.label,
    this.bestUci,
    this.pv, {
    this.secondBestCpWhite,
    this.secondBestUci,
  });
}

/// متحكم تحليل المباراة: يملك خط التحليل كاملًا بعيدًا عن الواجهة.
///
/// التدفق:
///   PGN → (الكاش الدائم؟ نعم → نتيجة جاهزة بلا Stockfish)
///       → لا → لكل وضعية: EngineService + Tablebase بالتوازي
///            → Opening Explorer بالتوازي
///            → التصنيف (Tablebase، براق/رائعة، كتاب)
///            → Maia (رائعة، شرح الأخطاء، الأداء)
///            → التمارين
///            → GameAnalysis (المصدر الموحَّد) → الكاش الدائم
///
/// الواجهة تقرأ حالته فقط وتستمع إليه (ChangeNotifier).
class GameAnalysisController extends ChangeNotifier {
  GameAnalysisController({
    required this.pgn,
    this.whiteLabel,
    this.blackLabel,
    this.depth = 14,
    this.multiPv = 2,
    EngineService? engine,
    AnalysisCache? cache,
  })  : _engine = engine ?? EngineService(),
        _cache = cache ?? AnalysisCache.instance {
    _initFromPgn();
  }

  final String pgn;
  final String? whiteLabel;
  final String? blackLabel;
  final int depth;
  final int multiPv;

  final EngineService _engine;
  final AnalysisCache _cache;

  bool _disposed = false;
  bool _started = false;

  int _requestToken = 0;

  String? _parseError;

  List<PgnPly> _plies = <PgnPly>[];
  List<String> _fens = <String>[];
  Map<String, String> _headers = <String, String>{};

  List<double> _evalPawns = <double>[];
  List<String> _evalLabels = <String>[];
  List<String> _bestUci = <String>[];
  List<List<String>> _pvUci = <List<String>>[];
  List<MoveQuality> _qualities = <MoveQuality>[];
  List<bool> _isBestEngineMove = <bool>[];
  List<int?> _secondBestCpWhite = <int?>[];
  List<String?> _secondBestUci = <String?>[];
  List<int?> _moveGapCp = <int?>[];
  List<int?> _tbWdlWhite = <int?>[];
  List<BookMoveInfo?> _bookInfo = <BookMoveInfo?>[];
  List<double?> _maiaProb = <double?>[];
  List<int?> _maiaBucket = <int?>[];
  List<double?> _maiaBestProb = <double?>[];
  List<String?> _maiaTopUci = <String?>[];

  bool _explorerAvailable = false;
  int _puzzlesAdded = 0;

  List<MoveAnalysisResult> _analysisResults = <MoveAnalysisResult>[];

  /// التحليل الموحَّد (بعد اكتماله أو بعد تحميله من الكاش).
  GameAnalysis? _analysis;

  bool _analyzing = false;
  bool _cancelled = false;
  bool _cancelRequested = false;
  bool _servedFromCache = false;
  double _progress = 0;
  int _analyzedCount = 0;

  String _cacheKey = '';
  String _settingsKey = '';

  // ------------------------------------------------------------
  // القراءة (للواجهة)
  // ------------------------------------------------------------

  String? get parseError => _parseError;
  List<PgnPly> get plies => _plies;
  List<String> get fens => _fens;
  Map<String, String> get headers => _headers;

  List<double> get evalPawns => _evalPawns;
  List<String> get evalLabels => _evalLabels;
  List<String> get bestUci => _bestUci;
  List<List<String>> get pvUci => _pvUci;
  List<MoveQuality> get qualities => _qualities;
  List<bool> get isBestEngineMove => _isBestEngineMove;
  List<int?> get secondBestCpWhite => _secondBestCpWhite;
  List<String?> get secondBestUci => _secondBestUci;
  List<int?> get moveGapCp => _moveGapCp;
  List<int?> get tbWdlWhite => _tbWdlWhite;
  List<BookMoveInfo?> get bookInfo => _bookInfo;
  List<double?> get maiaProb => _maiaProb;
  List<int?> get maiaBucket => _maiaBucket;
  List<double?> get maiaBestProb => _maiaBestProb;
  List<String?> get maiaTopUci => _maiaTopUci;

  bool get explorerAvailable => _explorerAvailable;
  int get puzzlesAdded => _puzzlesAdded;

  List<MoveAnalysisResult> get results => _analysisResults;
  GameAnalysis? get analysis => _analysis;

  bool get analyzing => _analyzing;
  bool get cancelled => _cancelled;
  bool get cancelRequested => _cancelRequested;
  bool get servedFromCache => _servedFromCache;
  double get progress => _progress;
  int get analyzedCount => _analyzedCount;
  String get cacheKey => _cacheKey;

  String get whiteName => whiteLabel ?? _headers['White'] ?? 'أبيض';
  String get blackName => blackLabel ?? _headers['Black'] ?? 'أسود';

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // ------------------------------------------------------------
  // التهيئة
  // ------------------------------------------------------------

  void _initFromPgn() {
    _headers = extractPgnHeaders(pgn);

    final plies = parsePgnMoves(pgn);

    if (plies == null || plies.isEmpty) {
      _parseError = 'تعذر قراءة نقلات هذه المباراة (PGN غير مدعوم).';
      return;
    }

    _plies = plies;

    _fens = <String>[
      plies.first.fenBefore,
      for (final p in plies) p.fenAfter,
    ];

    _evalPawns = List<double>.filled(_fens.length, 0.0);
    _evalLabels = List<String>.filled(_fens.length, '0.00');
    _bestUci = List<String>.filled(_fens.length, '');
    _pvUci = List<List<String>>.generate(
      _fens.length,
      (_) => const <String>[],
    );
    _secondBestCpWhite = List<int?>.filled(_fens.length, null);
    _secondBestUci = List<String?>.filled(_fens.length, null);
    _isBestEngineMove = List<bool>.filled(_plies.length, false);
    _moveGapCp = List<int?>.filled(_plies.length, null);
    _tbWdlWhite = List<int?>.filled(_fens.length, null);
    _bookInfo = List<BookMoveInfo?>.filled(_plies.length, null);
    _maiaProb = List<double?>.filled(_plies.length, null);
    _maiaBucket = List<int?>.filled(_plies.length, null);
    _maiaBestProb = List<double?>.filled(_plies.length, null);
    _maiaTopUci = List<String?>.filled(_plies.length, null);

    // قبل أول إطار: نعرض شاشة التحليل ولا نومض شاشة فارغة.
    _analyzing = true;
  }

  /// يبدأ التحليل: يحاول الكاش الدائم أولًا، وإلا يشغّل Stockfish.
  Future<void> start() async {
    if (_parseError != null || _started || _disposed) return;

    _started = true;
    _analyzing = true;

    final token = ++_requestToken;

    _notify();

    // إعدادات التحليل المؤثرة على النتيجة (توفر أوزان Maia).
    final maia = await MaiaService.availableBuckets();

    _settingsKey = 'maia:${maia.join(",")}';

    _cacheKey = _cache.keyFor(
      pgn: pgn,
      depth: depth,
      multiPv: multiPv,
      settings: _settingsKey,
    );

    final cached = await _cache.load(_cacheKey);

    if (_disposed || token != _requestToken) return;

    if (cached != null && _applyAnalysis(cached)) {
      _analysisResults = _buildAnalysisResults();
      _analysis = cached;
      _analyzedCount = _fens.length;
      _progress = 1;
      _analyzing = false;
      _servedFromCache = true;

      _notify();

      return;
    }

    // محرك Stockfish يبدأ هنا فقط عند غياب تحليل صالح محفوظ.
    _engine.init();

    _cancelRequested = false;

    await _runAnalysis(token);
  }

  /// يملأ الجداول الداخلية من تحليل محفوظ. يعيد false إن لم يطابق
  /// هذه المباراة (فلا يُستخدم).
  bool _applyAnalysis(GameAnalysis a) {
    if (!a.isConsistent ||
        a.positions.length != _fens.length ||
        a.moves.length != _plies.length) {
      return false;
    }

    for (var i = 0; i < _fens.length; i++) {
      if (a.positions[i].fen.trim() != _fens[i].trim()) return false;
    }

    for (var i = 0; i < _fens.length; i++) {
      final p = a.positions[i];

      _evalPawns[i] = p.evalPawns;
      _evalLabels[i] = p.evalLabel;
      _bestUci[i] = p.bestUci;
      _pvUci[i] = List<String>.of(p.pv);
      _secondBestCpWhite[i] = p.secondBestCpWhite;
      _secondBestUci[i] = p.secondBestUci;
      _tbWdlWhite[i] = p.tbWdlWhite;
    }

    final qualities = <MoveQuality>[];

    for (var i = 0; i < _plies.length; i++) {
      final m = a.moves[i];

      qualities.add(m.classification);
      _isBestEngineMove[i] = m.isBestMove;
      _moveGapCp[i] = m.bestMoveGapCp;
      _bookInfo[i] = m.bookInfo;
      _maiaProb[i] = m.maiaProbability;
      _maiaBucket[i] = m.maiaBucket;
      _maiaBestProb[i] = m.maiaBestProbability;
      _maiaTopUci[i] = m.maiaTopUci;
    }

    _qualities = qualities;
    _explorerAvailable = a.explorerAvailable;

    return true;
  }

  /// يبني [GameAnalysis] من الحالة الحالية ويحفظه في الكاش الدائم.
  Future<void> _persist() async {
    final analysis = GameAnalysis(
      analysisVersion: kAnalysisVersion,
      engineVersion: kEngineVersion,
      depth: depth,
      multiPv: multiPv,
      settingsKey: _settingsKey,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      explorerAvailable: _explorerAvailable,
      positions: <PositionAnalysis>[
        for (var i = 0; i < _fens.length; i++)
          PositionAnalysis(
            fen: _fens[i],
            evalPawns: _evalPawns[i],
            evalLabel: _evalLabels[i],
            bestUci: _bestUci[i],
            pv: List<String>.of(_pvUci[i]),
            secondBestCpWhite: _secondBestCpWhite[i],
            secondBestUci: _secondBestUci[i],
            tbWdlWhite: _tbWdlWhite[i],
          ),
      ],
      moves: _analysisResults,
    );

    _analysis = analysis;

    await _cache.save(
      _cacheKey,
      SavedGame(
        pgn: pgn,
        white: whiteName,
        black: blackName,
        result: _headers['Result'] ?? '',
        date: _headers['Date'] ?? '',
      ),
      analysis,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _requestToken++;
    _engine.dispose();
    super.dispose();
  }

  // ============================================================
  // التحليل الكامل للمباراة
  // ============================================================

  /// نطلب multiPV=2 (بدل 1) للحصول أيضًا على ثاني أفضل نقلة
  /// وتقييمها — هذا ضروري لتحسين كشف "رائعة" (هل كانت هذه
  /// النقلة الوحيدة القوية فعلًا؟) ولاختيار "أفضل نقلة في
  /// المباراة" بمعيار حقيقي بدل تخمين. التكلفة الإضافية
  /// محدودة (نفس البحث، سطر PV إضافي) وليست تحليلًا مضاعفًا.
  Future<_Eval> _evaluatePosition(String fen, {int? ply}) {
    final completer = Completer<_Eval>();

    double lastPawns = 0;
    String lastLabel = '0.00';
    List<String> lastPv = const <String>[];
    int? secondBestCp;
    String? secondBestUci;

    _engine.onInfo = null;
    _engine.onBestMove = null;

    _engine.onInfoFor = (request, multipv, line) {
      // حماية إضافية: نتيجة تخص وضعية أخرى لا تُستخدم أبدًا.
      if (request.fen.trim() != fen.trim()) return;

      if (multipv == 1) {
        lastPawns = line.evalPawns;
        lastLabel = line.evalLabel;
        lastPv = line.uciMoves;
      } else if (multipv == 2) {
        secondBestCp = cpFromWhitePerspective(
          line.evalPawns,
          line.evalLabel,
        );
        secondBestUci =
            line.uciMoves.isNotEmpty ? line.uciMoves.first : null;
      }
    };

    _engine.onBestMoveFor = (request, uci) {
      if (request.fen.trim() != fen.trim()) return;

      if (!completer.isCompleted) {
        completer.complete(
          _Eval(
            lastPawns,
            lastLabel,
            uci,
            lastPv,
            secondBestCpWhite: secondBestCp,
            secondBestUci: secondBestUci,
          ),
        );
      }
    };

    _engine.analyze(
      fen,
      depth: depth,
      multiPv: 2,
      ply: ply,
    );

    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () => _Eval(
        lastPawns,
        lastLabel,
        '',
        lastPv,
        secondBestCpWhite: secondBestCp,
        secondBestUci: secondBestUci,
      ),
    );
  }

  /// التقييم الفعّال بالقرن (منظور الأبيض) للوضعية i، ويُستخدم في
  /// التصنيف والدقة وخسارة التقييم. إن وُجدت نتيجة Tablebase مضمونة
  /// فهي تصحّح تقدير Stockfish:
  ///  - تعادل مضمون  => 0 (بدل أي أفضلية وهمية يراها المحرك).
  ///  - فوز/خسارة مضمونة => لا ينزل التقييم عن ±400 (احتمال فوز ~81%)،
  ///    فلا تبدو "فوزًا مضمونًا" وضعية يراها المحرك متكافئة.
  /// نتائج المات من المحرك تبقى كما هي. القيم المعروضة (شريط التقييم
  /// والرسم) لا تتغير — هذا التصحيح للحساب فقط.
  int cpAt(int i) {
    final base = cpFromWhitePerspective(
      _evalPawns[i],
      _evalLabels[i],
    );

    final wdl = i < _tbWdlWhite.length ? _tbWdlWhite[i] : null;

    if (wdl == null) return base;

    if (wdl == 0) return 0;

    return wdl > 0 ? math.max(base, 400) : math.min(base, -400);
  }

  /// يطبّق نتيجة Tablebase المضمونة على تصنيف النقلة:
  ///  - فوز => تعادل: "فرصة ضائعة". فوز/تعادل => خسارة: "خطأ فادح".
  ///  - النتيجة لم تتغير (فوز=>فوز، تعادل=>تعادل، خسارة=>خسارة): لا
  ///    تُصنَّف النقلة خطأ أو خطأً فادحًا مهما بدا تقدير المحرك، بحد
  ///    أقصى "غير دقيقة".
  MoveQuality _applyTablebase({
    required MoveQuality quality,
    required String color,
    required int wdlBeforeWhite,
    required int wdlAfterWhite,
  }) =>
      applyTablebaseClassification(
        quality: quality,
        color: color,
        wdlBeforeWhite: wdlBeforeWhite,
        wdlAfterWhite: wdlAfterWhite,
      );

  /// يملأ _bookInfo بإحصائيات Opening Explorer للنقلات الأولى.
  /// "الكتاب" سلسلة متصلة من البداية: عند أول نقلة ليست كتابًا نتوقف
  /// ولا نستعلم عن بقية النقلات (يوفّر الطلبات أيضًا).
  Future<void> _resolveBookMoves(int token) async {
    final limit = math.min(_plies.length, 40);

    for (var i = 0; i < limit; i++) {
      if (_disposed || token != _requestToken || _cancelRequested) {
        return;
      }

      final info = await OpeningExplorerService.instance
          .lookupBookMove(
        fenBefore: _plies[i].fenBefore,
        san: _plies[i].san,
      );

      if (info == null) return;

      _explorerAvailable = true;
      _bookInfo[i] = info;

      if (!info.isBook) return;
    }
  }

  String plyUci(int i) =>
      '${_plies[i].from}${_plies[i].to}${_plies[i].promotion ?? ''}';

  /// يشغّل Maia على كل نقلات المباراة (عدا الكتاب والنقلات الإجبارية)،
  /// بأوزان أقرب مستوى لتصنيف كل لاعب (من ترويسة PGN: WhiteElo /
  /// BlackElo، وإلا 1500). النتائج تُستخدم في:
  ///  - رفع نقلة "أفضل" إلى "رائعة" إن لم يكن يجدها إلا القليل.
  ///  - شرح الأخطاء: خطأ شائع عند هذا المستوى أم زلة غير معتادة.
  ///  - تقييم الأداء مقابل المتوقع لتصنيفك.
  ///  - اختيار التمارين من الأخطاء التي يفوّتها غالب لاعبي المستوى.
  /// أي فشل (لا أوزان، لا محرك) يتخطى Maia بصمت.
  Future<void> _applyMaia(
    int token,
    List<MoveQuality> qualities,
  ) async {
    if (_cancelRequested) return;

    final byBucket = <int, List<int>>{};

    for (var i = 0; i < qualities.length; i++) {
      if (qualities[i] == MoveQuality.book) continue;
      if (_legalMoveCount(_plies[i].fenBefore) <= 1) continue;

      final elo = int.tryParse(
        _headers[_plies[i].color == 'w' ? 'WhiteElo' : 'BlackElo'] ??
            '',
      );

      byBucket
          .putIfAbsent(MaiaService.bucketForElo(elo), () => <int>[])
          .add(i);
    }

    if (byBucket.isEmpty) return;

    for (final entry in byBucket.entries) {
      if (_disposed || token != _requestToken || _cancelRequested) {
        return;
      }

      final session = await MaiaSession.open(entry.key);

      if (session == null) continue;

      try {
        for (final i in entry.value) {
          if (_disposed ||
              token != _requestToken ||
              _cancelRequested) {
            return;
          }

          final policy = await session.policy(
            startFen: _fens.first,
            movesUci: <String>[
              for (var k = 0; k < i; k++) plyUci(k),
            ],
          );

          if (policy == null) continue;

          final played = plyUci(i);
          final prob = policy[played];

          _maiaBucket[i] = entry.key;

          final ranked = MaiaService.ranked(policy);

          if (ranked.isNotEmpty) _maiaTopUci[i] = ranked.first.key;

          final best = _pvUci[i].isNotEmpty ? _pvUci[i].first : null;

          if (parseUci(best) != null) {
            // مطابقة كاملة (from + to + promotion) عبر طبقة UCI الموحدة.
            double? bp;

            for (final e in policy.entries) {
              if (isSameUciMove(e.key, best)) {
                bp = (bp ?? 0) + e.value;
              }
            }

            _maiaBestProb[i] = bp;
          }

          if (prob == null) continue;

          _maiaProb[i] = prob;

          if (qualities[i] == MoveQuality.best &&
              _isBestEngineMove[i] &&
              _isMaiaGreat(i, prob)) {
            qualities[i] = MoveQuality.great;
          }
        }
      } finally {
        await session.close();
      }
    }
  }

  // ------------------------------------------------------------
  // تمارين من أخطائك
  // ------------------------------------------------------------

  /// يستخرج من المباراة وضعيات فاتتك فيها نقلة قوية ويحفظها في
  /// "تمارين من مبارياتك". إن عُرف اسمك (الإعدادات) تؤخذ أخطاؤك أنت
  /// فقط، وإلا أخطاء الطرفين. الأفضلية للنقلات التي لا يجدها غالب
  /// لاعبي المستوى (احتمالها عند Maia <= 35%).
  Future<void> _collectPuzzles(List<MoveQuality> qualities) async {
    if (_cancelRequested || _analyzedCount < _fens.length) return;

    try {
      final settings = AppSettings.instance;

      final whiteMe = settings.isMe(_headers['White']) ||
          settings.isMe(whiteLabel);
      final blackMe = settings.isMe(_headers['Black']) ||
          settings.isMe(blackLabel);

      final String? mySide =
          whiteMe && !blackMe ? 'w' : (blackMe && !whiteMe ? 'b' : null);

      final cands = <MapEntry<int, int>>[];

      for (var i = 0; i < qualities.length; i++) {
        final q = qualities[i];

        if (q != MoveQuality.miss &&
            q != MoveQuality.mistake &&
            q != MoveQuality.blunder) {
          continue;
        }

        final p = _plies[i];

        if (mySide != null && p.color != mySide) continue;

        final best = _pvUci[i].isNotEmpty ? _pvUci[i].first : '';

        if (parseUci(best) == null ||
            isSameUciMove(best, plyUci(i))) {
          continue;
        }

        final bp = _maiaBestProb[i];

        if (bp != null && bp > 0.35) continue;

        final sign = p.color == 'w' ? 1 : -1;

        // لا نختار وضعيات كانت خاسرة أصلًا.
        if (cpAt(i) * sign < -300) continue;

        cands.add(MapEntry<int, int>(i, lossAt(i)));
      }

      cands.sort((a, b) => b.value.compareTo(a.value));

      final limit = mySide == null ? 4 : 3;

      final label = '$whiteName vs $blackName';

      final items = <PuzzleItem>[];

      for (final c in cands.take(limit)) {
        final i = c.key;
        final p = _plies[i];
        final best = _pvUci[i].first;

        items.add(
          PuzzleItem(
            id: PuzzleStorage.idFor(p.fenBefore),
            fen: p.fenBefore,
            bestUci: best,
            bestSan: pvToSan(p.fenBefore, <String>[best]),
            playedSan: p.san,
            line: pvToSan(p.fenBefore, _pvUci[i]),
            label: label,
            createdAt: DateTime.now().millisecondsSinceEpoch,
            maiaBucket: _maiaBucket[i],
            maiaBestProb: _maiaBestProb[i],
          ),
        );
      }

      _puzzlesAdded = await PuzzleStorage.addAll(items);
    } catch (_) {}
  }

  bool _isMaiaGreat(int i, double prob) {
    if (prob > MaiaService.greatMaxProb) return false;

    final p = _plies[i];

    if (_legalMoveCount(p.fenBefore) <= 1) return false;

    final second = _secondBestCpWhite[i];

    if (second == null) return false;

    final wpBest = winPercentWhite(cpAt(i));
    final wpSecond = winPercentWhite(second);

    final moverBest = p.color == 'w' ? wpBest : 100 - wpBest;
    final moverSecond = p.color == 'w' ? wpSecond : 100 - wpSecond;

    // وضعية محسومة: لا معنى لـ"رائعة".
    if (moverBest < 8 || moverBest > 92) return false;

    return (moverBest - moverSecond) >= MaiaService.greatMinGapWinPct;
  }

  Future<void> _runAnalysis(int token) async {
    if (!_engine.ready) {
      await _engine.init();

      var waited = 0;
      while (!_engine.ready && waited < 8000) {
        await Future.delayed(
          const Duration(milliseconds: 200),
        );
        waited += 200;
      }
    }

    // استعلامات Opening Explorer تعمل بالتوازي مع Stockfish ولا تؤخّره.
    final bookFuture = _resolveBookMoves(token);

    for (var i = 0; i < _fens.length; i++) {
      if (_disposed || token != _requestToken) {
        return;
      }

      if (_cancelRequested) {
        break;
      }

      // استعلام Tablebase (للوضعيات ذات 7 قطع أو أقل فقط) يعمل
      // بالتوازي مع تحليل Stockfish لنفس الوضعية.
      final tbFuture =
          TablebaseService.instance.probeWhiteWdl(_fens[i]);

      final r = await _evaluatePosition(_fens[i], ply: i);

      final tbWdl = await tbFuture;

      if (_disposed || token != _requestToken) {
        return;
      }

      _evalPawns[i] = r.pawns;
      _evalLabels[i] = r.label;
      _bestUci[i] = r.bestUci;
      _pvUci[i] = r.pv;
      _secondBestCpWhite[i] = r.secondBestCpWhite;
      _secondBestUci[i] = r.secondBestUci;
      _tbWdlWhite[i] = tbWdl;

      _analyzedCount = i + 1;
      _progress = (i + 1) / _fens.length;
      _notify();
    }

    await bookFuture;

    if (_disposed || token != _requestToken) {
      return;
    }

    // نصنّف فقط النقلات التي اكتمل تحليل وضعيتها السابقة
    // واللاحقة فعليًا — إذا أُلغي التحليل منتصف الطريق، تبقى
    // هذه النتائج الجزئية صالحة ومستخدمة بدل ضياعها بالكامل.
    final classifiableCount =
        (_analyzedCount - 1).clamp(0, _plies.length);

    final qualities = <MoveQuality>[];

    for (var i = 0; i < classifiableCount; i++) {
      final p = _plies[i];

      final cpBefore = cpAt(i);

      final cpAfter = cpAt(i + 1);

      final bestUci = _bestUci[i];

      // مقارنة دقيقة كاملة (from + to + promotion)، وليست
      // startsWith النصية التي كانت تخطئ مثلًا بين "e7e8"
      // و"e7e8q" (ترقية مختلفة) أو حتى "e7e1" إن بدأت بنفس
      // المربعين من الصدفة في نصوص أطول.
      final playedUciMove = UciMove(
        from: p.from,
        to: p.to,
        promotion: p.promotion?.toLowerCase(),
      );

      final wasBest = isSameUciMove(
        bestUci,
        playedUciMove.uci,
      );

      // إن كانت النقلة المُلعَبة هي ثاني أفضل خط للمحرك نفسه
      // (MultiPV)، فتقييمها من نفس البحث وبنفس العمق أدق وأعدل من
      // تقييم بحث مستقل للوضعية التالية: نستخدمه في التصنيف فقط.
      var cpAfterForClass = cpAfter;

      final secondUci = _secondBestUci[i];
      final secondCp = _secondBestCpWhite[i];

      if (!wasBest &&
          secondCp != null &&
          isSameUciMove(secondUci, playedUciMove.uci)) {
        cpAfterForClass = secondCp;
      }

      var quality = classifyMove(
        cpBeforeWhite: cpBefore,
        cpAfterWhite: cpAfterForClass,
        color: p.color,
        wasBestMove: wasBest,
        onlyLegalMove: _legalMoveCount(p.fenBefore) <= 1,
      );

      _isBestEngineMove[i] = wasBest;

      // Tablebase: نتيجة مضمونة قبل/بعد النقلة تحسم التصنيف بدل
      // تقدير Stockfish.
      final tbBefore = _tbWdlWhite[i];
      final tbAfter = _tbWdlWhite[i + 1];

      if (tbBefore != null && tbAfter != null) {
        final adjusted = _applyTablebase(
          quality: quality,
          color: p.color,
          wdlBeforeWhite: tbBefore,
          wdlAfterWhite: tbAfter,
        );

        if (adjusted != quality) {
          quality = adjusted;

          if (adjusted == MoveQuality.blunder ||
              adjusted == MoveQuality.miss) {
            _isBestEngineMove[i] = false;
          }
        }
      }

      final sign = p.color == 'w' ? 1 : -1;
      final cpBeforeMover = cpBefore * sign;

      // فجوة التقييم بين أفضل نقلة وثاني أفضل نقلة، من منظور
      // اللاعب الذي يلعب — كبيرة تعني "هذه كانت النقلة
      // الوحيدة القوية فعلًا"، صغيرة تعني وجود بدائل شبه
      // مكافئة.
      final secondBestWhite = _secondBestCpWhite[i];

      final gapCp = secondBestWhite != null
          ? (cpBefore * sign) - (secondBestWhite * sign)
          : null;

      _moveGapCp[i] = gapCp;

      if (quality == MoveQuality.best) {
        final upgraded = _tryUpgradeToBrilliant(
          plyIndex: i,
          ply: p,
          baseQuality: quality,
          cpBeforeMover: cpBeforeMover,
          cpAfterMover: cpAfter * sign,
          secondBestGapCp: gapCp,
        );

        if (upgraded != null) {
          quality = upgraded;
        } else if (isGreatCandidate(
          cpBeforeWhite: cpBefore,
          secondBestCpWhite: secondBestWhite,
          color: p.color,
          onlyLegalMove: _legalMoveCount(p.fenBefore) <= 1,
        )) {
          quality = MoveQuality.great;
        }
      }

      // "كتاب": إن توفّر Opening Explorer فالنقلة كتاب إذا لُعبت في
      // عدد كافٍ من مباريات الأساتذة (سلسلة متصلة من بداية المباراة).
      // وإن تعذّر الاتصال نعود للتقدير المحلي القديم (أول 5 نقلات
      // لكل لاعب، وضعية متكافئة، والنقلة أفضل أو شبه أفضل).
      if (_explorerAvailable) {
        final info = _bookInfo[i];

        if (info != null && info.isBook) {
          quality = MoveQuality.book;
        }
      } else if (i < 10 &&
          (quality == MoveQuality.best ||
              quality == MoveQuality.excellent) &&
          cpBefore.abs() <= 60 &&
          cpAfter.abs() <= 60) {
        quality = MoveQuality.book;
      }

      qualities.add(quality);
    }

    // Maia: رفع "رائعة"، شرح الأخطاء، تقييم الأداء، واستخراج التمارين.
    await _applyMaia(token, qualities);

    await _collectPuzzles(qualities);

    if (_disposed || token != _requestToken) {
      return;
    }

    // لا ننقل المستخدم تلقائيًا إلى آخر نقلة بعد اكتمال التحليل.
    _qualities = qualities;
    _analyzing = false;
    _cancelled = _cancelRequested && _analyzedCount < _fens.length;
    _analysisResults = _buildAnalysisResults();

    _notify();

    // لا نخزّن إلا تحليلًا مكتملًا بالكامل — نتيجة جزئية (بعد إلغاء)
    // لا يجب أن تُقدَّم لاحقًا على أنها تحليل كامل للمباراة.
    if (!_cancelled && _analyzedCount >= _fens.length) {
      await _persist();
    }
  }

  /// إلغاء التحليل مع الاحتفاظ بكل ما تم تحليله فعليًا حتى
  /// هذه اللحظة (تقييم، أفضل نقلة، تصنيف) — فقط النقلات بعد
  /// نقطة الإلغاء تبقى غير محلَّلة.
  void cancel() {
    if (!_analyzing) return;

    _cancelRequested = true;
    _notify();

    _engine.stop();
  }

  // ============================================================
  // كشف تقريبي لنقلة "رائعة!!" (تضحية حقيقية + أفضل نقلة)
  // ============================================================

  int _legalMoveCount(String fen) {
    try {
      final g = ch.Chess();
      g.load(fen);
      return g.moves().length;
    } catch (_) {
      return 2;
    }
  }

  /// هل هذه النقلة تضحية حقيقية؟ الطريقة الدقيقة: نلعب النقلة ثم
  /// أول 4-6 نقلات من خط Stockfish الرئيسي (PV) بعدها ونقيس المادة.
  /// إن بقي اللاعب خاسرًا للمادة فعلًا (قطعة أو أكثر مقابل لا شيء)
  /// مع بقاء التقييم جيدًا فهي تضحية. أما التبادلات التي تعود فيها
  /// المادة متساوية فلا تُحتسب.
  ///
  /// إن لم يتوفر PV كافٍ (أو انتهى في منتصف تبادل) نعود للفحص
  /// القديم: الخصم يستطيع أخذ القطعة فورًا بربح مادي ظاهري.
  MoveQuality? _tryUpgradeToBrilliant({
    required int plyIndex,
    required PgnPly ply,
    required MoveQuality baseQuality,
    required int cpBeforeMover,
    required int cpAfterMover,
    required int? secondBestGapCp,
  }) {
    try {
      final boardBefore = GameState.parseBoard(
        ply.fenBefore.split(' ').first,
      );

      final movingPiece = boardBefore[ply.from];

      if (movingPiece == null ||
          movingPiece.length != 2) {
        return null;
      }

      final movingType = movingPiece[1];

      if (movingType == 'P' ||
          movingType == 'K') {
        return null;
      }

      final pvAfter = plyIndex + 1 < _pvUci.length
          ? _pvUci[plyIndex + 1]
          : const <String>[];

      final sim = pvAfter.length >= 3
          ? simulatePvMaterial(
              fenBefore: ply.fenBefore,
              from: ply.from,
              to: ply.to,
              promotion: ply.promotion,
              moverColor: ply.color,
              pvAfterUci: pvAfter,
            )
          : null;

      bool genuineSacrifice;

      if (sim != null && sim.quiet) {
        // تضحية حقيقية: خسارة مادة فعلية (>= 2 نقطة) في نهاية الخط،
        // مع بقاء التقييم جيدًا (ليست وضعية خاسرة).
        genuineSacrifice =
            sim.deficit >= 2 && cpAfterMover >= -50;
      } else {
        genuineSacrifice =
            _legacySacrificeCheck(ply, boardBefore, movingType);
      }

      // فكرة تكتيكية بدون تضحية: نقلة هادئة (ليست أخذًا) يربح بها
      // اللاعب مادة بالقوة في خط المحرك.
      final tacticalIdea = !genuineSacrifice &&
          !ply.isCapture &&
          sim != null &&
          sim.quiet &&
          -sim.deficit >= 3;

      if (!genuineSacrifice && !tacticalIdea) {
        return null;
      }

      // استرداد بديهي: أخذ مباشر على نفس المربع الذي أُخذ للتو.
      final obviousRecapture = ply.isCapture &&
          plyIndex > 0 &&
          _plies[plyIndex - 1].isCapture &&
          _plies[plyIndex - 1].to == ply.to;

      final beforeGame = ch.Chess();
      beforeGame.load(ply.fenBefore);

      var legalCount = 0;

      try {
        legalCount = beforeGame.moves().length;
      } catch (_) {
        legalCount = 2;
      }

      final brilliant = isBrilliantCandidate(
        baseQuality: baseQuality,
        isSacrifice: genuineSacrifice,
        cpBeforeMover: cpBeforeMover,
        onlyLegalMove: legalCount <= 1,
        movingPieceType: movingType,
        secondBestGapCp: secondBestGapCp,
        isObviousRecapture: obviousRecapture,
        isTacticalIdea: tacticalIdea,
        positionHoldsAfter: cpAfterMover >= -50,
      );

      return brilliant ? MoveQuality.brilliant : null;
    } catch (_) {
      return null;
    }
  }

  /// الفحص القديم للتضحية (احتياطي عند غياب PV): قيمة القطعة
  /// المتحركة ناقص ما أخذته >= 2، والخصم يستطيع أخذها في الحال.
  bool _legacySacrificeCheck(
    PgnPly ply,
    Map<String, String> boardBefore,
    String movingType,
  ) {
    int capturedValue = 0;

    if (ply.isCapture) {
      final capturedPiece = boardBefore[ply.to];

      if (capturedPiece != null &&
          capturedPiece.length == 2) {
        capturedValue =
            pieceValues[capturedPiece[1]] ?? 0;
      } else {
        capturedValue = 1;
      }
    }

    final movingValue = pieceValues[movingType] ?? 0;

    if (movingValue - capturedValue < 2) {
      return false;
    }

    final afterGame = ch.Chess();
    afterGame.load(ply.fenAfter);

    List<dynamic> opponentMoves = [];

    try {
      opponentMoves = afterGame.moves(
        <String, dynamic>{'verbose': true},
      );
    } catch (_) {
      opponentMoves = [];
    }

    for (final m in opponentMoves) {
      String? to;

      try {
        to = m is Map
            ? m['to']?.toString()
            : (m as dynamic).toAlgebraic as String;
      } catch (_) {
        to = null;
      }

      if (to == ply.to) {
        return true;
      }
    }

    return false;
  }

  // ============================================================
  // حسابات تقرير المباراة (الدقة، مراحل اللعبة، اللحظات الحرجة)
  // ============================================================

  /// خسارة التقييم بوحدة القرن من منظور اللاعب الذي لعب
  /// النقلة رقم i (قيمة موجبة = تراجع).
  int lossAt(int i) {
    final before = cpAt(i);

    final after = cpAt(i + 1);

    final sign = _plies[i].color == 'w' ? 1 : -1;

    return (before * sign) - (after * sign);
  }

  double accuracyAt(int i) {
    final before = cpAt(i);

    final after = cpAt(i + 1);

    final wpBefore = winPercentWhite(before);
    final wpAfter = winPercentWhite(after);

    final color = _plies[i].color;

    final wpBeforeMover =
        color == 'w' ? wpBefore : 100 - wpBefore;
    final wpAfterMover =
        color == 'w' ? wpAfter : 100 - wpAfter;

    return moveAccuracy(
      winPercentBeforeMover: wpBeforeMover,
      winPercentAfterMover: wpAfterMover,
    );
  }

  /// عدد نقاط المادة (بدون بيادق وملوك) على الرقعة عند FEN
  /// معيّن — يُستخدم لتحديد بداية النهايات.
  int nonPawnMaterial(String fen) {
    final board = GameState.parseBoard(
      fen.split(' ').first,
    );

    var total = 0;

    for (final piece in board.values) {
      if (piece.length != 2) continue;
      final t = piece[1];
      if (t == 'P' || t == 'K') continue;
      total += pieceValues[t] ?? 0;
    }

    return total;
  }

  /// index أول نقلة تدخل بها المباراة مرحلة النهايات، أو
  /// طول المباراة إن لم تصله (لا نهايات).
  int get endgameStartPly {
    for (var i = 0; i < _fens.length; i++) {
      if (nonPawnMaterial(_fens[i]) <= 12) {
        return i;
      }
    }

    return _plies.length;
  }

  int get openingEndPly =>
      _plies.length < 20 ? _plies.length : 20;

  String phaseOf(int plyIndex) {
    if (plyIndex < openingEndPly) return 'opening';
    if (plyIndex >= endgameStartPly) return 'endgame';
    return 'middlegame';
  }

  /// يبني قائمة [MoveAnalysisResult] — المصدر الموحَّد لكل ما يُعرض
  /// عن كل نقلة — من حالة التحليل الحالية.
  List<MoveAnalysisResult> _buildAnalysisResults() {
    final results = <MoveAnalysisResult>[];

    for (var i = 0; i < _qualities.length; i++) {
      final p = _plies[i];
      final q = _qualities[i];

      final sign = p.color == 'w' ? 1 : -1;

      final beforeWhite = cpAt(i);
      final afterWhite = cpAt(i + 1);

      final bestUci = i < _bestUci.length ? _bestUci[i] : '';

      final bestSan = parseUci(bestUci) != null
          ? pvToSan(_fens[i], [bestUci])
          : '';

      results.add(
        MoveAnalysisResult(
          ply: i,
          moveNumber: (i ~/ 2) + 1,
          side: p.color,
          san: p.san,
          uci: plyUci(i),
          fenBefore: p.fenBefore,
          fenAfter: p.fenAfter,
          evaluationBeforeCp: beforeWhite * sign,
          evaluationAfterCp: afterWhite * sign,
          evaluationLossCp: lossAt(i),
          evaluationBeforeWhiteCp: beforeWhite,
          evaluationAfterWhiteCp: afterWhite,
          bestMoveSan: bestSan,
          bestMoveUci: bestUci,
          principalVariationUci:
              i < _pvUci.length ? _pvUci[i] : const <String>[],
          classification: q,
          phase: phaseOf(i),
          materialBefore: nonPawnMaterial(p.fenBefore),
          materialAfter: nonPawnMaterial(p.fenAfter),
          // تُحدَّد اللحظات الحرجة لاحقًا في markCriticalMoments.
          isCritical: false,
          isBestMove: i < _isBestEngineMove.length
              ? _isBestEngineMove[i]
              : false,
          isBrilliant: q == MoveQuality.brilliant,
          isMistake: q == MoveQuality.mistake,
          isBlunder: q == MoveQuality.blunder,
          isMissedOpportunity: q == MoveQuality.miss,
          isGreat: q == MoveQuality.great,
          bestMoveGapCp: _moveGapCp[i],
          tablebaseVerdict: tablebaseVerdict(
            side: p.color,
            wdlBeforeWhite: _tbWdlWhite[i],
            wdlAfterWhite: _tbWdlWhite[i + 1],
          ),
          tablebaseWdlBeforeWhite: _tbWdlWhite[i],
          tablebaseWdlAfterWhite: _tbWdlWhite[i + 1],
          bookInfo: _bookInfo[i],
          maiaProbability: _maiaProb[i],
          maiaBestProbability: _maiaBestProb[i],
          maiaTopUci: _maiaTopUci[i],
          maiaBucket: _maiaBucket[i],
        ),
      );
    }

    return markCriticalMoments(results);
  }
}
