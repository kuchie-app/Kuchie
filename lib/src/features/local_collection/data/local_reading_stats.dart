import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Time spent reading one series. Server titles carry their cover path.
typedef LocalReadingTime = ({
  String seriesId,
  String title,
  Duration time,
  String? cover,
});

/// The key for a Server collection title, beside Local series ids.
String serverReadingKey(int mangaId) => 'server:$mangaId';

/// Reading time per series, for Reading Insights and History.
class LocalReadingStats extends ChangeNotifier {
  LocalReadingStats._();

  static final instance = LocalReadingStats._();

  static const _key = 'local.reading.seconds';
  static const _sinceKey = 'local.reading.since';

  final _seconds = <String, int>{};
  final _titles = <String, String>{};
  final _covers = <String, String>{};
  DateTime? _since;
  Future<void>? _loading;

  /// When Kuchie started counting.
  DateTime? get since => _since;

  Future<void> load() => _loading ??= () async {
    final prefs = await SharedPreferences.getInstance();
    final since = prefs.getInt(_sinceKey);
    _since = since == null ? null : DateTime.fromMillisecondsSinceEpoch(since);
    try {
      final saved = jsonDecode(prefs.getString(_key) ?? '{}');
      if (saved is Map<String, Object?>) {
        for (final MapEntry(:key, :value) in saved.entries) {
          if (value case {'s': final int seconds, 't': final String title}) {
            _seconds[key] = seconds;
            _titles[key] = title;
            if (value['c'] case final String cover) _covers[key] = cover;
          }
        }
      }
    } on FormatException {
      // A damaged record starts the count again.
    }
  }();

  /// Adds [time] read in [seriesId]; reads under two seconds are taps.
  Future<void> add(
    String seriesId,
    String title,
    Duration time, {
    String? cover,
  }) async {
    if (time.inSeconds < 2) return;
    await load();
    _seconds[seriesId] = (_seconds[seriesId] ?? 0) + time.inSeconds;
    _titles[seriesId] = title;
    if (cover != null && cover.isNotEmpty) _covers[seriesId] = cover;
    final prefs = await SharedPreferences.getInstance();
    if (_since == null) {
      _since = DateTime.now();
      await prefs.setInt(_sinceKey, _since!.millisecondsSinceEpoch);
    }
    await prefs.setString(
      _key,
      jsonEncode({
        for (final MapEntry(:key, :value) in _seconds.entries)
          key: {'s': value, 't': _titles[key] ?? '', 'c': ?_covers[key]},
      }),
    );
    notifyListeners();
  }

  Duration timeFor(String seriesId) =>
      Duration(seconds: _seconds[seriesId] ?? 0);

  Duration get total =>
      Duration(seconds: _seconds.values.fold(0, (sum, value) => sum + value));

  /// Series by reading time, longest first.
  List<LocalReadingTime> get ranked => [
    for (final MapEntry(:key, :value) in _seconds.entries)
      (
        seriesId: key,
        title: _titles[key] ?? '',
        time: Duration(seconds: value),
        cover: _covers[key],
      ),
  ]..sort((a, b) => b.time.compareTo(a.time));
}

/// "4 h 24 m", "13 m" or "< 1 m".
String formatReadingTime(Duration time) {
  final hours = time.inHours;
  final minutes = time.inMinutes % 60;
  if (hours > 0) return '$hours h $minutes m';
  if (minutes > 0) return '$minutes m';
  return '< 1 m';
}
