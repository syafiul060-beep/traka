import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Model satu tujuan terakhir.
class RecentDestination {
  final String text;
  final double? lat;
  final double? lng;
  final DateTime usedAt;

  const RecentDestination({
    required this.text,
    this.lat,
    this.lng,
    required this.usedAt,
  });

  Map<String, dynamic> toJson() => {
        'text': text,
        'lat': lat,
        'lng': lng,
        'usedAt': usedAt.toIso8601String(),
      };

  factory RecentDestination.fromJson(Map<String, dynamic> j) =>
      RecentDestination(
        text: j['text'] as String? ?? '',
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
        usedAt: DateTime.tryParse(j['usedAt'] as String? ?? '') ?? DateTime.now(),
      );
}

/// Service untuk riwayat tujuan penumpang (disimpan lokal).
class RecentDestinationService {
  static const String _key = 'traka_recent_destinations';
  static const int _maxCount = 10;

  /// Simpan tujuan baru (paling atas).
  static Future<void> add(String text, {double? lat, double? lng}) async {
    if (text.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final list = await getList();
    final normalized = text.trim();
    list.removeWhere((r) =>
        r.text.toLowerCase() == normalized.toLowerCase());
    list.insert(0, RecentDestination(
      text: normalized,
      lat: lat,
      lng: lng,
      usedAt: DateTime.now(),
    ));
    while (list.length > _maxCount) list.removeLast();
    final encoded = list.map((r) => jsonEncode(r.toJson())).toList();
    await prefs.setStringList(_key, encoded);
  }

  /// Ambil daftar tujuan terakhir.
  static Future<List<RecentDestination>> getList() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    final list = <RecentDestination>[];
    for (final s in raw) {
      try {
        final j = jsonDecode(s) as Map<String, dynamic>;
        list.add(RecentDestination.fromJson(j));
      } catch (_) {}
    }
    return list;
  }

  /// Hapus satu item.
  static Future<void> remove(String text) async {
    final list = await getList();
    list.removeWhere((r) =>
        r.text.toLowerCase() == text.trim().toLowerCase());
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _key, list.map((r) => jsonEncode(r.toJson())).toList());
  }

  /// Hapus semua.
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
