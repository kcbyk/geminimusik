import 'package:flutter/material.dart';

import '../../models/generative_ui/ui_component_model.dart';
import '../../theme/chat_ui.dart';

/// Yuvarlatılmış albüm kapağı: ağ hatasında nota ikonlu sade bir zemin.
class AlbumCover extends StatelessWidget {
  final String? url;
  final double size;
  final double radius;

  const AlbumCover({
    super.key,
    this.url,
    this.size = 88,
    this.radius = 12,
  });

  @override
  Widget build(BuildContext context) {
    final clean = (url ?? '').trim();
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: clean.isEmpty
            ? _fallback()
            : Image.network(
                clean,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _fallback(),
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : _fallback(loading: true),
              ),
      ),
    );
  }

  Widget _fallback({bool loading = false}) {
    return Container(
      color: ChatUi.surfaceRaised,
      alignment: Alignment.center,
      child: loading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 1.6,
                color: ChatUi.textMuted,
              ),
            )
          : const Icon(Icons.music_note_rounded,
              color: ChatUi.textMuted, size: 26),
    );
  }
}

/// Albüm kartı: kapak + künye + oynat + açılır parça listesi.
class AlbumCard extends StatefulWidget {
  final String title;
  final String? artist;
  final String? year;
  final String? coverUrl;
  final List<AlbumTrack> tracks;
  final void Function(String prompt)? onAction;

  const AlbumCard({
    super.key,
    required this.title,
    this.artist,
    this.year,
    this.coverUrl,
    this.tracks = const [],
    this.onAction,
  });

  @override
  State<AlbumCard> createState() => _AlbumCardState();
}

