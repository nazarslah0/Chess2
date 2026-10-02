import 'package:flutter/material.dart';
import 'package:chess/chess.dart' as ch;

/// ============================================================
/// Board Themes
/// ============================================================

class BoardTheme {
  final String name;
  final Color light;
  final Color dark;
  final Color lastMove;
  final Color checkColor;
  final Color selected;
  final Color target;
  final Color border;

  const BoardTheme({
    required this.name,
    required this.light,
    required this.dark,
    required this.lastMove,
    required this.checkColor,
    required this.selected,
    required this.target,
    required this.border,
  });
}

/// ============================================================
/// Piece Themes
/// ============================================================

class PieceTheme {
  final String name;

  final Color whiteFill;
  final Color whiteStroke;

  final Color blackFill;
  final Color blackStroke;

  final String? assetFolder;

  const PieceTheme({
    required this.name,
    required this.whiteFill,
    required this.whiteStroke,
    required this.blackFill,
    required this.blackStroke,
    this.assetFolder,
  });

  String assetPath(
    String colorLetter,
    String typeLetter,
  ) {
    return 'assets/pieces/$assetFolder/'
        '$colorLetter$typeLetter.png';
  }
}

/// ============================================================
/// Board Themes List
/// ============================================================

const List<BoardTheme> boardThemes = [
  BoardTheme(
    name: 'كلاسيكي',
    light: Color(0xFFF0D9B5),
    dark: Color(0xFFB58863),
    lastMove: Color(0x552AA198),
    checkColor: Color(0xFFDC2626),
    selected: Color(0x552563EB),
    target: Color(0x552563EB),
    border: Color(0xFF3A2E22),
  ),
  BoardTheme(
    name: 'أخضر',
    light: Color(0xFFEEEED2),
    dark: Color(0xFF769656),
    lastMove: Color(0x55F6F669),
    checkColor: Color(0xFFDC2626),
    selected: Color(0x552563EB),
    target: Color(0x552563EB),
    border: Color(0xFF2E3B25),
  ),
  BoardTheme(
    name: 'أزرق',
    light: Color(0xFFDEE3E6),
    dark: Color(0xFF6E8CA0),
    lastMove: Color(0x55FFD54A),
    checkColor: Color(0xFFDC2626),
    selected: Color(0x552563EB),
    target: Color(0x552563EB),
    border: Color(0xFF23303A),
  ),
  BoardTheme(
    name: 'داكن',
    light: Color(0xFF4A4A4A),
    dark: Color(0xFF262626),
    lastMove: Color(0x556EE7B7),
    checkColor: Color(0xFFEF4444),
    selected: Color(0x554F86F7),
    target: Color(0x554F86F7),
    border: Color(0xFF141414),
  ),
  BoardTheme(
    name: 'رخامي',
    light: Color(0xFFEDEAE0),
    dark: Color(0xFF8C7B6B),
    lastMove: Color(0x55C9A25E),
    checkColor: Color(0xFFB3261E),
    selected: Color(0x556750A4),
    target: Color(0x556750A4),
    border: Color(0xFF463B30),
  ),
  BoardTheme(
    name: 'أخضر (المجموعة المرفقة)',
    light: Color(0xFFFFF2D4),
    dark: Color(0xFF8CC936),
    lastMove: Color(0x55FFD54A),
    checkColor: Color(0xFFDC2626),
    selected: Color(0x552563EB),
    target: Color(0x552563EB),
    border: Color(0xFF2E3B25),
  ),
  BoardTheme(
    name: 'بني (المجموعة المرفقة)',
    light: Color(0xFFFFF2D4),
    dark: Color(0xFFDE925A),
    lastMove: Color(0x552AA198),
    checkColor: Color(0xFFDC2626),
    selected: Color(0x552563EB),
    target: Color(0x552563EB),
    border: Color(0xFF3A2E22),
  ),
  BoardTheme(
    name: 'أزرق (المجموعة المرفقة)',
    light: Color(0xFFFFFFFF),
    dark: Color(0xFF96DBFF),
    lastMove: Color(0x55FFD54A),
    checkColor: Color(0xFFDC2626),
    selected: Color(0x552563EB),
    target: Color(0x552563EB),
    border: Color(0xFF23303A),
  ),
];

