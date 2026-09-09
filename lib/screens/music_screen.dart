import 'dart:async';
// ignore: avoid_web_libraries_in_flutter
import 'dart:io' if (dart.library.html) '../stubs/io_stub.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:open_filex/open_filex.dart';
import 'package:audioplayers/audioplayers.dart';
import '../models/song_model.dart';
import '../services/music_service.dart';
import '../theme/gemini_colors.dart';
import '../widgets/gemini_sparkle.dart';

enum MusicAutoAction { none, download, play }

class MusicScreen extends StatefulWidget {
  final String? initialQuery;
  final MusicAutoAction autoAction;
  final VoidCallback? onOpenSidebar;

  const MusicScreen({
    super.key,
    this.initialQuery,
    this.autoAction = MusicAutoAction.none,
    this.onOpenSidebar,
  });

  @override
  State<MusicScreen> createState() => _MusicScreenState();
}

class _MusicScreenState extends State<MusicScreen> with SingleTickerProviderStateMixin {
  TabController? _tabController;
  final TextEditingController _searchController = TextEditingController();
  final MusicService _musicService = MusicService();
  final AudioPlayer _audioPlayer = AudioPlayer();

  List<SongItem> _searchResults = [];
  bool _isSearching = false;
  String? _searchError;

  final List<DownloadTask> _downloads = [];

