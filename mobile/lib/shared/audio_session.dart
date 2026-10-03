import 'package:just_audio/just_audio.dart';

class AudioSession {
  static final players = <AudioPlayer>{};
  static Future<void> stopAll({AudioPlayer? except}) async {
    for (final player in players.toList()) {
      if (player != except) await player.pause();
    }
  }
}