/// مظهر تحليل المباريات القريب من واجهة Chess.com الظاهرة في الطلب.
const BoardTheme chessComBoardTheme = BoardTheme(
  name: 'Chess.com Green',
  light: Color(0xFFF0F0D0),
  dark: Color(0xFF769656),
  lastMove: Color(0x99F6F669),
  checkColor: Color(0xFFE05252),
  selected: Color(0x99F6F669),
  target: Color(0xAA5B7F3A),
  border: Color(0xFF5C7042),
);

const PieceTheme chessComPieceTheme = PieceTheme(
  name: 'Chess.com — Staunty',
  whiteFill: Color(0xFFF7F7F7),
  whiteStroke: Color(0xFF555555),
  blackFill: Color(0xFF333333),
  blackStroke: Color(0xFFD8D8D8),
  assetFolder: 'Chesscom',
);

/// ============================================================
/// Piece Themes List
/// ============================================================

const List<PieceTheme> pieceThemes = [
  PieceTheme(
    name: 'قطع حقيقية — كلاسيكي',
    whiteFill: Color(0xFFFCFCFC),
    whiteStroke: Color(0xFF222222),
    blackFill: Color(0xFF161616),
    blackStroke: Color(0xFFEAEAEA),
    assetFolder: 'classic',
  ),
  PieceTheme(
    name: 'قطع حقيقية — مسطح',
    whiteFill: Color(0xFFFCFCFC),
    whiteStroke: Color(0xFF222222),
    blackFill: Color(0xFF161616),
    blackStroke: Color(0xFFEAEAEA),
    assetFolder: 'flat',
  ),
  PieceTheme(
    name: 'قطع حقيقية — خشبي',
    whiteFill: Color(0xFFFCFCFC),
    whiteStroke: Color(0xFF222222),
    blackFill: Color(0xFF161616),
    blackStroke: Color(0xFFEAEAEA),
    assetFolder: 'wood',
  ),
  PieceTheme(
    name: 'مرسومة — كلاسيكي أبيض/أسود',
    whiteFill: Color(0xFFFCFCFC),
    whiteStroke: Color(0xFF222222),
    blackFill: Color(0xFF161616),
    blackStroke: Color(0xFFEAEAEA),
  ),
  PieceTheme(
    name: 'مرسومة — خشبي',
    whiteFill: Color(0xFFF3E1C2),
    whiteStroke: Color(0xFF5C3A21),
    blackFill: Color(0xFF6B4226),
    blackStroke: Color(0xFFF3E1C2),
  ),
  PieceTheme(
    name: 'مرسومة — نيون',
    whiteFill: Color(0xFFB6FFF5),
    whiteStroke: Color(0xFF0891B2),
    blackFill: Color(0xFF7C3AED),
    blackStroke: Color(0xFFE9D5FF),
  ),
  PieceTheme(
    name: 'مرسومة — ذهبي/فضي',
    whiteFill: Color(0xFFE5E7EB),
    whiteStroke: Color(0xFF4B5563),
    blackFill: Color(0xFFB8860B),
    blackStroke: Color(0xFFFFF3CD),
  ),
];

/// ============================================================
/// Move Entry
/// ============================================================

class MoveEntry {
  final String san;
  final String color;

  const MoveEntry(
    this.san,
    this.color,
  );
}

/// ============================================================
/// Game State
/// ============================================================

class GameState extends ChangeNotifier {
  static const String files = 'abcdefgh';

  static const String startFen =
      'rnbqkbnr/pppppppp/8/8/8/8/'
      'PPPPPPPP/RNBQKBNR w KQkq - 0 1';

  /// مكتبة الشطرنج الأساسية.
  ch.Chess chess = ch.Chess();

  /// play / setup
  String mode = 'play';

  /// لوحة الإعداد.
  ///
  /// القيمة مثل:
  /// wK = ملك أبيض
  /// bQ = وزير أسود
  /// wP = بيدق أبيض
  Map<String, String> setupBoard =
      <String, String>{};

  /// الدور في وضع الإعداد.
  String setupTurn = 'w';

  /// حقوق التبييت.
  bool ck = true;
  bool cq = true;
  bool ckb = true;
  bool cqb = true;

  /// En Passant square.
  String ep = '-';

  /// آخر نقلة.
  String? lastFrom;
  String? lastTo;

  /// المربع المحدد.
  String? selectedSquare;

  /// قلب الرقعة.
  bool flipped = false;

  /// سجل النقلات.
  List<MoveEntry> history =
      <MoveEntry>[];

  /// حالة الوضعية.
  String legalMessage =
      'وضعية قانونية';

  bool legal = true;

  // ==========================================================
  // Current FEN
  // ==========================================================

