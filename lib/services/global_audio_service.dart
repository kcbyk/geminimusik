import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';
import 'music_service.dart';
import 'media_session_service.dart';
import '../models/song_model.dart';

/// Chat ekranından müzik çalmak için global singleton ses servisi.
/// Arka planda ve telefon ekranı kilitliyken bile çalmayı sürdürür.
class GlobalAudioService extends ChangeNotifier {
  static final GlobalAudioService instance = GlobalAudioService._();
  
  GlobalAudioService._() {
    _initAudioContext();
    _initListeners();
  }

  final AudioPlayer _player = AudioPlayer();
  final MusicService _musicService = MusicService();

  String? currentTitle;
  String? currentArtist;
  String? currentCover;
  PlayerState playerState = PlayerState.stopped;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  bool isLoading = false;
  String? errorMessage;

  // Oynatıcı görünüm kontrolleri (Gizle/Aç/Küçült)
  bool isMinimized = false;
  bool isHidden = false;

  bool get isPlaying => playerState == PlayerState.playing;
  bool get hasTrack => currentTitle != null;

  /// Telefon kilitliyken ve arka planda çalabilmesi için AudioContext yapılandırması
  void _initAudioContext() {
    try {
      AudioPlayer.global.setAudioContext(
        AudioContext(
          android: AudioContextAndroid(
            isSpeakerphoneOn: false,
            stayAwake: true,
            contentType: AndroidContentType.music,
            usageType: AndroidUsageType.media,
            audioFocus: AndroidAudioFocus.gain,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
          ),
        ),
      );
    } catch (e) {
      debugPrint('AudioContext init hatasi: $e');
    }
  }

  void _initListeners() {
    _player.onPlayerStateChanged.listen((s) {
      playerState = s;
      if (s == PlayerState.playing) isLoading = false;
      _syncMediaSession();
      notifyListeners();
    });
    _player.onPositionChanged.listen((p) {
      position = p;
      notifyListeners();
    });
    _player.onDurationChanged.listen((d) {
      duration = d;
      notifyListeners();
    });
    _player.onPlayerComplete.listen((_) {
      playerState = PlayerState.stopped;
      position = Duration.zero;
      _syncMediaSession();
      notifyListeners();
    });
  }

  void _syncMediaSession() {
    if (hasTrack) {
      updateWebMediaSession(
        title: currentTitle ?? 'Şarkı',
        artist: currentArtist ?? 'AI Music Hub',
        artworkUrl: currentCover,
        isPlaying: isPlaying,
        onPlay: () => pauseOrResume(),
        onPause: () => pauseOrResume(),
        onStop: () => stop(),
      );
    } else {
      clearWebMediaSession();
    }
  }

  // --- Oynatıcıyı Gizleme / Açma / Küçültme Metodları ---
  void toggleMinimized() {
    isMinimized = !isMinimized;
    notifyListeners();
  }

  void setMinimized(bool val) {
    isMinimized = val;
    notifyListeners();
  }

  void toggleHidden() {
    isHidden = !isHidden;
    notifyListeners();
  }

  void setHidden(bool val) {
    isHidden = val;
    notifyListeners();
  }

  void showPlayer() {
    isHidden = false;
    isMinimized = false;
    notifyListeners();
  }

  void hidePlayer() {
    isHidden = true;
    notifyListeners();
  }

  Future<void> searchAndPlay(String query) async {
    isLoading = true;
    errorMessage = null;
    currentTitle = query;
    currentArtist = null;
    currentCover = null;
    // Yeni şarkı başladığında oynatıcıyı otomatik aç
    isHidden = false;
    isMinimized = false;
    notifyListeners();

    try {
      final results = await _musicService.searchSongs(query);
      if (results.isEmpty) {
        errorMessage = 'Şarkı bulunamadı';
        isLoading = false;
        notifyListeners();
        return;
      }
      await _playItem(results.first);
    } catch (e) {
      errorMessage = 'Hata: ';
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _playItem(SongItem song) async {
    currentTitle = song.title;
    currentArtist = song.artist;
    currentCover = song.thumbnailUrl;
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    _syncMediaSession();

    try {
      await _player.stop();
      String? audioUrl = song.directUrl;
      if (audioUrl == null || audioUrl.contains('youtube') || audioUrl.contains('youtu.be')) {
        final ytId = MusicService.extractYouTubeId(audioUrl) ?? MusicService.extractYouTubeId(song.id);
        if (ytId != null) {
          // 1. Birincil doğrudan MP3 motoru
          audioUrl = await _musicService.getDirectMp3Link(ytId);
          // 2. Yedek çoklu anahtarlı ytstream motoru
          if (audioUrl == null || audioUrl.isEmpty) {
            audioUrl = await _musicService.getRapidApiAudioStream(ytId);
          }
        }
      }
      if (audioUrl == null || audioUrl.isEmpty) {
        errorMessage = 'Ses kaynağı bulunamadı';
        isLoading = false;
        notifyListeners();
        return;
      }
      await _player.play(UrlSource(audioUrl));
    } catch (e) {
      errorMessage = 'Oynatma hatası: ';
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> pauseOrResume() async {
    if (playerState == PlayerState.playing) {
      await _player.pause();
    } else {
      await _player.resume();
    }
  }

  Future<void> stop() async {
    await _player.stop();
    currentTitle = null;
    currentArtist = null;
    currentCover = null;
    position = Duration.zero;
    duration = Duration.zero;
    isLoading = false;
    errorMessage = null;
    isHidden = false;
    isMinimized = false;
    _syncMediaSession();
    notifyListeners();
  }

  Future<void> seek(Duration pos) async {
    await _player.seek(pos);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
