import 'package:flutter/material.dart';
import 'package:chess/chess.dart' as ch;

import 'models.dart';
import 'engine_service.dart';
import 'board_widget.dart';
import 'panels.dart';
import 'sound_service.dart';
import 'home_screen.dart';
import 'app_theme.dart';

void main() {
  runApp(
    const ChessAnalyzerApp(),
  );
}

/// ============================================================
/// App
/// ============================================================

class ChessAnalyzerApp extends StatelessWidget {
  const ChessAnalyzerApp({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'محلل وضعيات الشطرنج',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      theme: Chess2Theme.light(),
      darkTheme: Chess2Theme.dark(),
      themeMode: ThemeMode.dark,
      // نطبّق RTL على كل الشاشات (بما فيها الشاشات التي
      // تُفتح لاحقًا عبر Navigator.push)، بدل تغليف الشاشة
      // الأولى فقط.
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const HomeScreen(),
    );
  }
}

/// ============================================================
/// Home Screen
/// ============================================================

class PositionAnalyzerScreen extends StatefulWidget {
  const PositionAnalyzerScreen({
    super.key,
  });

  @override
  State<PositionAnalyzerScreen> createState() =>
      _PositionAnalyzerScreenState();
}

class _PositionAnalyzerScreenState extends State<PositionAnalyzerScreen> {
  // ==========================================================
  // State
  // ==========================================================

  final GameState state =
      GameState();

  final EngineService engine =
      EngineService();

  final SoundService soundService =
      SoundService();

  int boardThemeIdx = 0;
  int pieceThemeIdx = 0;

  String engineStatus =
      '🟡 جاري تشغيل Stockfish 19...';

  bool engineReady = false;

  int depth = 18;
  int multiPv = 3;

  final Map<int, PvLineDisplay> pvLines =
      <int, PvLineDisplay>{};

  String? _analysisFen;
  String? _lastKnownFen;

  String? selectedSetupPiece;

  bool eraseMode = false;

  Set<String> targets =
      <String>{};

  final TextEditingController fenController =
      TextEditingController();

  // ==========================================================
  // Init
  // ==========================================================

  @override
  void initState() {
    super.initState();

    state.addListener(
      _onStateChanged,
    );

    state.onSound = (
      String kind,
    ) {
      soundService.playKind(kind);
    };

    engine.onStatus = (
      String status,
    ) {
      if (!mounted) {
        return;
      }

      setState(() {
        engineStatus = status;

        // ملاحظة: لا نستنتج جاهزية المحرك من شكل
        // الرسالة (🟢/🟡/🔴)، لأن رسائل مثل "تم إيقاف
        // التحليل" أو "جاري تحليل الوضعية..." تبدأ بـ
        // 🟡 رغم أن المحرك لا يزال جاهزًا تمامًا. كان
        // هذا يجعل زر "تحليل الوضعية" يتعطل بشكل دائم
        // بعد أول إيقاف للتحليل. نعتمد بدلاً من ذلك على
        // العلم الفعلي engine.ready الذي تديره
        // EngineService نفسها.
        engineReady =
            engine.ready;
      });
    };

    engine.onInfo = (
      int multipv,
      PvLine raw,
    ) {
      if (!mounted) {
        return;
      }

      final analysisFen =
          _analysisFen;

      if (analysisFen == null ||
          analysisFen.trim() !=
              state.currentFen.trim()) {
        return;
      }

      final display =
          _convertPv(
        analysisFen,
        raw,
      );

      // لا نعرض PV إذا لم نستطع
      // تحويل أول نقلة إلى نقلة قانونية.
      if (display.moves.isEmpty ||
          display.bestFrom.isEmpty ||
          display.bestTo.isEmpty) {
        return;
      }

      setState(() {
        pvLines[multipv] =
            display;
      });
    };

    engine.onBestMove = (
      String uci,
    ) {
      // بعض إصدارات/بناءات Stockfish قد ترسل bestmove
      // بدون أن تصل آخر info/pv إلى EventChannel.
      // في هذه الحالة نستخدم bestmove نفسه كحل احتياطي
      // حتى لا ينتهي التحليل بواجهة فارغة وبدون سهم.
      if (!mounted) {
        return;
      }

      final analysisFen = _analysisFen;
      if (analysisFen == null ||
          analysisFen.trim() != state.currentFen.trim()) {
        return;
      }

      final clean = uci.trim().toLowerCase();
      if (!_isValidUciMove(clean)) {
        return;
      }

      // إذا وصل PV بالفعل، فلا نستبدله.
      if (pvLines.containsKey(1)) {
        return;
      }

      setState(() {
        pvLines[1] = PvLineDisplay(
          depth: depth,
          evalLabel: '—',
          moves: <String>[clean],
          bestFrom: clean.substring(0, 2),
          bestTo: clean.substring(2, 4),
        );
      });
    };

    // تشغيل Stockfish 19.
    engine.init();
  }