  /// الـ FEN الحالي.
  ///
  /// مهم جدًا:
  /// board_widget.dart يعتمد عليه.
  String get currentFen {
    if (mode == 'setup') {
      return buildSetupFen();
    }

    try {
      return chess.fen;
    } catch (_) {
      return startFen;
    }
  }

  // ==========================================================
  // Refresh
  // ==========================================================

  /// تحديث واجهة التطبيق بعد تعديل مباشر.
  ///
  /// مطلوب من panels.dart.
  void refresh() {
    _validate();
    notifyListeners();
  }

  // ==========================================================
  // Start position
  // ==========================================================

  void startPosition() {
    chess = ch.Chess();

    mode = 'play';

    setupBoard =
        <String, String>{};

    setupTurn = 'w';

    ck = true;
    cq = true;
    ckb = true;
    cqb = true;

    ep = '-';

    lastFrom = null;
    lastTo = null;
    selectedSquare = null;

    history =
        <MoveEntry>[];

    _validate();

    notifyListeners();
  }

  // ==========================================================
  // Clear board for setup
  // ==========================================================

  void clearBoardForSetup() {
    setupBoard =
        <String, String>{};

    mode = 'setup';

    setupTurn = 'w';

    ck = false;
    cq = false;
    ckb = false;
    cqb = false;

    ep = '-';

    lastFrom = null;
    lastTo = null;
    selectedSquare = null;

    history =
        <MoveEntry>[];

    _validate();

    notifyListeners();
  }

  // ==========================================================
  // Enter setup from current position
  // ==========================================================

  void enterSetupModeFromCurrent() {
    final fen =
        chess.fen.trim();

    final parts =
        fen.split(RegExp(r'\s+'));

    if (parts.length < 4) {
      return;
    }

    setupBoard =
        parseBoard(parts[0]);

    setupTurn =
        parts[1] == 'b'
            ? 'b'
            : 'w';

    final rights =
        parts[2];

    ck =
        rights.contains('K');

    cq =
        rights.contains('Q');

    ckb =
        rights.contains('k');

    cqb =
        rights.contains('q');

    ep =
        parts[3];

    _sanitizeSetupRights();

    mode = 'setup';

    selectedSquare = null;

    _validate();

    notifyListeners();
  }

  // ==========================================================
  // Return from setup to play
  // ==========================================================

  bool enterPlayModeFromSetup() {
    // إذا كنا في وضع اللعب أصلًا (لم يدخل المستخدم وضع الإعداد
    // بعد)، فإن setupBoard تكون فارغة، وبناء FEN منها كان يمسح
    // الرقعة بالكامل عند الضغط على "وضع اللعب". لا شيء لفعله
    // هنا في هذه الحالة.
    if (mode != 'setup') {
      return true;
    }

    _sanitizeSetupRights();

    final fen =
        buildSetupFen();

    final test =
        ch.Chess();

    try {
      final result =
          test.load(fen);

      if (result == false) {
        legal = false;

        legalMessage =
            'الوضعية غير صالحة';

        notifyListeners();

        return false;
      }
    } catch (_) {
      legal = false;

      legalMessage =
          'تعذر تحميل الوضعية';

      notifyListeners();

      return false;
    }

    chess = test;

    mode = 'play';

    lastFrom = null;
    lastTo = null;
    selectedSquare = null;

    history =
        <MoveEntry>[];

    _validate();

    notifyListeners();

    return true;
  }

  // ==========================================================
  // Load FEN
  // ==========================================================

  bool loadFen(String fen) {
    final clean =
        fen.trim();

    if (clean.isEmpty) {
      legal = false;
      legalMessage =
          'FEN فارغ';

      notifyListeners();

      return false;
    }

    final test =
        ch.Chess();

    try {
      final result =
          test.load(clean);

      if (result == false) {
        legal = false;

        legalMessage =
            'FEN غير صالح';

        notifyListeners();

        return false;
      }
    } catch (_) {
      legal = false;

      legalMessage =
          'FEN غير صالح';

      notifyListeners();

      return false;
    }

    chess = test;

    mode = 'play';

    lastFrom = null;
    lastTo = null;
    selectedSquare = null;

    history =
        <MoveEntry>[];

    _validate();

    notifyListeners();

    return true;
  }

  // ==========================================================
  // Parse FEN board
  // ==========================================================

