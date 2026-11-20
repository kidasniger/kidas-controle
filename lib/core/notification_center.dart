import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'store.dart';

/// Historique local des alertes affichées par l'application.
/// Les entrées restent sur l'appareil et ne contiennent aucun secret.
class NotificationEntry {
  final String id;
  final String title;
  final String body;
  final String category;
  final DateTime createdAt;
  final bool read;

  const NotificationEntry({
    required this.id,
    required this.title,
    required this.body,
    required this.category,
    required this.createdAt,
    this.read = false,
  });

  factory NotificationEntry.fromMap(Map<String, dynamic> map) {
    return NotificationEntry(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      body: map['body']?.toString() ?? '',
      category: map['category']?.toString() ?? 'general',
      createdAt: DateTime.tryParse(map['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      read: map['read'] == true,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'body': body,
        'category': category,
        'createdAt': createdAt.toIso8601String(),
        'read': read,
      };

  NotificationEntry copyWith({bool? read}) => NotificationEntry(
        id: id,
        title: title,
        body: body,
        category: category,
        createdAt: createdAt,
        read: read ?? this.read,
      );
}

class NotificationCenter {
  static const _key = 'notification_center_v1';
  static final ValueNotifier<List<NotificationEntry>> entries =
      ValueNotifier(const []);
  static bool _loaded = false;
  static Future<void>? _loading;

  static int get unreadCount => entries.value.where((e) => !e.read).length;

  static Future<void> load() {
    if (_loaded) return Future.value();
    return _loading ??= _load();
  }

  static Future<void> _load() async {
    try {
      final raw = await Store.get(_key);
      final decoded = raw.isEmpty ? const [] : jsonDecode(raw);
      if (decoded is List) {
        entries.value = decoded
            .whereType<Map>()
            .map((item) => NotificationEntry.fromMap(
                  Map<String, dynamic>.from(item),
                ))
            .where((item) => item.id.isNotEmpty)
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      }
    } catch (_) {
      entries.value = const [];
    } finally {
      _loaded = true;
      _loading = null;
    }
  }

  static Future<void> add({
    required String title,
    required String body,
    String category = 'general',
  }) async {
    await load();
    final now = DateTime.now();
    final item = NotificationEntry(
      id: '${now.microsecondsSinceEpoch}',
      title: title,
      body: body,
      category: category,
      createdAt: now,
    );
    final next = [item, ...entries.value].take(150).toList();
    entries.value = next;
    await _save();
  }

  static Future<void> markRead(String id) async {
    await load();
    entries.value = [
      for (final item in entries.value)
        if (item.id == id) item.copyWith(read: true) else item,
    ];
    await _save();
  }

  static Future<void> markAllRead() async {
    await load();
    entries.value = [for (final item in entries.value) item.copyWith(read: true)];
    await _save();
  }

  static Future<void> remove(String id) async {
    await load();
    entries.value = entries.value.where((item) => item.id != id).toList();
    await _save();
  }

  static Future<void> clear() async {
    entries.value = const [];
    _loaded = true;
    await _save();
  }

  static Future<void> _save() async {
    await Store.set(
      _key,
      jsonEncode(entries.value.map((item) => item.toMap()).toList()),
    );
  }
}
