import 'package:audioplayers/audioplayers.dart';

/// خدمة تشغيل أصوات الشطرنج: حركة عادية / أكل / كش / كش مات
/// / تبييت (Castle) / ترقية / نهاية اللعبة.
///
/// نستخدم AudioPlayer منفصل لكل صوت لتفادي أي تأخير أو تقطيع
/// عند تشغيل نقلات سريعة متتالية (كل مشغل يحمّل ملفه مسبقًا).
class SoundService {
  SoundService() {
    _init();
  }

  final Map<String, AudioPlayer> _players = {
    'move': AudioPlayer(playerId: 'sound_move'),
    'capture': AudioPlayer(playerId: 'sound_capture'),
    'check': AudioPlayer(playerId: 'sound_check'),
    'checkmate':
        AudioPlayer(playerId: 'sound_checkmate'),
    'castle': AudioPlayer(playerId: 'sound_castle'),
    'promotion':
        AudioPlayer(playerId: 'sound_promotion'),
    'game_over':
        AudioPlayer(playerId: 'sound_game_over'),
  };

  static const Map<String, String> _files = {
    'move': 'sounds/move.wav',
    'capture': 'sounds/capture.wav',
    'check': 'sounds/check.wav',
    'checkmate': 'sounds/checkmate.wav',
    'castle': 'sounds/castle.wav',
    'promotion': 'sounds/promotion.wav',
    'game_over': 'sounds/game_over.wav',
  };

  bool enabled = true;

  Future<void> _init() async {
    for (final entry in _players.entries) {
      try {
        await entry.value
            .setReleaseMode(ReleaseMode.stop);

        await entry.value.setSource(
          AssetSource(_files[entry.key]!),
        );
      } catch (_) {
        // لا نمنع تشغيل التطبيق إن تعذّر تحميل صوت واحد.
      }
    }
  }

  Future<void> _play(String kind) async {
    if (!enabled) {
      return;
    }

    final player = _players[kind];

    if (player == null) {
      return;
    }

    try {
      await player.stop();
      await player.resume();
    } catch (_) {}
  }

  void playMove() => _play('move');

  void playCapture() => _play('capture');

  void playCheck() => _play('check');

  void playCheckmate() => _play('checkmate');

  void playCastle() => _play('castle');

  void playPromotion() => _play('promotion');

  void playGameOver() => _play('game_over');

  /// نقطة دخول موحّدة تُستدعى من GameState.onSound.
  /// القيم المدعومة: move / capture / check / checkmate /
  /// castle / promotion / game_over.
  void playKind(String kind) {
    if (_players.containsKey(kind)) {
      _play(kind);
    } else {
      playMove();
    }
  }

  void dispose() {
    for (final p in _players.values) {
      p.dispose();
    }
  }
}