  static Map<String, String> parseBoard(
    String boardPart,
  ) {
    final map =
        <String, String>{};

    final ranks =
        boardPart.split('/');

    if (ranks.length != 8) {
      return map;
    }

    for (int rankIndex = 0;
        rankIndex < 8;
        rankIndex++) {
      int fileIndex = 0;

      final row =
          ranks[rankIndex];

      for (final character
          in row.split('')) {
        final number =
            int.tryParse(character);

        if (number != null) {
          fileIndex += number;
          continue;
        }

        if (fileIndex < 0 ||
            fileIndex >= 8) {
          continue;
        }

        final color =
            character ==
                    character.toUpperCase()
                ? 'w'
                : 'b';

        final type =
            character.toUpperCase();

        final square =
            '${files[fileIndex]}'
            '${8 - rankIndex}';

        map[square] =
            '$color$type';

        fileIndex++;
      }
    }

    return map;
  }

  // ==========================================================
  // Convert board map to FEN board
  // ==========================================================

  static String _mapToBoardPart(
    Map<String, String> board,
  ) {
    final rows =
        <String>[];

    for (int rank = 8;
        rank >= 1;
        rank--) {
      int empty = 0;

      final row =
          StringBuffer();

      for (int file = 0;
          file < 8;
          file++) {
        final square =
            '${files[file]}$rank';

        final piece =
            board[square];

        if (piece == null) {
          empty++;
          continue;
        }

        if (empty > 0) {
          row.write(empty);
          empty = 0;
        }

        final color =
            piece.isNotEmpty
                ? piece[0]
                : 'w';

        final type =
            piece.length > 1
                ? piece[1].toUpperCase()
                : '';

        if (color == 'w') {
          row.write(type);
        } else {
          row.write(
            type.toLowerCase(),
          );
        }
      }

      if (empty > 0) {
        row.write(empty);
      }

      rows.add(
        row.toString(),
      );
    }

    return rows.join('/');
  }

  // ==========================================================
  // Sanitize castling / EP
  // ==========================================================

  void _sanitizeSetupRights() {
    // White king side.
    ck = ck &&
        setupBoard['e1'] == 'wK' &&
        setupBoard['h1'] == 'wR';

    // White queen side.
    cq = cq &&
        setupBoard['e1'] == 'wK' &&
        setupBoard['a1'] == 'wR';

    // Black king side.
    ckb = ckb &&
        setupBoard['e8'] == 'bK' &&
        setupBoard['h8'] == 'bR';

    // Black queen side.
    cqb = cqb &&
        setupBoard['e8'] == 'bK' &&
        setupBoard['a8'] == 'bR';

    // EP must be a valid square.
    if (ep != '-' &&
        !_validSquare(ep)) {
      ep = '-';
    }
  }

  // ==========================================================
  // Build setup FEN
  // ==========================================================

  String buildSetupFen() {
    _sanitizeSetupRights();

    final rights =
        StringBuffer();

    if (ck) {
      rights.write('K');
    }

    if (cq) {
      rights.write('Q');
    }

    if (ckb) {
      rights.write('k');
    }

    if (cqb) {
      rights.write('q');
    }

    final castling =
        rights.isEmpty
            ? '-'
            : rights.toString();

    final side =
        setupTurn == 'b'
            ? 'b'
            : 'w';

    final enPassant =
        _validSquare(ep)
            ? ep
            : '-';

    return '${_mapToBoardPart(setupBoard)} '
        '$side '
        '$castling '
        '$enPassant '
        '0 1';
  }

  // ==========================================================
  // Place setup piece
  // ==========================================================

  void placeSetupPiece(
    String square,
    String piece,
  ) {
    if (!_validSquare(square)) {
      return;
    }

    if (piece.length != 2) {
      return;
    }

    final color =
        piece[0];

    final type =
        piece[1].toUpperCase();

    if (color != 'w' &&
        color != 'b') {
      return;
    }

    if (!'KQRBNP'.contains(type)) {
      return;
    }

    final normalized =
        '$color$type';

    // يسمح بملك واحد فقط لكل لون.
    if (type == 'K') {
      final oldKings =
          setupBoard.entries
              .where(
                (entry) =>
                    entry.value ==
                        normalized &&
                    entry.key != square,
              )
              .map(
                (entry) => entry.key,
              )
              .toList();

      for (final oldSquare
          in oldKings) {
        setupBoard.remove(
          oldSquare,
        );
      }
    }

    setupBoard[square] =
        normalized;

    _sanitizeSetupRights();

    selectedSquare =
        square;

    _validate();

    notifyListeners();
  }

