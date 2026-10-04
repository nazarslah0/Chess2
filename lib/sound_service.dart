import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

/// أصوات Chess2 الجديدة.
/// الملفات القديمة WAV أزيلت واستُبدلت بالكامل بالأصوات MP3 التي
/// زوّدنا بها المستخدم.
class SoundService {
  SoundService() {
    _init();
  }

  final Map<String, AudioPlayer> _players = {
    'move': AudioPlayer(playerId: 'chess2_move'),
    'capture': AudioPlayer(playerId: 'chess2_take'),
    'check': AudioPlayer(playerId: 'chess2_snap'),
    'checkmate': AudioPlayer(playerId: 'chess2_snap_mate'),
    'castle': AudioPlayer(playerId: 'chess2_swap'),
    'promotion': AudioPlayer(playerId: 'chess2_swap_promotion'),
    'game_over': AudioPlayer(playerId: 'chess2_rewind'),
  };

  static const Map<String, String> _files = {
    'move': 'sounds/move.mp3',
    'capture': 'sounds/take.mp3',
    'check': 'sounds/snap.mp3',
    'checkmate': 'sounds/snap.mp3',
    'castle': 'sounds/swap.mp3',
    'promotion': 'sounds/swap.mp3',
    'game_over': 'sounds/rewind.mp3',
  };

  bool enabled = true;
  Future<void>? _ready;

  Future<void> _init() {
    _ready ??= _preparePlayers();
    return _ready!;
  }

  Future<void> _preparePlayers() async {
    for (final entry in _players.entries) {
      try {
        final player = entry.value;
        await player.setReleaseMode(ReleaseMode.stop);
        await player.setSource(AssetSource(_files[entry.key]!));
      } catch (_) {
        // يبقى التطبيق يعمل حتى إذا تعذر تحميل مؤثر صوتي.
      }
    }
  }

  /// يبدأ الصوت فورًا بعد تجهيز المصدر. لا نستخدم await في مسار
  /// النقلة نفسها حتى لا يتأخر تحديث الرقعة بسبب الصوت.
  void _playNow(String kind) {
    if (!enabled) return;

    final player = _players[kind];
    if (player == null) return;

    () async {
      try {
        await _ready;
        await player.stop();
        await player.seek(Duration.zero);
        unawaited(player.resume());
      } catch (_) {}
    }();
  }

  void playMove() => _playNow('move');
  void playCapture() => _playNow('capture');
  void playCheck() => _playNow('check');
  void playCheckmate() => _playNow('checkmate');
  void playCastle() => _playNow('castle');
  void playPromotion() => _playNow('promotion');
  void playGameOver() => _playNow('game_over');

  void playKind(String kind) {
    if (_players.containsKey(kind)) {
      _playNow(kind);
    } else {
      _playNow('move');
    }
  }

  void dispose() {
    for (final player in _players.values) {
      player.dispose();
    }
  }
}
