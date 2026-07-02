import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';

class GlobalAudioPlayer {
  static final GlobalAudioPlayer _instance = GlobalAudioPlayer._internal();
  factory GlobalAudioPlayer() => _instance;

  GlobalAudioPlayer._internal() {
    _audioPlayer.setReleaseMode(ReleaseMode.loop);
    _audioPlayer.onPlayerStateChanged.listen((state) {
      isPlaying.value = state == PlayerState.playing;
    });
  }

  final AudioPlayer _audioPlayer = AudioPlayer();
  
  final ValueNotifier<String?> currentUrl = ValueNotifier<String?>(null);
  final ValueNotifier<bool> isPlaying = ValueNotifier<bool>(false);

  Future<void> play(String url) async {
    if (currentUrl.value == url && isPlaying.value) return; 
    
    if (currentUrl.value != url) {
      await stop();
    }
    
    currentUrl.value = url;
    await _audioPlayer.play(UrlSource(url));
  }

  Future<void> pause() async {
    await _audioPlayer.pause();
  }

  Future<void> stop() async {
    await _audioPlayer.stop();
  }

  void dispose() {
    _audioPlayer.dispose();
  }
}