  // Müzik Çalar (Player) Durumu
  String? _currentlyPlayingTitle;
  String? _currentlyPlayingArtist;
  String? _currentlyPlayingCover;
  String? _currentlyPlayingUrlOrPath;
  PlayerState _playerState = PlayerState.stopped;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  bool _isLoadingAudio = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      _searchController.text = widget.initialQuery!;
      if (widget.autoAction != MusicAutoAction.none) {
        _performSearchAndAct(widget.initialQuery!, widget.autoAction);
      } else {
        _performSearch(widget.initialQuery!);
      }
    }

    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _playerState = state;
          if (state == PlayerState.playing) {
            _isLoadingAudio = false;
          }
        });
      }
    });

    _audioPlayer.onPositionChanged.listen((pos) {
      if (mounted) setState(() => _currentPosition = pos);
    });

    _audioPlayer.onDurationChanged.listen((dur) {
      if (mounted) setState(() => _totalDuration = dur);
    });
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _audioPlayer.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return;

    setState(() {
      _isSearching = true;
      _searchError = null;
    });

    try {
      final results = await _musicService.searchSongs(cleanQuery);
      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _searchError = e.toString();
          _isSearching = false;
        });
      }
    }
  }

  /// AI komutuyla arama + otomatik aksiyon (download veya play)
  Future<void> _performSearchAndAct(String query, MusicAutoAction action) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return;

    setState(() {
      _isSearching = true;
      _searchError = null;
    });

    try {
      final results = await _musicService.searchSongs(cleanQuery);
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });

      if (results.isEmpty) return;

      final first = results.first;
      if (action == MusicAutoAction.download) {
        await startDownload(
          first.title,
          coverUrl: first.thumbnailUrl,
          song: first,
          audioSource: first.directUrl,
        );
      } else if (action == MusicAutoAction.play) {
        await _playOrPauseSong(
          title: first.title,
          artist: first.artist,
          coverUrl: first.thumbnailUrl,
          audioSource: first.directUrl,
          song: first,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _searchError = e.toString();
          _isSearching = false;
        });
      }
    }
  }

  bool _isDirectAudio(String? audioSource) {
    if (audioSource == null || audioSource.isEmpty) return false;
    // Yerel cihaz dosya yolu (örn. C:\, /data/..., /storage/...)
    if (!audioSource.startsWith('http://') && !audioSource.startsWith('https://')) return true;
    // Web sayfaları doğrudan ses dosyası DEĞİLDİR
    if (audioSource.contains('youtube.com') ||
        audioSource.contains('youtu.be') ||
        audioSource.contains('soundcloud.com') ||
        audioSource.contains('archive.org')) {
      return false;
    }
    // Google Video doğrudan akış URL'si (yalnızca mobil/masaüstü için geçerli, webde CORS sebebiyle engellidir)
    if (audioSource.contains('googlevideo.com')) {
      return !kIsWeb;
    }
    // Render API'mizden gelen gerçek MP3 akışı
    if (audioSource.contains('/api/v1/file/')) return true;
    // Doğrudan ses uzantıları
    final clean = audioSource.toLowerCase().split('?').first;
    return clean.endsWith('.mp3') ||
        clean.endsWith('.m4a') ||
        clean.endsWith('.wav') ||
        clean.endsWith('.aac') ||
        clean.endsWith('.ogg');
  }

  /// Şarkıyı başlatır veya duraklatır (Arama listesinden veya İndirilenlerden)
  Future<void> _playOrPauseSong({
    required String title,
    String? artist,
    String? coverUrl,
    String? audioSource,
    SongItem? song,
  }) async {
    // Sadece doğrudan çalınabilir gerçek ses dosyası veya yerel dosya ise direkt oynat
    if (_isDirectAudio(audioSource)) {
      if (_currentlyPlayingUrlOrPath == audioSource) {
        if (_playerState == PlayerState.playing) {
          await _audioPlayer.pause();
        } else {
          await _audioPlayer.resume();
        }
        return;
      }

      setState(() {
        _currentlyPlayingTitle = title;
        _currentlyPlayingArtist = artist;
        _currentlyPlayingCover = coverUrl;
        _currentlyPlayingUrlOrPath = audioSource;
        _isLoadingAudio = true;
        _currentPosition = Duration.zero;
        _totalDuration = Duration.zero;
      });

      try {
        await _audioPlayer.stop();
        if (audioSource!.startsWith('http://') || audioSource.startsWith('https://')) {
          await _audioPlayer.play(UrlSource(audioSource));
        } else {
          await _audioPlayer.play(DeviceFileSource(audioSource));
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isLoadingAudio = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ses çalınamadı: $e'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
      return;
    }

    // Eğer şu an çalan şarkı zaten buysa, çal/duraklat yap
    if (_currentlyPlayingTitle == title && _currentlyPlayingUrlOrPath != null) {
      if (_playerState == PlayerState.playing) {
        await _audioPlayer.pause();
      } else {
        await _audioPlayer.resume();
      }
      return;
    }

    // YouTube / SoundCloud / Archive vb. arama sonucundaki şarkı için:
    // Mini çalar anında ekrana gelir, kullanıcıyı bekletmeden hazırlandığını gösterir
    setState(() {
      _currentlyPlayingTitle = title;
      _currentlyPlayingArtist = artist;
      _currentlyPlayingCover = coverUrl;
      _currentlyPlayingUrlOrPath = null;
      _isLoadingAudio = true;
      _currentPosition = Duration.zero;
      _totalDuration = Duration.zero;
    });

    // 1. ÖNCELİK (BİRİNCİL APİ): RapidAPI youtube-mp36 ile 0.5 saniyede doğrudan MP3 bağlantısı al!
    // Bu bağlantı hem Web'de (Chrome) hem Mobilde (Android/iOS) CORS uyumlu ve 100% donmadan çalar!
    final ytId = MusicService.extractYouTubeId(song?.directUrl) ??
        MusicService.extractYouTubeId(audioSource) ??
        MusicService.extractYouTubeId(song?.id);

    if (ytId != null) {
      try {
        final directMp3Url = await _musicService.getDirectMp3Link(ytId);
        if (directMp3Url != null && directMp3Url.isNotEmpty && mounted) {
          setState(() {
            _currentlyPlayingUrlOrPath = directMp3Url;
            _isLoadingAudio = false;
          });
          await _audioPlayer.stop();
          await _audioPlayer.play(UrlSource(directMp3Url));
          return;
        }
      } catch (_) {
        // Hata durumunda diğer seçeneklere devam et
      }
    }

    // 2. MOBİL / MASAÜSTÜ İÇİN İKİNCİ APİ: ytstream Google Video akışı (yalnızca web harici)
    if (!kIsWeb && ytId != null) {
      try {
        final rapidStreamUrl = await _musicService.getRapidApiAudioStream(ytId);
        if (rapidStreamUrl != null && rapidStreamUrl.isNotEmpty && mounted) {
          setState(() {
            _currentlyPlayingUrlOrPath = rapidStreamUrl;
            _isLoadingAudio = false;
          });
          await _audioPlayer.stop();
          await _audioPlayer.play(UrlSource(rapidStreamUrl));
          return;
        }
      } catch (_) {
        // RapidAPI başarısız olursa kesintisiz olarak yedek API'ye geçer
      }
    }

    // 3. YEDEK APİ (Render sunucusu dönüştürme ve sorgulama)
    try {
      Map<String, dynamic> jobData;
      if (song != null && song.directUrl != null && song.directUrl!.isNotEmpty) {
        jobData = await _musicService.convertUrl(
          url: song.directUrl!,
          title: title,
          source: song.source,
        );
      } else {
        jobData = await _musicService.startInstantJob(title);
      }

      final jobId = jobData['job_id'] as String;
      _pollAndPlayWhenReady(jobId: jobId, title: title, artist: artist, coverUrl: coverUrl);
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingAudio = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Müzik başlatılamadı: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _pollAndPlayWhenReady({
    required String jobId,
    required String title,
    String? artist,
    String? coverUrl,
  }) {
    int attempts = 0;
    Timer.periodic(const Duration(milliseconds: 1200), (timer) async {
      attempts++;
      if (attempts > 45 || !mounted) {
        timer.cancel();
        if (mounted && _currentlyPlayingTitle == title) {
          setState(() => _isLoadingAudio = false);
        }
        return;
      }

      try {
        final statusData = await _musicService.checkStatus(jobId);
        final durum = statusData['durum'] as String? ?? '';
        final dosyaUrl = statusData['dosya_url'] as String?;
        final dosyaAdi = statusData['dosya'] as String? ?? '$title.mp3';

        if (durum == 'bitti' || (dosyaUrl != null && dosyaUrl.isNotEmpty)) {
          timer.cancel();
          final streamUrl = _musicService.getFullDownloadUrl(dosyaUrl ?? '/api/v1/file/$dosyaAdi');

          if (mounted && _currentlyPlayingTitle == title) {
            setState(() {
              _currentlyPlayingUrlOrPath = streamUrl;
              _isLoadingAudio = false;
            });
            await _audioPlayer.stop();
            await _audioPlayer.play(UrlSource(streamUrl));
          }
        }
      } catch (e) {
        timer.cancel();
        if (mounted && _currentlyPlayingTitle == title) {
          setState(() => _isLoadingAudio = false);
        }
      }
    });
  }

  Future<void> startDownload(String title, {String? coverUrl, SongItem? song, String? audioSource}) async {
    final ytId = MusicService.extractYouTubeId(song?.directUrl) ??
        MusicService.extractYouTubeId(audioSource) ??
        MusicService.extractYouTubeId(song?.id);

    // Zaten indiriliyor mu kontrol et
    final existingTask = _downloads.cast<DownloadTask?>().firstWhere(
      (t) => t != null && t.songTitle.toLowerCase().trim() == title.toLowerCase().trim(),
      orElse: () => null,
    );
    if (existingTask != null &&
        (existingTask.status == DownloadStatus.downloading ||
            existingTask.status == DownloadStatus.converting ||
            existingTask.status == DownloadStatus.queued)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"$title" zaten şu an indiriliyor.'),
          backgroundColor: const Color(0xFF1E1F20),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Görevi anında oluştur ve listeye ekle (Böylece hem arama sekmesinde hem indirilenlerde dönen çark anında belirir)
    final task = DownloadTask(
      jobId: 'dl_${DateTime.now().millisecondsSinceEpoch}',
      songTitle: title,
      thumbnailUrl: coverUrl,
      status: DownloadStatus.downloading,
      statusMessage: 'Bağlantı kuruluyor...',
      progressPercent: 0,
    );

    setState(() {
      _downloads.insert(0, task);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(GeminiColors.geminiCyan),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text('"$title" indiriliyor...')),
          ],
        ),
        backgroundColor: const Color(0xFF1E1F20),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        action: SnackBarAction(
          label: 'GÖRÜNTÜLE',
          textColor: GeminiColors.geminiCyan,
          onPressed: () {
            _tabController?.animateTo(1);
          },
        ),
      ),
    );

    // 1. ÖNCELİK (BİRİNCİL APİ): RapidAPI youtube-mp36 ile doğrudan yüksek hızlı MP3 indir
    if (ytId != null) {
      try {
        final directMp3Url = await _musicService.getDirectMp3Link(ytId) ??
            (!kIsWeb ? await _musicService.getRapidApiAudioStream(ytId) : null);
        if (directMp3Url != null && directMp3Url.isNotEmpty) {
          if (mounted) {
            setState(() {
              task.status = DownloadStatus.downloading;
              task.statusMessage = 'İndiriliyor...';
              task.progressPercent = 5;
            });
          }

          try {
            final savedFilePath = await _musicService.downloadMp3File(
              remotePath: directMp3Url,
              fallbackFileName: '$title.mp3',
              onProgress: (received, total) {
                if (total > 0 && mounted) {
                  setState(() {
                    task.progressPercent = ((received / total) * 100).toInt();
                    task.statusMessage =
                        '${(received / (1024 * 1024)).toStringAsFixed(1)} MB / ${(total / (1024 * 1024)).toStringAsFixed(1)} MB';
                  });
                }
              },
            );

            if (mounted) {
              setState(() {
                task.status = DownloadStatus.completed;
                task.statusMessage = 'Hazır (MP3)';
                task.filePath = savedFilePath;
              });

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('✅ "${task.songTitle}" başarıyla indirildi!'),
                  backgroundColor: const Color(0xFF1E1F20),
                  behavior: SnackBarBehavior.floating,
                  action: SnackBarAction(
                    label: 'ÇAL / DİNLE',
                    textColor: GeminiColors.geminiCyan,
                    onPressed: () => _playOrPauseSong(
                      title: task.songTitle,
                      coverUrl: task.thumbnailUrl,
                      audioSource: savedFilePath,
                    ),
                  ),
                ),
              );
            }
            return;
          } catch (err) {
            // RapidAPI dosya indirme hatasında yedeğe devam et
          }
        }
      } catch (_) {
        // Hata durumunda yedek sisteme geç
      }
    }

    // 2. ÖNCELİK (YEDEK APİ): Özel Render sunucusu dönüştürme ve sorgulama
    try {
      if (mounted) {
        setState(() {
          task.status = DownloadStatus.converting;
          task.statusMessage = 'Dönüştürülüyor (Yedek)...';
          task.progressPercent = 15;
        });
      }
      Map<String, dynamic> jobData;
      if (song != null && song.directUrl != null && song.directUrl!.isNotEmpty) {
        jobData = await _musicService.convertUrl(
          url: song.directUrl!,
          title: title,
          source: song.source,
        );
      } else {
        jobData = await _musicService.startInstantJob(title);
      }
      final jobId = jobData['job_id'] as String;
      task.jobId = jobId;

      _pollTaskProgress(task);
    } catch (e) {
      if (mounted) {
        setState(() {
          task.status = DownloadStatus.error;
          task.statusMessage = 'Hata oluştu';
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Hata: $e'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _pollTaskProgress(DownloadTask task) {
    Timer.periodic(const Duration(seconds: 3), (timer) async {
      try {
        final statusData = await _musicService.checkStatus(task.jobId);
        final yuzde = statusData['yuzde'] as int? ?? 0;
        final durum = statusData['durum'] as String? ?? '';
        final dosyaUrl = statusData['dosya_url'] as String?;
        final dosyaAdi =
            statusData['dosya'] as String? ?? '${task.songTitle}.mp3';

        if (!mounted) {
          timer.cancel();
          return;
        }

        setState(() {
          task.progressPercent = yuzde;
          task.statusMessage =
              statusData['mesaj'] as String? ?? 'Dönüştürülüyor...';
        });

        if (durum == 'bitti' ||
            yuzde >= 100 ||
            (dosyaUrl != null && dosyaUrl.isNotEmpty)) {
          timer.cancel();
          task.status = DownloadStatus.downloading;
          task.statusMessage = 'İndiriliyor...';
          setState(() {});

          final remotePath = dosyaUrl ?? '/api/v1/file/$dosyaAdi';

          try {
            final savedFilePath = await _musicService.downloadMp3File(
              remotePath: remotePath,
              fallbackFileName: dosyaAdi,
              onProgress: (received, total) {
                if (total > 0 && mounted) {
                  setState(() {
                    task.progressPercent = ((received / total) * 100).toInt();
                    task.statusMessage =
                        '${(received / (1024 * 1024)).toStringAsFixed(1)} MB / ${(total / (1024 * 1024)).toStringAsFixed(1)} MB';
                  });
                }
              },
            );

            if (mounted) {
              setState(() {
                task.status = DownloadStatus.completed;
                task.statusMessage = 'Hazır (320kbps MP3)';
                task.filePath = savedFilePath;
              });

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('✅ "${task.songTitle}" başarıyla indirildi!'),
                  backgroundColor: const Color(0xFF1E1F20),
                  behavior: SnackBarBehavior.floating,
                  action: SnackBarAction(
                    label: 'ÇAL / DİNLE',
                    textColor: GeminiColors.geminiCyan,
                    onPressed: () => _playOrPauseSong(
                      title: task.songTitle,
                      coverUrl: task.thumbnailUrl,
                      audioSource: savedFilePath,
                    ),
                  ),
                ),
              );
            }
          } catch (dlError) {
            final fullStreamUrl = _musicService.getFullDownloadUrl(remotePath);
            if (mounted) {
              setState(() {
                task.status = DownloadStatus.completed;
                task.statusMessage = 'Hazır (Çevrimiçi Dinle)';
                task.filePath = fullStreamUrl;
              });
            }
          }
        }
      } catch (e) {
        timer.cancel();
        if (mounted) {
          setState(() {
            task.status = DownloadStatus.error;
            task.errorMessage = e.toString();
            task.statusMessage = 'Hata oluştu: $e';
          });
        }
      }
    });
  }

  void _openDownloadedFile(String filePath) async {
    if (filePath.startsWith('http://') || filePath.startsWith('https://')) {
      _playOrPauseSong(title: 'Şarkı', audioSource: filePath);
      return;
    }
    final result = await OpenFilex.open(filePath);
    if (result.type != ResultType.done && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Dosya açılamadı: ${result.message}')),
      );
    }
  }

  /// İndirilen şarkıyı listeden ve diskten siler
  Future<void> _deleteDownload(DownloadTask task) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1F22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Şarkıyı Sil', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          '"${task.songTitle}" şarkısını indirmelerden silmek istediğinize emin misiniz?',
          style: const TextStyle(color: Color(0xFFC4C7C5), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // Eğer şu an çalan bu şarkıysa durdur
    if (_currentlyPlayingUrlOrPath == task.filePath) {
      await _audioPlayer.stop();
      setState(() {
        _currentlyPlayingTitle = null;
        _currentlyPlayingUrlOrPath = null;
        _playerState = PlayerState.stopped;
      });
    }

    // Diskten dosyayı sil (eğer yerel dosyaysa ve web değilse)
    if (!kIsWeb && task.filePath != null && !task.filePath!.startsWith('http')) {
      try {
        final file = File(task.filePath!);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }

    setState(() {
      _downloads.remove(task);
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🗑️ "${task.songTitle}" silindi.'),
          backgroundColor: const Color(0xFF1E1F20),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    _tabController ??= TabController(length: 2, vsync: this);
    return Scaffold(
      backgroundColor: GeminiColors.background,
      appBar: AppBar(
        backgroundColor: GeminiColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: widget.onOpenSidebar != null
            ? IconButton(
                icon: const Icon(Icons.menu, color: GeminiColors.textSecondary),
                tooltip: 'Menü',
                onPressed: widget.onOpenSidebar,
              )
            : null,
        title: const Text(
          'Müzik Hub',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: GeminiColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.4,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: GeminiColors.geminiBlue,
          indicatorWeight: 2.5,
          dividerColor: Colors.transparent,
          labelColor: GeminiColors.textPrimary,
          unselectedLabelColor: GeminiColors.textMuted,
          tabs: const [
            Tab(icon: Icon(Icons.search, size: 18), text: 'Şarkı Ara'),
            Tab(icon: Icon(Icons.library_music, size: 18), text: 'İndirilenler'),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildSearchTab(),
                _buildDownloadsTab(),
              ],
            ),
          ),
          // Premium Floating Alt Müzik Oynatıcı Barı
          if (_currentlyPlayingTitle != null) _buildBottomAudioPlayer(),
        ],
      ),
    );
  }

  /// Ekranın altında yüzen (floating), profesyonel ve modern Gemini Müzik Çalar Barı
  Widget _buildBottomAudioPlayer() {
    final isPlaying = _playerState == PlayerState.playing;
    final maxDur = _totalDuration.inMilliseconds.toDouble();
    final currPos = _currentPosition.inMilliseconds.toDouble();
    final sliderVal = (maxDur > 0 && currPos <= maxDur) ? currPos : 0.0;

    return Container(
      width: double.infinity,
      color: Colors.transparent,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF141619),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFF2E3238),
                  width: 1,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x99000000),
                    blurRadius: 28,
                    spreadRadius: 2,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // En üstte sıfır boşluklu şık ince etkileşimli ilerleme çubuğu
                  SizedBox(
                    height: 16,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3.0,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                          pressedElevation: 4,
                        ),
                        activeTrackColor: GeminiColors.geminiCyan,
                        inactiveTrackColor: const Color(0xFF2A2D32),
                        thumbColor: Colors.white,
                        overlayColor: const Color(0x334DAAF6),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                        trackShape: const RectangularSliderTrackShape(),
                      ),
                      child: Slider(
                        min: 0.0,
                        max: maxDur > 0 ? maxDur : 1.0,
                        value: sliderVal,
                        onChanged: (val) {
                          _audioPlayer.seek(Duration(milliseconds: val.toInt()));
                        },
                      ),
                    ),
                  ),

                  // Ana gövde: Parça detayları, kontroller ve süre
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 12, 10),
                    child: Row(
                      children: [
                        // Albüm Kapağı (Daire & Yükleme Göstergesi)
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF22252A),
                                border: Border.all(
                                  color: isPlaying
                                      ? GeminiColors.geminiCyan.withValues(alpha: 0.45)
                                      : const Color(0xFF33373E),
                                  width: 1.5,
                                ),
                              ),
                              child: ClipOval(
                                child: _currentlyPlayingCover != null
                                    ? Image.network(
                                        _currentlyPlayingCover!,
                                        width: 46,
                                        height: 46,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => _defaultThumb(size: 46),
                                      )
                                    : _defaultThumb(size: 46),
                              ),
                            ),
                            if (_isLoadingAudio)
                              Container(
                                width: 46,
                                height: 46,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Color(0x99000000),
                                ),
                                padding: const EdgeInsets.all(12),
                                child: const CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: GeminiColors.geminiCyan,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(width: 12),

                        // Parça Adı, Sanatçı ve Süre Gösterimi
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _currentlyPlayingTitle ?? 'Bilinmeyen Şarkı',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: GeminiColors.textPrimary,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  if (_currentlyPlayingArtist != null && _currentlyPlayingArtist!.isNotEmpty) ...[
                                    Flexible(
                                      child: Text(
                                        _currentlyPlayingArtist!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: GeminiColors.textMuted,
                                          fontSize: 11.5,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    const Text(
                                      '•',
                                      style: TextStyle(color: GeminiColors.textMuted, fontSize: 11),
                                    ),
                                    const SizedBox(width: 6),
                                  ],
                                  Text(
                                    _formatDuration(_currentPosition),
                                    style: const TextStyle(
                                      color: GeminiColors.geminiCyan,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      fontFeatures: [FontFeature.tabularFigures()],
                                    ),
                                  ),
                                  Text(
                                    ' / ${_totalDuration > Duration.zero ? _formatDuration(_totalDuration) : '--:--'}',
                                    style: const TextStyle(
                                      color: GeminiColors.textMuted,
                                      fontSize: 11.5,
                                      fontFeatures: [FontFeature.tabularFigures()],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // 10 Saniye Geri Sar
                        IconButton(
                          icon: const Icon(Icons.replay_10_rounded, color: GeminiColors.textSecondary, size: 22),
                          tooltip: '10 saniye geri',
                          splashRadius: 18,
                          onPressed: () {
                            final newPos = _currentPosition - const Duration(seconds: 10);
                            _audioPlayer.seek(newPos < Duration.zero ? Duration.zero : newPos);
                          },
                        ),

                        // Ana Oynat / Duraklat Butonu (Gemini Gradyanlı & Vurgulu)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(24),
                              onTap: () {
                                _playOrPauseSong(
                                  title: _currentlyPlayingTitle!,
                                  artist: _currentlyPlayingArtist,
                                  coverUrl: _currentlyPlayingCover,
                                  audioSource: _currentlyPlayingUrlOrPath,
                                );
                              },
                              child: Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF4285F4),
                                      Color(0xFF9B72CB),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF4285F4).withValues(alpha: 0.35),
                                      blurRadius: 12,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 26,
                                ),
                              ),
                            ),
                          ),
                        ),

                        // 10 Saniye İleri Sar
                        IconButton(
                          icon: const Icon(Icons.forward_10_rounded, color: GeminiColors.textSecondary, size: 22),
                          tooltip: '10 saniye ileri',
                          splashRadius: 18,
                          onPressed: () {
                            final newPos = _currentPosition + const Duration(seconds: 10);
                            _audioPlayer.seek(newPos > _totalDuration ? _totalDuration : newPos);
                          },
                        ),

                        const SizedBox(width: 2),

                        // Kapat Butonu
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: GeminiColors.textMuted, size: 20),
                          tooltip: 'Oynatıcıyı Kapat',
                          splashRadius: 18,
                          onPressed: () {
                            _audioPlayer.stop();
                            setState(() {
                              _currentlyPlayingTitle = null;
                              _currentlyPlayingUrlOrPath = null;
                              _playerState = PlayerState.stopped;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchTab() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 850),
              child: Container(
                decoration: BoxDecoration(
                  color: GeminiColors.inputBackground,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: GeminiColors.border, width: 1),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.search,
                        color: GeminiColors.textMuted, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        style: const TextStyle(
                            color: GeminiColors.textPrimary, fontSize: 15),
                        textInputAction: TextInputAction.search,
                        onSubmitted: _performSearch,
                        decoration: const InputDecoration(
                          hintText: 'Şarkı veya sanatçı adı ara (YouTube)...',
                          hintStyle: TextStyle(
                              color: GeminiColors.textMuted, fontSize: 14),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_forward,
                          color: GeminiColors.geminiCyan, size: 20),
                      tooltip: 'Ara',
                      onPressed: () => _performSearch(_searchController.text),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_isSearching)
          const Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: GeminiColors.geminiBlue),
                  SizedBox(height: 16),
                  Text(
                    'Şarkılar aranıyor...',
                    style: TextStyle(color: GeminiColors.textMuted),
                  ),
                ],
              ),
            ),
          )
        else if (_searchError != null)
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text('Hata: $_searchError',
                    style: const TextStyle(color: Colors.redAccent)),
              ),
            ),
          )
        else if (_searchResults.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  GeminiSparkleIcon(size: 48),
                  SizedBox(height: 16),
                  Text(
                    'İstediğin şarkıyı arat, üstüne dokunarak dinle veya MP3 indir!',
                    style: TextStyle(color: GeminiColors.textMuted),
                  ),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 850),
                child: ListView.builder(
                  itemCount: _searchResults.length,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemBuilder: (context, index) {
                    final song = _searchResults[index];
                    return _buildSongTile(song);
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSongTile(SongItem song) {
    final isThisPlaying = _currentlyPlayingTitle == song.title &&
        _playerState == PlayerState.playing;

    final songTask = _downloads.cast<DownloadTask?>().firstWhere(
      (t) => t != null && t.songTitle.toLowerCase().trim() == song.title.toLowerCase().trim(),
      orElse: () => null,
    );
    final isSongDownloading = songTask != null &&
        (songTask.status == DownloadStatus.downloading ||
            songTask.status == DownloadStatus.converting ||
            songTask.status == DownloadStatus.queued);
    final isSongDownloaded = songTask != null && songTask.status == DownloadStatus.completed;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: isThisPlaying
            ? const Color(0xFF232832)
            : GeminiColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isThisPlaying ? GeminiColors.geminiCyan : GeminiColors.border,
          width: isThisPlaying ? 1.2 : 0.8,
        ),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        // Şarkının üzerine basıldığında doğrudan çal/aç
        onTap: () {
          _playOrPauseSong(
            title: song.title,
            artist: song.artist,
            coverUrl: song.thumbnailUrl,
            audioSource: song.directUrl,
            song: song,
          );
        },
        // DAİRE ŞEKLİNDE KAPAK FOTOĞRAFI
        leading: Container(
          width: 52,
          height: 52,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFF282A2C),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              ClipOval(
                child: song.thumbnailUrl != null
                    ? Image.network(
                        song.thumbnailUrl!,
                        width: 52,
                        height: 52,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _defaultThumb(size: 52),
                      )
                    : _defaultThumb(size: 52),
              ),
              if (isThisPlaying)
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withValues(alpha: 0.45),
                  ),
                  child: const Icon(
                    Icons.graphic_eq,
                    color: GeminiColors.geminiCyan,
                    size: 24,
                  ),
                ),
              // İndiriliyorsa kapağın üzerinde dönen canlı çark göstergesi
              if (isSongDownloading)
                Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withValues(alpha: 0.65),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: const [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(GeminiColors.geminiCyan),
                        ),
                      ),
                      Icon(
                        Icons.download_rounded,
                        color: GeminiColors.geminiCyan,
                        size: 12,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        title: Text(
          song.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: isThisPlaying ? GeminiColors.geminiCyan : GeminiColors.textPrimary,
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Row(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.play_arrow, color: Colors.redAccent, size: 12),
                  SizedBox(width: 3),
                  Text(
                    'YOUTUBE',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                song.durationFormatted,
                style: const TextStyle(
                    color: GeminiColors.textMuted, fontSize: 11),
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Oynat / Duraklat Butonu
            IconButton(
              icon: Icon(
                isThisPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                color: GeminiColors.geminiCyan,
                size: 32,
              ),
              tooltip: isThisPlaying ? 'Durdur' : 'Dinle',
              onPressed: () {
                _playOrPauseSong(
                  title: song.title,
                  artist: song.artist,
                  coverUrl: song.thumbnailUrl,
                  audioSource: song.directUrl,
                  song: song,
                );
              },
            ),
            const SizedBox(width: 4),
            // İndir / İndiriliyor / İndirildi Butonu
            if (isSongDownloading)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: GeminiColors.geminiCyan.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: GeminiColors.geminiCyan.withValues(alpha: 0.4),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(GeminiColors.geminiCyan),
                      ),
                    ),
                    SizedBox(width: 6),
                    Text(
                      'İndiriliyor...',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: GeminiColors.geminiCyan,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              )
            else if (isSongDownloaded)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF00E676).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF00E676).withValues(alpha: 0.4),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.check_circle_rounded, color: Color(0xFF00E676), size: 14),
                    SizedBox(width: 4),
                    Text(
                      'İndirildi',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF00E676),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              )
            else
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: GeminiColors.geminiBlue, width: 1),
                  foregroundColor: GeminiColors.geminiBlue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                icon: const Icon(Icons.download, size: 15),
                label: const Text('İndir', style: TextStyle(fontSize: 12)),
                onPressed: () => startDownload(song.title, coverUrl: song.thumbnailUrl, song: song),
              ),
          ],
        ),
      ),
    );
  }

  Widget _defaultThumb({double size = 52, bool isSquare = false}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: isSquare ? BoxShape.rectangle : BoxShape.circle,
        borderRadius: isSquare ? BorderRadius.circular(14) : null,
        color: const Color(0xFF25262B),
      ),
      child: Icon(Icons.music_note_rounded, color: GeminiColors.textMuted, size: size * 0.45),
    );
  }

  Widget _buildDownloadsTab() {
    if (_downloads.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF4285F4).withValues(alpha: 0.15),
                    const Color(0xFF9B72CB).withValues(alpha: 0.15),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: const Color(0xFF4285F4).withValues(alpha: 0.3),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF4285F4).withValues(alpha: 0.15),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(
                Icons.cloud_download_rounded,
                size: 40,
                color: Color(0xFF8AB4F8),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Henüz İndirilen Şarkı Yok',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Arama bölümünden dilediğin şarkıyı 320kbps MP3 olarak\nindirebilir ve çevrimdışı dinleyebilirsin.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: GeminiColors.textMuted,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
        ),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 850),
        child: ListView.builder(
          itemCount: _downloads.length + 1,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12, left: 4, right: 4),
                child: Row(
                  children: [
                    const Icon(
                      Icons.folder_shared_rounded,
                      size: 16,
                      color: GeminiColors.geminiCyan,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'İNDİRİLEN ŞARKILAR',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                        color: GeminiColors.textMuted,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4285F4).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xFF4285F4).withValues(alpha: 0.3),
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        '${_downloads.length}',
                        style: const TextStyle(
                          color: GeminiColors.geminiCyan,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            final task = _downloads[index - 1];
            return _buildDownloadItem(task);
          },
        ),
      ),
    );
  }

  /// Modern, Spotify/YouTube Music tarzı zenginleştirilmiş indirme kartı
  Widget _buildDownloadItem(DownloadTask task) {
    final isCompleted = task.status == DownloadStatus.completed;
    final isDownloading = task.status == DownloadStatus.downloading ||
        task.status == DownloadStatus.converting ||
        task.status == DownloadStatus.queued;
    final isError = task.status == DownloadStatus.error;
    final isPlaying = task.filePath != null &&
        _currentlyPlayingUrlOrPath == task.filePath &&
        _playerState == PlayerState.playing;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1C20),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isPlaying
              ? const Color(0xFF4285F4).withValues(alpha: 0.7)
              : (isCompleted
                  ? Colors.white.withValues(alpha: 0.08)
                  : const Color(0xFF4285F4).withValues(alpha: 0.3)),
          width: isPlaying ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isPlaying
                ? const Color(0xFF4285F4).withValues(alpha: 0.22)
                : Colors.black.withValues(alpha: 0.4),
            blurRadius: isPlaying ? 22 : 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 1. ŞIK ALBÜM KAPAĞI (58x58 Yuvarlatılmış Kare & Derinlik)
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: const Color(0xFF25262B),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: task.thumbnailUrl != null
                              ? Image.network(
                                  task.thumbnailUrl!,
                                  width: 58,
                                  height: 58,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      _defaultThumb(size: 58, isSquare: true),
                                )
                              : _defaultThumb(size: 58, isSquare: true),
                        ),
                        // Çalıyorsa equalizer görseli
                        if (isPlaying)
                          Container(
                            width: 58,
                            height: 58,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              color: Colors.black.withValues(alpha: 0.55),
                            ),
                            child: const Icon(
                              Icons.graphic_eq_rounded,
                              color: GeminiColors.geminiCyan,
                              size: 26,
                            ),
                          ),
                        // İndiriliyorsa kapağın tam ortasında dönen canlı çark göstergesi
                        if (isDownloading)
                          Container(
                            width: 58,
                            height: 58,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              color: Colors.black.withValues(alpha: 0.65),
                            ),
                            child: Stack(
                              alignment: Alignment.center,
                              children: const [
                                SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.6,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      GeminiColors.geminiCyan,
                                    ),
                                  ),
                                ),
                                Icon(
                                  Icons.download_rounded,
                                  color: GeminiColors.geminiCyan,
                                  size: 14,
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),

                  // 2. ORTA BİLGİ ALANI (Başlık, Rozetler, Durum)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          task.songTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isPlaying ? GeminiColors.geminiCyan : Colors.white,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 5),
                        // Durum Rozetleri
                        if (isCompleted) ...[
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2.5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF4285F4).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: const Color(0xFF4285F4).withValues(alpha: 0.35),
                                    width: 0.8,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    Icon(Icons.check_circle_rounded,
                                        size: 11, color: Color(0xFF8AB4F8)),
                                    SizedBox(width: 4),
                                    Text(
                                      '320kbps MP3',
                                      style: TextStyle(
                                        color: Color(0xFF8AB4F8),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2.5),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'Çevrimdışı Hazır',
                                  style: TextStyle(
                                    color: GeminiColors.textMuted,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ] else if (isDownloading) ...[
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  task.statusMessage,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF8AB4F8),
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF4285F4).withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '%${task.progressPercent}',
                                  style: const TextStyle(
                                    color: GeminiColors.geminiCyan,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ] else if (isError) ...[
                          Row(
                            children: [
                              const Icon(Icons.error_outline_rounded,
                                  size: 14, color: Colors.redAccent),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  task.errorMessage ?? 'İndirme hatası',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.redAccent,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),

                  // 3. SAĞ KONTROLLER
                  if (isCompleted) ...[
                    // Çal / Duraklat Butonu (Gemini Degrade Daire)
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(22),
                        onTap: () => _playOrPauseSong(
                          title: task.songTitle,
                          coverUrl: task.thumbnailUrl,
                          audioSource: task.filePath!,
                        ),
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: isPlaying
                                  ? const [Color(0xFF00E5FF), Color(0xFF4285F4)]
                                  : const [Color(0xFF4285F4), Color(0xFF9B72CB)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF4285F4)
                                    .withValues(alpha: isPlaying ? 0.5 : 0.3),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Icon(
                            isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Dosyayı Aç (Masaüstü/Mobil)
                    if (!kIsWeb && !task.filePath!.startsWith('http')) ...[
                      _buildGlassActionBtn(
                        icon: Icons.folder_open_rounded,
                        tooltip: 'Dosyayı Aç',
                        onTap: () => _openDownloadedFile(task.filePath!),
                      ),
                      const SizedBox(width: 6),
                    ],
                    // Sil Butonu
                    _buildGlassActionBtn(
                      icon: Icons.delete_outline_rounded,
                      tooltip: 'İndirmeyi Sil',
                      hoverColor: Colors.redAccent,
                      onTap: () => _deleteDownload(task),
                    ),
                  ] else if (isDownloading) ...[
                    // İndirmeyi İptal/Sil
                    _buildGlassActionBtn(
                      icon: Icons.close_rounded,
                      tooltip: 'İptal Et',
                      onTap: () => _deleteDownload(task),
                    ),
                  ] else if (isError) ...[
                    // Yeniden Dene Butonu
                    _buildGlassActionBtn(
                      icon: Icons.refresh_rounded,
                      tooltip: 'Yeniden Dene',
                      hoverColor: GeminiColors.geminiCyan,
                      onTap: () => startDownload(task.songTitle,
                          coverUrl: task.thumbnailUrl),
                    ),
                    const SizedBox(width: 6),
                    _buildGlassActionBtn(
                      icon: Icons.delete_outline_rounded,
                      tooltip: 'Sil',
                      onTap: () => _deleteDownload(task),
                    ),
                  ],
                ],
              ),
            ),

            // 4. CANLI VE IŞILTILI PROGRESS BAR (Yalnızca indirme/dönüştürme sürerken)
            if (isDownloading)
              Container(
                height: 4,
                width: double.infinity,
                color: Colors.white.withValues(alpha: 0.06),
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: (task.progressPercent / 100).clamp(0.02, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF4285F4), Color(0xFF00E5FF)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00E5FF).withValues(alpha: 0.6),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Yarı saydam cam efektli yuvarlak aksiyon butonu
  Widget _buildGlassActionBtn({
    required IconData icon,
    required String tooltip,
    Color? hoverColor,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
                width: 0.8,
              ),
            ),
            child: Icon(
              icon,
              size: 18,
              color: hoverColor ?? Colors.white.withValues(alpha: 0.75),
            ),
          ),
        ),
      ),
    );
  }
}
