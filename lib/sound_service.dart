import 'package:audioplayers/audioplayers.dart';

/// خدمة تشغيل أصوات النقلات (حركة عادية / أكل / كش مات).
///
/// نستخدم AudioPlayer منفصل لكل صوت لتفادي أي تأخير أو تقطيع
/// عند تشغيل نقلات سريعة متتالية (كل مشغل يحمّل ملفه مسبقًا).
class SoundService {
  SoundService() {
    _init();
  }

  final AudioPlayer _movePlayer = AudioPlayer(
    playerId: 'sound_move',
  );

  final AudioPlayer _capturePlayer = AudioPlayer(
    playerId: 'sound_capture',
  );

  final AudioPlayer _checkmatePlayer = AudioPlayer(
    playerId: 'sound_checkmate',
  );

  bool enabled = true;

  Future<void> _init() async {
    try {
      await _movePlayer.setReleaseMode(ReleaseMode.stop);
      await _capturePlayer.setReleaseMode(ReleaseMode.stop);
      await _checkmatePlayer.setReleaseMode(ReleaseMode.stop);

      await _movePlayer.setSource(
        AssetSource('sounds/move.wav'),
      );
      await _capturePlayer.setSource(
        AssetSource('sounds/capture.wav'),
      );
      await _checkmatePlayer.setSource(
        AssetSource('sounds/checkmate.wav'),
      );
    } catch (_) {
      // لا نمنع تشغيل التطبيق إن تعذّر تحميل الصوت.
    }
  }

  Future<void> _play(AudioPlayer player) async {
    if (!enabled) {
      return;
    }

    try {
      await player.stop();
      await player.resume();
    } catch (_) {}
  }

  void playMove() => _play(_movePlayer);

  void playCapture() => _play(_capturePlayer);

  void playCheckmate() => _play(_checkmatePlayer);

  /// نقطة دخول موحّدة تُستدعى من GameState.onSound.
  void playKind(String kind) {
    switch (kind) {
      case 'capture':
        playCapture();
        break;
      case 'checkmate':
        playCheckmate();
        break;
      default:
        playMove();
    }
  }

  void dispose() {
    _movePlayer.dispose();
    _capturePlayer.dispose();
    _checkmatePlayer.dispose();
  }
}