  // ==========================================================
  // Erase setup square
  // ==========================================================

  void eraseSetupSquare(
    String square,
  ) {
    if (!_validSquare(square)) {
      return;
    }

    setupBoard.remove(
      square,
    );

    _sanitizeSetupRights();

    selectedSquare = null;

    _validate();

    notifyListeners();
  }

  // ==========================================================
  // Select setup square
  // ==========================================================

  void tapSetupSelect(
    String? square,
  ) {
    if (square != null &&
        !_validSquare(square)) {
      selectedSquare = null;
    } else {
      selectedSquare =
          square;
    }

    notifyListeners();
  }

  // ==========================================================
  // Legal targets
  // ==========================================================

  // ==========================================================
  // مساعدات قراءة النقلات من حزمة chess (Map أو Move)
  // ==========================================================

  static String? _readSquare(dynamic item, String key) {
    try {
      if (item is Map) {
        final v = item[key];
        return v?.toString();
      }
    } catch (_) {}

    try {
      final d = item as dynamic;
      return key == 'from'
          ? d.fromAlgebraic as String
          : d.toAlgebraic as String;
    } catch (_) {}

    return null;
  }

  static String? _moveTo(dynamic item) => _readSquare(item, 'to');

  /// يبحث عن النقلة القانونية المطابقة لـ from/to/promotion
  /// ويعيدها كـ Map (تحتوي على san) أو null.
  static Map<String, dynamic>? findLegalMove(
    ch.Chess game,
    String from,
    String to,
    String? promotion,
  ) {
    try {
      final moves = game.moves(<String, dynamic>{'verbose': true});

      for (final item in moves) {
        if (_readSquare(item, 'from') != from ||
            _readSquare(item, 'to') != to) {
          continue;
        }

        String? promo;
        String san = '';

        if (item is Map) {
          promo = item['promotion']?.toString().toLowerCase();
          san = (item['san'] ?? '').toString();
        } else {
          try {
            promo = (item as dynamic).promotion?.toString().toLowerCase();
          } catch (_) {}
          try {
            san = game.move_to_san(item);
          } catch (_) {}
        }

        if (promotion != null &&
            promo != null &&
            promo.isNotEmpty &&
            promo != promotion.toLowerCase()) {
          continue;
        }

        return <String, dynamic>{
          'from': from,
          'to': to,
          'san': san.isEmpty ? '$from$to' : san,
        };
      }
    } catch (_) {}

    return null;
  }

  Set<String> legalTargets(
    String from,
  ) {
    if (mode != 'play') {
      return <String>{};
    }

    if (!_validSquare(from)) {
      return <String>{};
    }

    try {
      final raw =
          chess.moves(
        <String, dynamic>{
          'square': from,
          'verbose': true,
        },
      );

      final result =
          <String>{};

      // مع verbose=true تعيد حزمة chess عناصر Map
      // (from / to / san / promotion ...)، لكن قد تعيد
      // كائنات Move في إصدارات أخرى، لذلك ندعم الحالتين.
      for (final item in raw) {
        final sq = _moveTo(item);
        if (sq != null) {
          result.add(sq);
        }
      }

      return result;
    } catch (_) {
      return <String>{};
    }
  }

  /// يُستدعى بعد كل نقلة ناجحة لتشغيل صوت مناسب.
  /// القيمة: 'move' أو 'capture' أو 'checkmate'.
  void Function(String kind)? onSound;

  // ==========================================================
  // Make move
  // ==========================================================

