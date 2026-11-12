import 'package:flutter/material.dart';

import '../../../models/generative_ui/ui_action_model.dart';
import '../../../models/generative_ui/ui_component_model.dart';
import '../../chat/music_cards.dart';

/// `album`, `tracklist` ve `artist` bileşenleri.
///
/// Model bu üç türü ürettiğinde yanıt, ChatGPT'nin müzik ekranındaki gibi
/// kapak + künye + parça listesi hâlinde görünür. Tüm aksiyonlar sohbet
/// akışına "prompt" olarak döner (ör. "Sana Vuruldum şarkısını çal").
class UiAlbumWidget extends StatelessWidget {
  final UiComponent component;
  final void Function(UiAction action) onAction;

  const UiAlbumWidget({
    super.key,
    required this.component,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final data = component.data;
    return AlbumCard(
      title: component.title ?? data['name']?.toString() ?? 'Albüm',
      artist: (component.subtitle ?? data['artist']?.toString()),
      year: data['year']?.toString(),
      coverUrl: (data['cover'] ??
              data['cover_url'] ??
              data['image_url'] ??
              data['image'])
          ?.toString(),
      tracks: tracksFromComponent(component),
      onAction: (prompt) => onAction(
        UiAction(type: 'prompt', label: prompt, value: prompt),
      ),
    );
  }
}

class UiTracklistWidget extends StatelessWidget {
  final UiComponent component;
  final void Function(UiAction action) onAction;

  const UiTracklistWidget({
    super.key,
    required this.component,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return TrackListCard(
      title: component.title ?? component.data['playlist']?.toString(),
      tracks: tracksFromComponent(component),
      onAction: (prompt) => onAction(
        UiAction(type: 'prompt', label: prompt, value: prompt),
      ),
    );
  }
}

class UiArtistWidget extends StatelessWidget {
  final UiComponent component;
  final void Function(UiAction action) onAction;

  const UiArtistWidget({
    super.key,
    required this.component,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final data = component.data;
    final rawTags = data['tags'] ?? data['genres'];
    return ArtistCard(
      name: component.title ?? data['name']?.toString() ?? 'Sanatçı',
      subtitle: component.subtitle ?? component.description,
      imageUrl: (data['image_url'] ?? data['image'] ?? data['avatar'])
          ?.toString(),
      tags: rawTags is List
          ? rawTags.map((e) => e.toString()).toList()
          : const [],
      onAction: (prompt) => onAction(
        UiAction(type: 'prompt', label: prompt, value: prompt),
      ),
    );
  }
}