  // ==========================================================
  // State changes
  // ==========================================================

  void _onStateChanged() {
    if (!mounted) {
      return;
    }

    final fen =
        state.currentFen.trim();

    if (fen != _lastKnownFen) {
      _lastKnownFen = fen;

      if (engine.analyzing) {
        engine.stop();
      }

      setState(() {
        pvLines.clear();

        _analysisFen = null;

        targets =
            <String>{};
      });

      return;
    }

    setState(() {});
  }

  // ==========================================================
  // Dispose
  // ==========================================================

  @override
  void dispose() {
    state.removeListener(
      _onStateChanged,
    );

    engine.dispose();

    soundService.dispose();

    fenController.dispose();

    state.dispose();

    super.dispose();
  }

  bool _isValidUciMove(String uci) {
    if (uci.length < 4) {
      return false;
    }

    bool validSquare(String value) {
      if (value.length != 2) {
        return false;
      }
      final file = value.codeUnitAt(0);
      final rank = value.codeUnitAt(1);
      return file >= 97 && file <= 104 &&
          rank >= 49 && rank <= 56;
    }

    return validSquare(uci.substring(0, 2)) &&
        validSquare(uci.substring(2, 4));
  }

  // ==========================================================
  // Convert UCI PV to SAN
  // ==========================================================

  PvLineDisplay _convertPv(
    String fen,
    PvLine raw,
  ) {
    final chess =
        ch.Chess();

    try {
      final loaded =
          chess.load(fen);

      if (loaded == false) {
        return PvLineDisplay(
          depth: raw.depth,
          evalLabel: raw.evalLabel,
          moves: const <String>[],
          bestFrom: '',
          bestTo: '',
        );
      }
    } catch (_) {
      return PvLineDisplay(
        depth: raw.depth,
        evalLabel: raw.evalLabel,
        moves: const <String>[],
        bestFrom: '',
        bestTo: '',
      );
    }

    final List<String> sans =
        <String>[];

    String bestFrom = '';
    String bestTo = '';

    for (final uciRaw
        in raw.uciMoves) {
      final uci = uciRaw.trim().toLowerCase();

      // أهم نقطة: لا نجعل فشل تحويل SAN يمنع ظهور
      // نتيجة Stockfish والسهم. UCI نفسه كافٍ لرسم السهم.
      if (!_isValidUciMove(uci)) {
        break;
      }

      final from = uci.substring(0, 2);
      final to = uci.substring(2, 4);

      String? promotion;
      if (uci.length >= 5) {
        promotion = uci.substring(4, 5);
      }

      // ------------------------------------------------------
      // النقلة الأولى تُستخدم للسهم فورًا.
      // ------------------------------------------------------

      if (bestFrom.isEmpty) {
        bestFrom = from;
        bestTo = to;
      }

      // ------------------------------------------------------
      // البحث عن النقلة بين النقلات القانونية للحصول على SAN،
      // ثم تنفيذها على نسخة التحليل لمتابعة الـ PV.
      // إذا فشل ذلك نعرض UCI بدل إسقاط النتيجة كلها.
      // ------------------------------------------------------

      final legal = GameState.findLegalMove(
        chess,
        from,
        to,
        promotion,
      );

      if (legal == null) {
        if (sans.isEmpty) {
          sans.add(uci);
        }
        break;
      }

      final san = (legal['san'] ?? uci).toString();

      bool moved = false;
      try {
        final args = <String, dynamic>{
          'from': from,
          'to': to,
        };
        if (promotion != null) {
          args['promotion'] = promotion;
        }
        final result = chess.move(args);
        moved = result != false;
      } catch (_) {
        moved = false;
      }

      if (!moved) {
        if (sans.isEmpty) {
          sans.add(uci);
        }
        break;
      }

      sans.add(san);

      // لا نعرض أكثر من 8 نقلات.
      if (sans.length >= 8) {
        break;
      }
    }

    return PvLineDisplay(
      depth: raw.depth,
      evalLabel: raw.evalLabel,
      moves: List<String>.unmodifiable(
        sans,
      ),
      bestFrom: bestFrom,
      bestTo: bestTo,
    );
  }

