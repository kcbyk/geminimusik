import 'package:dio/dio.dart';

class ImageSearchItem {
  final String title, thumbnailUrl, imageUrl, sourceUrl, sourceName;
  final String? photographer;
  final int? width, height;
  const ImageSearchItem(
      {required this.title,
      required this.thumbnailUrl,
      required this.imageUrl,
      required this.sourceUrl,
      required this.sourceName,
      this.photographer,
      this.width,
      this.height});
  Map<String, dynamic> toGalleryJson() => {
        'title': title,
        'thumbnail_url': thumbnailUrl,
        'image_url': imageUrl,
        'source_url': sourceUrl,
        'source_name': sourceName,
        'photographer': photographer,
        'width': width,
        'height': height
      };
}

/// API anahtarları yalnızca sunucudaki /api/image-search endpoint'inde tutulur.
class ImageSearchService {
  ImageSearchService({Dio? dio}) : _dio = dio ?? Dio();
  static const _endpoint = String.fromEnvironment('IMAGE_SEARCH_ENDPOINT');
  final Dio _dio;

  Future<List<ImageSearchItem>> search(String query,
      {int page = 1, int count = 10}) async {
    if (_endpoint.isEmpty || query.trim().isEmpty) return const [];
    final response = await _dio.get(_endpoint, queryParameters: {
      'q': query,
      'page': page,
      'count': count.clamp(1, 12)
    });
    final data = response.data;
    final results = data is Map ? data['images'] : null;
    if (results is! List) return const [];
    return results
        .whereType<Map>()
        .map((raw) {
          String https(dynamic value) {
            final valueString = value?.toString() ?? '';
            return Uri.tryParse(valueString)?.scheme == 'https'
                ? valueString
                : '';
          }

          return ImageSearchItem(
            title: raw['title']?.toString() ?? '',
            thumbnailUrl: https(raw['thumbnail_url']),
            imageUrl: https(raw['image_url']),
            sourceUrl: https(raw['source_url']),
            sourceName: raw['source_name']?.toString() ?? 'Kaynak',
            photographer: raw['photographer']?.toString(),
            width: (raw['width'] as num?)?.toInt(),
            height: (raw['height'] as num?)?.toInt(),
          );
        })
        .where((item) =>
            item.thumbnailUrl.isNotEmpty &&
            item.imageUrl.isNotEmpty &&
            item.sourceUrl.isNotEmpty)
        .toList();
  }
}