  bool tryMove(
    String from,
    String to, {
    String? promotion,
  }) {
    if (mode != 'play') {
      return false;
    }

    if (!_validSquare(from) ||
        !_validSquare(to)) {
      return false;
    }

    final args =
        <String, dynamic>{
      'from': from,
      'to': to,
    };

    if (promotion != null) {
      args['promotion'] =
          promotion;
    }

    // نحدد إن كانت النقلة أكلًا *قبل* تنفيذها (بما في ذلك
    // الأخذ في المرور en passant) لأن اللوحة تتغيّر بعد move().
    bool isCapture = false;

    try {
      final boardBefore =
          parseBoard(
        chess.fen
            .split(' ')
            .first,
      );

      if (boardBefore[to] != null) {
        isCapture = true;
      } else {
        final moving =
            boardBefore[from];

        if (moving != null &&
            moving.length == 2 &&
            moving[1] == 'P' &&
            from[0] != to[0]) {
          // بيدق يتحرك قطريًا إلى مربع فارغ = أخذ بالمرور.
          isCapture = true;
        }
      }
    } catch (_) {}

    // نحفظ لون اللاعب الذي ينقل *قبل* تنفيذ النقلة،
    // لأن chess.turn يتغير فور نجاح move().
    //
    // ملاحظة: chess.getHistory({'verbose': true}) يعيد
    // كائنات Move حقيقية (ليست Map)، وMove لا تملك حقل
    // 'san' أو 'color' جاهزًا، لذلك القراءة القديمة
    // (verbose.last as Map) كانت تفشل بصمت في كل مرة،
    // وتجعل كل نقلة تُسجَّل كأنها نقلة أبيض.
    final movingColor =
        chess.turn == ch.Color.WHITE
            ? 'w'
            : 'b';

    try {
      final result =
          chess.move(args);

      if (result == false) {
        return false;
      }

      String san = '';
      final color = movingColor;

      try {
        final simple =
            chess.getHistory();

        if (simple.isNotEmpty) {
          san =
              '${simple.last}';
        }
      } catch (_) {}

      if (san.isEmpty) {
        san =
            '$from-$to';
      }

      history = [
        ...history,
        MoveEntry(
          san,
          color,
        ),
      ];

      lastFrom = from;
      lastTo = to;

      selectedSquare = null;

      _validate();

      // ------------------------------------------------------
      // تشغيل الصوت المناسب (بالأولوية: كش مات/نهاية اللعبة
      // > ترقية > تبييت > كش > أكل > حركة عادية).
      // ------------------------------------------------------

      bool isCheckmateNow = false;
      bool isDrawNow = false;
      bool isCheckNow = false;

      try {
        isCheckmateNow = chess.in_checkmate;
      } catch (_) {}

      try {
        isDrawNow = chess.in_stalemate;
      } catch (_) {}

      if (!isDrawNow) {
        try {
          isDrawNow = chess.in_draw;
        } catch (_) {}
      }

      try {
        isCheckNow =
            !isCheckmateNow && chess.in_check;
      } catch (_) {}

      final isCastle =
          san.startsWith('O-O');

      if (isCheckmateNow) {
        onSound?.call('checkmate');
      } else if (isDrawNow) {
        onSound?.call('game_over');
      } else if (promotion != null) {
        onSound?.call('promotion');
      } else if (isCastle) {
        onSound?.call('castle');
      } else if (isCheckNow) {
        onSound?.call('check');
      } else if (isCapture) {
        onSound?.call('capture');
      } else {
        onSound?.call('move');
      }

      notifyListeners();

      return true;
    } catch (_) {
      return false;
    }
  }

  // ==========================================================
  // Flip board
  // ==========================================================

  void flipBoard() {
    flipped = !flipped;
    notifyListeners();
  }

  // ==========================================================
  // Validation
  // ==========================================================

  void _validate() {
    if (mode == 'play') {
      try {
        legal = true;

        if (chess.in_checkmate) {
          legalMessage =
              'كش مات';
        } else if (chess.in_check) {
          legalMessage =
              'كش';
        } else if (chess.in_stalemate) {
          legalMessage =
              'تعادل — Stalemate';
        } else {
          legalMessage =
              'وضعية قانونية';
        }
      } catch (_) {
        legal = false;

        legalMessage =
            'تعذر التحقق من الوضعية';
      }

      return;
    }

    // --------------------------------------------------------
    // Setup validation
    // --------------------------------------------------------

    final whiteKings =
        setupBoard.values
            .where(
              (piece) =>
                  piece == 'wK',
            )
            .length;

    final blackKings =
        setupBoard.values
            .where(
              (piece) =>
                  piece == 'bK',
            )
            .length;

    if (whiteKings != 1 ||
        blackKings != 1) {
      legal = false;

      legalMessage =
          'يجب وضع ملك أبيض وملك أسود واحد';

      return;
    }

    final fen =
        buildSetupFen();

    try {
      final test =
          ch.Chess();

      final result =
          test.load(fen);

      legal =
          result != false;

      legalMessage =
          legal
              ? 'وضعية قانونية'
              : 'الوضعية غير قانونية';
    } catch (_) {
      legal = false;

      legalMessage =
          'الوضعية غير قانونية';
    }
  }

  // ==========================================================
  // Square validation
  // ==========================================================

  static bool _validSquare(
    String square,
  ) {
    return RegExp(
      r'^[a-h][1-8]$',
    ).hasMatch(square);
  }
}
