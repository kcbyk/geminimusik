import '../../global_audio_service.dart';
import '../../music_service.dart';
import '../agent_models.dart';

/// Müzik: arama, çalma, duraklatma, indirme, oynatıcı görünürlüğü.
class MusicTool extends AgentTool {
  MusicTool({MusicService? musicService})
      : _music = musicService ?? MusicService();

  final MusicService _music;

  @override
  String get name => 'music';

  @override
  String get description =>
      'Müzik motorunu yönetir: search (YouTube sonuçları), play, pause, resume, '
      'stop, seek, status, download (MP3 olarak cihaza kaydeder), show_player, hide_player.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'OBJECT',
        'properties': {
          'action': {
            'type': 'STRING',
            'enum': [
              'search',
              'play',
              'pause',
              'resume',
              'stop',
              'seek',
              'status',
              'download',
              'show_player',
              'hide_player',
            ],
          },
          'query': {
            'type': 'STRING',
            'description': 'search/play/download için şarkı adı + sanatçı.'
          },
          'seconds': {
            'type': 'INTEGER',
            'description': 'seek için saniye cinsinden konum.'
          },
        },
        'required': ['action'],
      };

  @override
  bool get speaksResult => true;

  @override
  Future<ToolResult> invoke(Map<String, dynamic> args) async {
    final action = args['action'] as String? ?? 'status';
    final query = (args['query'] as String?)?.trim() ?? '';
    final audio = GlobalAudioService.instance;

    switch (action) {
      case 'search':
        if (query.isEmpty) {
          return ToolResult.error('search için query gerekli.');
        }
        final songs = await _music.searchSongs(query);
        if (songs.isEmpty) return ToolResult('"$query" için sonuç bulunamadı.');
        final lines = songs.take(8).map((s) =>
            '- ${s.title}${s.artist == null ? '' : ' — ${s.artist}'} (${s.durationFormatted}, ${s.source})');
        return ToolResult(
            '${songs.length} sonuç (ilk 8):\n${lines.join('\n')}');
      case 'play':
        if (query.isEmpty) return ToolResult.error('play için query gerekli.');
        await audio.searchAndPlay(query);
        return ToolResult('"$query" çalınıyor.');
      case 'pause':
      case 'resume':
        await audio.pauseOrResume();
        return ToolResult(
            audio.isPlaying ? 'Çalmaya devam ediyor.' : 'Duraklatıldı.');
      case 'stop':
        await audio.stop();
        return const ToolResult('Oynatma durduruldu.');
      case 'seek':
        final seconds = (args['seconds'] as num?)?.toInt();
        if (seconds == null) {
          return ToolResult.error('seek için seconds gerekli.');
        }
        await audio.seek(Duration(seconds: seconds));
        return ToolResult('$seconds. saniyeye atlandı.');
      case 'download':
        if (query.isEmpty) {
          return ToolResult.error('download için query gerekli.');
        }
        return _download(query);
      case 'show_player':
        audio.showPlayer();
        return const ToolResult('Oynatıcı açıldı.');
      case 'hide_player':
        audio.hidePlayer();
        return const ToolResult('Oynatıcı gizlendi.');
      case 'status':
      default:
        if (!audio.hasTrack) return const ToolResult('Şu an çalan parça yok.');
        return ToolResult(
            'Çalan: ${audio.currentTitle}${audio.currentArtist == null ? '' : ' — ${audio.currentArtist}'} | '
            'durum: ${audio.isPlaying ? 'çalıyor' : 'duraklatıldı'} | '
            '${audio.position.inSeconds}/${audio.duration.inSeconds} sn');
    }
  }

  Future<ToolResult> _download(String query) async {
    final job = await _music.startInstantJob(query);
    final jobId = job['job_id']?.toString();
    if (jobId == null) {
      return ToolResult.error('İndirme görevi başlatılamadı: $job');
    }
    for (var attempt = 0; attempt < 40; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      final status = await _music.checkStatus(jobId);
      final state = status['durum']?.toString() ?? '';
      final fileUrl = status['dosya_url']?.toString();
      final fileName = status['dosya']?.toString() ?? '$query.mp3';
      if (state == 'bitti' || (fileUrl != null && fileUrl.isNotEmpty)) {
        final saved = await _music.downloadMp3File(
          remotePath: fileUrl ?? '/api/v1/file/$fileName',
          fallbackFileName: fileName,
          onProgress: (_, __) {},
        );
        return ToolResult('İndirildi: $saved');
      }
      if (state == 'hata') {
        return ToolResult.error('Dönüştürme hatası: $status');
      }
    }
    return ToolResult.error('İndirme 60 saniyede tamamlanmadı (job: $jobId).');
  }
}