  // ==========================================================
  // Analyze
  // ==========================================================

  void _analyze() {
    final fen =
        state.currentFen.trim();

    if (fen.isEmpty) {
      return;
    }

    if (!engineReady) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        const SnackBar(
          content: Text(
            'Stockfish 19 لم يصبح جاهزًا بعد',
          ),
        ),
      );

      return;
    }

    setState(() {
      pvLines.clear();

      _analysisFen = fen;
    });

    engine.analyze(
      fen,
      depth: depth,
      multiPv: multiPv,
    );
  }

  // ==========================================================
  // Promotion dialog
  // ==========================================================

  Future<String?> _askPromotion() {
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text(
            'اختر قطعة الترقية',
          ),
          content: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p
                  in <String>[
                'q',
                'r',
                'b',
                'n',
              ])
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(
                      ctx,
                      p,
                    );
                  },
                  child: Text(
                    <String, String>{
                      'q': 'وزير',
                      'r': 'رخ',
                      'b': 'فيل',
                      'n': 'حصان',
                    }[p]!,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // ==========================================================
  // Board tap
  // ==========================================================

  Future<void> _onBoardTap(
    String square,
  ) async {
    // --------------------------------------------------------
    // Setup mode
    // --------------------------------------------------------

    if (state.mode == 'setup') {
      if (eraseMode) {
        state.eraseSetupSquare(
          square,
        );

        return;
      }

      if (selectedSetupPiece != null) {
        state.placeSetupPiece(
          square,
          selectedSetupPiece!,
        );

        return;
      }

      state.tapSetupSelect(
        square ==
                state.selectedSquare
            ? null
            : square,
      );

      return;
    }

    // --------------------------------------------------------
    // Play mode
    // --------------------------------------------------------

    if (state.selectedSquare == null) {
      final board =
          GameState.parseBoard(
        state.currentFen
            .split(' ')
            .first,
      );

      final piece =
          board[square];

      final fenParts =
          state.currentFen
              .split(' ');

      final turn =
          fenParts.length > 1
              ? fenParts[1]
              : 'w';

      if (piece != null &&
          piece.startsWith(turn)) {
        state.tapSetupSelect(
          square,
        );

        setState(() {
          targets =
              state
                  .legalTargets(square)
                  .toSet();
        });
      }

      return;
    }

    // --------------------------------------------------------
    // Same square
    // --------------------------------------------------------

    if (square ==
        state.selectedSquare) {
      state.tapSetupSelect(
        null,
      );

      setState(() {
        targets =
            <String>{};
      });

      return;
    }

    // --------------------------------------------------------
    // New piece selection
    // --------------------------------------------------------

    if (!targets.contains(square)) {
      final board =
          GameState.parseBoard(
        state.currentFen
            .split(' ')
            .first,
      );

      final piece =
          board[square];

      final fenParts =
          state.currentFen
              .split(' ');

      final turn =
          fenParts.length > 1
              ? fenParts[1]
              : 'w';

      if (piece != null &&
          piece.startsWith(turn)) {
        state.tapSetupSelect(
          square,
        );

        setState(() {
          targets =
              state
                  .legalTargets(square)
                  .toSet();
        });
      } else {
        state.tapSetupSelect(
          null,
        );

        setState(() {
          targets =
              <String>{};
        });
      }

      return;
    }

    // --------------------------------------------------------
    // Make move
    // --------------------------------------------------------

    final from =
        state.selectedSquare!;

    final board =
        GameState.parseBoard(
      state.currentFen
          .split(' ')
          .first,
    );

    final movingPiece =
        board[from];

    final isPromotion =
        movingPiece != null &&
        movingPiece.length >= 2 &&
        movingPiece.substring(1) ==
            'P' &&
        (
          (
            movingPiece.startsWith('w') &&
            square.endsWith('8')
          ) ||
          (
            movingPiece.startsWith('b') &&
            square.endsWith('1')
          )
        );

    setState(() {
      targets =
          <String>{};
    });

    if (isPromotion) {
      final promotion =
          await _askPromotion();

      if (!mounted) {
        return;
      }

      state.tryMove(
        from,
        square,
        promotion:
            promotion ?? 'q',
      );
    } else {
      state.tryMove(
        from,
        square,
      );
    }
  }

  // ==========================================================
  // Build
  // ==========================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    final boardTheme =
        boardThemes[
          boardThemeIdx
        ];

    final pieceTheme =
        pieceThemes[
          pieceThemeIdx
        ];

    final top =
        pvLines[1];

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'تحليل وضعية ♟️',
        ),
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          padding:
              const EdgeInsets.all(12),

          child: Column(
            children: [
              // =================================================
              // Themes
              // =================================================

              Row(
                children: [
                  Expanded(
                    child:
                        DropdownButtonFormField<int>(
                      decoration:
                          const InputDecoration(
                        labelText:
                            'ثيم الرقعة',
                      ),

                      initialValue:
                          boardThemeIdx,

                      items: [
                        for (
                          int i = 0;
                          i <
                              boardThemes
                                  .length;
                          i++
                        )
                          DropdownMenuItem<int>(
                            value: i,
                            child: Text(
                              boardThemes[
                                i
                              ].name,
                            ),
                          ),
                      ],

                      onChanged: (
                        int? value,
                      ) {
                        setState(() {
                          boardThemeIdx =
                              value ?? 0;
                        });
                      },
                    ),
                  ),

                  const SizedBox(
                    width: 8,
                  ),

                  Expanded(
                    child:
                        DropdownButtonFormField<int>(
                      decoration:
                          const InputDecoration(
                        labelText:
                            'ثيم القطع',
                      ),

                      initialValue:
                          pieceThemeIdx,

                      items: [
                        for (
                          int i = 0;
                          i <
                              pieceThemes
                                  .length;
                          i++
                        )
                          DropdownMenuItem<int>(
                            value: i,
                            child: Text(
                              pieceThemes[
                                i
                              ].name,
                            ),
                          ),
                      ],

                      onChanged: (
                        int? value,
                      ) {
                        setState(() {
                          pieceThemeIdx =
                              value ?? 0;
                        });
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(
                height: 10,
              ),

              // =================================================
              // Board
              // =================================================

              ConstrainedBox(
                constraints:
                    const BoxConstraints(
                  maxWidth: 480,
                ),

                child: BoardWidget(
                  state: state,
                  boardTheme:
                      boardTheme,
                  pieceTheme:
                      pieceTheme,
                  onTap:
                      _onBoardTap,
                  targets:
                      targets,

                  arrowFrom:
                      top != null &&
                              top.bestFrom
                                  .isNotEmpty
                          ? top.bestFrom
                          : null,

                  arrowTo:
                      top != null &&
                              top.bestTo
                                  .isNotEmpty
                          ? top.bestTo
                          : null,
                ),
              ),

              const SizedBox(
                height: 10,
              ),

              // =================================================
              // Board controls
              // =================================================

              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment:
                    WrapAlignment.center,

                children: [
                  FilledButton(
                    onPressed: () {
                      state
                          .enterPlayModeFromSetup();
                    },

                    child:
                        const Text(
                      'وضع اللعب',
                    ),
                  ),

                  OutlinedButton(
                    onPressed: () {
                      state
                          .enterSetupModeFromCurrent();
                    },

                    child:
                        const Text(
                      'إعداد الوضعية',
                    ),
                  ),

                  OutlinedButton(
                    onPressed: () {
                      state.flipBoard();
                    },

                    child:
                        const Text(
                      'قلب الرقعة',
                    ),
                  ),

                  OutlinedButton(
                    onPressed: () {
                      state.startPosition();
                    },

                    child:
                        const Text(
                      'الوضعية الابتدائية',
                    ),
                  ),

                  OutlinedButton(
                    style:
                        OutlinedButton.styleFrom(
                      foregroundColor:
                          Colors.red,
                    ),

                    onPressed: () {
                      state
                          .clearBoardForSetup();
                    },

                    child:
                        const Text(
                      'مسح الرقعة',
                    ),
                  ),
                ],
              ),

              const SizedBox(
                height: 12,
              ),

              // =================================================
              // Setup panel
              // =================================================

              if (state.mode ==
                  'setup')
                SetupPanel(
                  state: state,
                  pieceTheme:
                      pieceTheme,
                  selectedPiece:
                      selectedSetupPiece,
                  eraseMode:
                      eraseMode,

                  onSelectPiece: (
                    String piece,
                  ) {
                    setState(() {
                      selectedSetupPiece =
                          piece;

                      eraseMode =
                          false;
                    });
                  },

                  onToggleErase: () {
                    setState(() {
                      eraseMode =
                          !eraseMode;

                      selectedSetupPiece =
                          null;
                    });
                  },

                  onChanged: () {},
                ),

              const SizedBox(
                height: 12,
              ),

              // =================================================
              // FEN
              // =================================================

              Card(
                child: Padding(
                  padding:
                      const EdgeInsets.all(
                    12,
                  ),

                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment
                            .start,

                    children: [
                      const Text(
                        'FEN',
                        style:
                            TextStyle(
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),

                      const SizedBox(
                        height: 5,
                      ),

                      SelectableText(
                        state.currentFen,
                        style:
                            const TextStyle(
                          fontFamily:
                              'monospace',
                          fontSize: 12,
                        ),
                      ),

                      const SizedBox(
                        height: 8,
                      ),

                      TextField(
                        controller:
                            fenController,

                        textDirection:
                            TextDirection
                                .ltr,

                        textAlign:
                            TextAlign.left,

                        decoration:
                            const InputDecoration(
                          labelText:
                              'الصق FEN هنا',
                          border:
                              OutlineInputBorder(),
                        ),
                      ),

                      const SizedBox(
                        height: 8,
                      ),

                      FilledButton.icon(
                        onPressed: () {
                          final fen =
                              fenController
                                  .text
                                  .trim();

                          if (fen.isEmpty) {
                            return;
                          }

                          final loaded =
                              state.loadFen(
                            fen,
                          );

                          if (!loaded &&
                              mounted) {
                            ScaffoldMessenger
                                .of(
                              context,
                            ).showSnackBar(
                              const SnackBar(
                                content:
                                    Text(
                                  'FEN غير صالح',
                                ),
                              ),
                            );
                          }
                        },

                        icon:
                            const Icon(
                          Icons.download,
                        ),

                        label:
                            const Text(
                          'تحميل FEN',
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(
                height: 12,
              ),

              // =================================================
              // Analysis
              // =================================================

              AnalysisPanel(
                engineStatus:
                    engineStatus,

                engineReady:
                    engineReady,

                analyzing:
                    engine.analyzing,

                depth:
                    depth,

                multiPv:
                    multiPv,

                lines:
                    pvLines,

                onAnalyze:
                    _analyze,

                onStop: () {
                  engine.stop();
                },

                onDepthChanged: (
                  int value,
                ) {
                  setState(() {
                    depth = value;
                  });
                },

                onMultiPvChanged: (
                  int value,
                ) {
                  setState(() {
                    multiPv = value;
                  });
                },

                onSelectLine: (
                  int index,
                ) {
                  // لا نغير وضعية الرقعة
                  // عند اختيار PV.
                },
              ),

              const SizedBox(
                height: 12,
              ),

              // =================================================
              // Move history
              // =================================================

              MoveListPanel(
                history:
                    state.history,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