class _AlbumCardState extends State<AlbumCard> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final meta = [
      if (widget.artist != null && widget.artist!.trim().isNotEmpty)
        widget.artist!.trim(),
      if (widget.year != null && widget.year!.trim().isNotEmpty)
        widget.year!.trim(),
      if (widget.tracks.isNotEmpty) '${widget.tracks.length} parça',
    ].join(' · ');

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: ChatUi.cardDecoration(radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              AlbumCover(url: widget.coverUrl, size: 82),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: ChatUi.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ChatUi.caption,
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _PillButton(
                          icon: Icons.play_arrow_rounded,
                          label: 'Çal',
                          primary: true,
                          onTap: () => widget.onAction?.call(
                            '${widget.title} albümünü çal',
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (widget.tracks.isNotEmpty)
                          _PillButton(
                            icon: _expanded
                                ? Icons.expand_less_rounded
                                : Icons.expand_more_rounded,
                            label: _expanded ? 'Gizle' : 'Parçalar',
                            onTap: () =>
                                setState(() => _expanded = !_expanded),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_expanded && widget.tracks.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(color: ChatUi.borderSoft, height: 1),
            const SizedBox(height: 6),
            for (var i = 0; i < widget.tracks.length; i++)
              TrackRow(
                index: i + 1,
                track: widget.tracks[i],
                fallbackArtworkUrl: widget.coverUrl,
                onTap: () => widget.onAction?.call(
                  '${widget.tracks[i].title} - '
                  '${widget.tracks[i].artist ?? widget.artist ?? ''} şarkısını çal',
                ),
                onDownload: () => widget.onAction?.call(
                  '${widget.tracks[i].title} - '
                  '${widget.tracks[i].artist ?? widget.artist ?? ''} şarkısını indir',
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class AlbumTrack {
  final String title;
  final String? artist;
  final String? duration;

  /// Parçanın kendi kapak görseli. Albüm kartlarında boş bırakılırsa
  /// albüm kapağı kullanılır.
  final String? artworkUrl;

  const AlbumTrack({
    required this.title,
    this.artist,
    this.duration,
    this.artworkUrl,
  });

  /// Var olan kapağı korur, yalnızca boşsa [artwork] ile doldurur.
  AlbumTrack withArtwork(String? artwork) => AlbumTrack(
        title: title,
        artist: artist,
        duration: duration,
        artworkUrl: (artworkUrl ?? '').trim().isNotEmpty ? artworkUrl : artwork,
      );
}

/// Tek bir parça satırı. Numaraya dokununca çalar, indirme ikonu ayrı çalışır.
class TrackRow extends StatelessWidget {
  final int index;
  final AlbumTrack track;
  final VoidCallback? onTap;
  final VoidCallback? onDownload;

  /// Albüm kapağı; parçanın kendi kapağı yoksa bu gösterilir.
  final String? fallbackArtworkUrl;

  const TrackRow({
    super.key,
    required this.index,
    required this.track,
    this.onTap,
    this.onDownload,
    this.fallbackArtworkUrl,
  });

  /// Parçanın kapağı (yoksa albüm kapağı). İkisi de yoksa hiç yer kaplamaz.
  Widget _trackArtwork() {
    final url = (track.artworkUrl ?? fallbackArtworkUrl ?? '').trim();
    if (url.isEmpty) return const SizedBox.shrink();
    return AlbumCover(url: url, size: 38, radius: 8);
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: Text(
                index.toString().padLeft(2, '0'),
                style: const TextStyle(
                  color: ChatUi.textMuted,
                  fontSize: 12,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 4),
            _trackArtwork(),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: ChatUi.textPrimary,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (track.artist != null && track.artist!.trim().isNotEmpty)
                    Text(
                      track.artist!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ChatUi.caption,
                    ),
                ],
              ),
            ),
            if (track.duration != null && track.duration!.trim().isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(
                track.duration!,
                style: const TextStyle(
                  color: ChatUi.textMuted,
                  fontSize: 12,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
            if (onDownload != null)
              IconButton(
                onPressed: onDownload,
                visualDensity: VisualDensity.compact,
                tooltip: 'İndir',
                icon: const Icon(Icons.download_rounded,
                    size: 17, color: ChatUi.textMuted),
              )
            else
              const Icon(Icons.play_arrow_rounded,
                  size: 17, color: ChatUi.textMuted),
          ],
        ),
      ),
    );
  }
}

/// Sanatçı kartı: yuvarlak avatar, isim, kısa künye, takip et aksiyonu.
class ArtistCard extends StatelessWidget {
  final String name;
  final String? subtitle;
  final String? imageUrl;
  final List<String> tags;
  final void Function(String prompt)? onAction;

  const ArtistCard({
    super.key,
    required this.name,
    this.subtitle,
    this.imageUrl,
    this.tags = const [],
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: ChatUi.cardDecoration(radius: 18),
      child: Row(
        children: [
          ClipOval(
            child: SizedBox(
              width: 64,
              height: 64,
              child: (imageUrl ?? '').trim().isEmpty
                  ? Container(
                      color: ChatUi.surfaceRaised,
                      alignment: Alignment.center,
                      child: const Icon(Icons.person_rounded,
                          color: ChatUi.textMuted, size: 28),
                    )
                  : Image.network(
                      imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: ChatUi.surfaceRaised,
                        alignment: Alignment.center,
                        child: const Icon(Icons.person_rounded,
                            color: ChatUi.textMuted, size: 28),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: ChatUi.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: ChatUi.caption,
                  ),
                ],
                if (tags.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final tag in tags.take(4))
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: ChatUi.surfaceRaised,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: ChatUi.borderSoft),
                          ),
                          child: Text(
                            tag,
                            style: const TextStyle(
                              color: ChatUi.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (onAction != null)
            IconButton(
              tooltip: 'Şarkılarını göster',
              onPressed: () => onAction!('$name şarkılarını listele'),
              icon: const Icon(Icons.play_circle_fill_rounded,
                  color: ChatUi.accent, size: 30),
            ),
        ],
      ),
    );
  }
}

/// Bağımsız parça listesi (albüm kapağı olmadan).
class TrackListCard extends StatelessWidget {
  final String? title;
  final List<AlbumTrack> tracks;
  final void Function(String prompt)? onAction;

  /// Liste başlığında gösterilen albüm kapağı (varsa) ve parça satırları için
  /// yedek görsel.
  final String? coverUrl;

  const TrackListCard({
    super.key,
    this.title,
    required this.tracks,
    this.onAction,
    this.coverUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: ChatUi.cardDecoration(radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null && title!.trim().isNotEmpty) ...[
            Row(
              children: [
                if ((coverUrl ?? '').trim().isNotEmpty) ...[
                  AlbumCover(url: coverUrl, size: 40, radius: 8),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    title!,
                    style: const TextStyle(
                      color: ChatUi.textPrimary,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          for (var i = 0; i < tracks.length; i++)
            TrackRow(
              index: i + 1,
              track: tracks[i],
              fallbackArtworkUrl: coverUrl,
              onTap: () => onAction?.call('${tracks[i].title} şarkısını çal'),
              onDownload: () => onAction?.call('${tracks[i].title} şarkısını indir'),
            ),
        ],
      ),
    );
  }
}

/// Kart içi küçük hap buton.
class _PillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  const _PillButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: primary ? ChatUi.accent : ChatUi.surfaceRaised,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: primary ? Colors.black : ChatUi.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: primary ? Colors.black : ChatUi.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// UiComponent → AlbumTrack dönüşümü (generative UI entegrasyonu için).
List<AlbumTrack> tracksFromComponent(UiComponent component) {
  final raw = component.data['tracks'] ?? component.data['songs'];
  if (raw is! List) return const [];
  return raw
      .map((item) {
        if (item is String) return AlbumTrack(title: item);
        if (item is Map) {
          final artwork = item['artwork'] ??
              item['artwork_url'] ??
              item['cover'] ??
              item['image'];
          return AlbumTrack(
            title: (item['title'] ?? item['name'] ?? '').toString(),
            artist: (item['artist'] ?? item['subtitle'])?.toString(),
            duration: (item['duration'] ?? item['length'])?.toString(),
            artworkUrl: artwork is Map
                ? (artwork['url'] ?? artwork['src'])?.toString()
                : artwork?.toString(),
          );
        }
        return null;
      })
      .whereType<AlbumTrack>()
      .where((t) => t.title.trim().isNotEmpty)
      .toList();
}
