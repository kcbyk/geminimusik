class SongItem {
  final String id;
  final String title;
  final String? artist;
  final int durationSeconds;
  final String? thumbnailUrl;
  final String source; // youtube, soundcloud, archive.org
  final String? directUrl;

  SongItem({
    required this.id,
    required this.title,
    this.artist,
    this.durationSeconds = 0,
    this.thumbnailUrl,
    required this.source,
    this.directUrl,
  });

  factory SongItem.fromJson(Map<String, dynamic> json) {
    return SongItem(
      id: json['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      title: json['baslik'] as String? ?? 'Bilinmeyen Şarkı',
      artist: json['kanal'] as String?,
      durationSeconds: json['sure'] as int? ?? 0,
      thumbnailUrl: json['kapak'] as String?,
      source: json['kaynak'] as String? ?? 'youtube',
      directUrl: json['url'] as String?,
    );
  }

  String get durationFormatted {
    if (durationSeconds <= 0) return "--:--";
    final min = (durationSeconds / 60).floor();
    final sec = durationSeconds % 60;
    return '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }
}

enum DownloadStatus { idle, queued, converting, downloading, completed, error }

class DownloadTask {
  String jobId;
  final String songTitle;
  final String? thumbnailUrl;
  int progressPercent;
  String statusMessage;
  DownloadStatus status;
  String? filePath;
  String? downloadUrl;
  String? errorMessage;

  DownloadTask({
    required this.jobId,
    required this.songTitle,
    this.thumbnailUrl,
    this.progressPercent = 0,
    this.statusMessage = 'Başlatılıyor...',
    this.status = DownloadStatus.queued,
    this.filePath,
    this.downloadUrl,
    this.errorMessage,
  });
}
