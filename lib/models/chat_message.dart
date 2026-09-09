import 'dart:typed_data';

class ChatMessage {
  final String id;
  final String content;
  final bool? _isUser;
  final DateTime timestamp;
  final String? usedModel; // e.g. "Gemini 2.5 Flash (Key 1)"
  final bool? _isMusicCommand;
  final bool? _isWebSearch;
  final String? searchQuery;
  final List<Map<String, String>>? sources; // [{'title': '...', 'url': '...'}]
  final Uint8List? imageBytes;
  final String? imageMimeType;

  bool get isUser => _isUser == true;
  bool get isMusicCommand => _isMusicCommand == true;
  bool get isWebSearch => _isWebSearch == true;

  ChatMessage({
    required this.id,
    required this.content,
    required bool isUser,
    required this.timestamp,
    this.usedModel,
    bool isMusicCommand = false,
    bool isWebSearch = false,
    this.searchQuery,
    this.sources,
    this.imageBytes,
    this.imageMimeType,
  })  : _isUser = isUser,
        _isMusicCommand = isMusicCommand,
        _isWebSearch = isWebSearch;

  Map<String, dynamic> toJson() => {
        'id': id,
        'content': content,
        'isUser': isUser,
        'timestamp': timestamp.toIso8601String(),
        'usedModel': usedModel,
        'isMusicCommand': isMusicCommand,
        'isWebSearch': isWebSearch,
        'searchQuery': searchQuery,
        'sources': sources,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
        content: json['content']?.toString() ?? '',
        isUser: json['isUser'] == true,
        timestamp: json['timestamp'] != null
            ? (DateTime.tryParse(json['timestamp'].toString()) ?? DateTime.now())
            : DateTime.now(),
        usedModel: json['usedModel']?.toString(),
        isMusicCommand: json['isMusicCommand'] == true,
        isWebSearch: json['isWebSearch'] == true,
        searchQuery: json['searchQuery']?.toString(),
        sources: (json['sources'] as List?)
            ?.map((e) => Map<String, String>.from(e as Map))
            .toList(),
      );

  ChatMessage copyWith({
    String? id,
    String? content,
    bool? isUser,
    DateTime? timestamp,
    String? usedModel,
    bool? isMusicCommand,
    bool? isWebSearch,
    String? searchQuery,
    List<Map<String, String>>? sources,
    Uint8List? imageBytes,
    String? imageMimeType,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      content: content ?? this.content,
      isUser: isUser ?? this.isUser,
      timestamp: timestamp ?? this.timestamp,
      usedModel: usedModel ?? this.usedModel,
      isMusicCommand: isMusicCommand ?? this.isMusicCommand,
      isWebSearch: isWebSearch ?? this.isWebSearch,
      searchQuery: searchQuery ?? this.searchQuery,
      sources: sources ?? this.sources,
      imageBytes: imageBytes ?? this.imageBytes,
      imageMimeType: imageMimeType ?? this.imageMimeType,
    );
  }
}
