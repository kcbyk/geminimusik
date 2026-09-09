import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_message.dart';

class ChatSession {
  final String id;
  String title;
  final DateTime createdAt;
  List<ChatMessage> messages;

  ChatSession({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.messages,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'messages': messages.map((m) => m.toJson()).toList(),
      };

  factory ChatSession.fromJson(Map<String, dynamic> json) => ChatSession(
        id: json['id'] as String,
        title: json['title'] as String? ?? 'Yeni Sohbet',
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
            : DateTime.now(),
        messages: (json['messages'] as List? ?? [])
            .map((m) => ChatMessage.fromJson(m as Map<String, dynamic>))
            .toList(),
      );
}

class ChatHistoryService {
  static final ChatHistoryService instance = ChatHistoryService._internal();
  ChatHistoryService._internal();

  static const String _storageKey = 'gemini_saved_chat_sessions_v1';

  final ValueNotifier<List<ChatSession>> sessionsNotifier = ValueNotifier<List<ChatSession>>([]);
  final ValueNotifier<String?> activeSessionIdNotifier = ValueNotifier<String?>(null);

  bool _isLoaded = false;

  Future<void> init() async {
    if (_isLoaded) return;
    await loadSessions();
    _isLoaded = true;
  }

  Future<List<ChatSession>> loadSessions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_storageKey);
      if (jsonString != null && jsonString.isNotEmpty) {
        final List list = jsonDecode(jsonString) as List;
        final sessions = list
            .map((item) => ChatSession.fromJson(item as Map<String, dynamic>))
            .toList();
        sessions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        sessionsNotifier.value = sessions;
        return sessions;
      }
    } catch (_) {}
    sessionsNotifier.value = [];
    return [];
  }

  Future<void> saveSession(ChatSession session) async {
    final list = List<ChatSession>.from(sessionsNotifier.value);
    final index = list.indexWhere((s) => s.id == session.id);
    if (index != -1) {
      list[index] = session;
    } else {
      list.insert(0, session);
    }
    sessionsNotifier.value = list;
    await _persist(list);
  }

  Future<void> deleteSession(String sessionId) async {
    final list = List<ChatSession>.from(sessionsNotifier.value);
    list.removeWhere((s) => s.id == sessionId);
    sessionsNotifier.value = list;
    if (activeSessionIdNotifier.value == sessionId) {
      activeSessionIdNotifier.value = null;
    }
    await _persist(list);
  }

  Future<void> _persist(List<ChatSession> sessions) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = jsonEncode(sessions.map((s) => s.toJson()).toList());
      await prefs.setString(_storageKey, jsonString);
    } catch (_) {}
  }

  ChatSession? getSession(String sessionId) {
    try {
      return sessionsNotifier.value.firstWhere((s) => s.id == sessionId);
    } catch (_) {
      return null;
    }
  }
}
