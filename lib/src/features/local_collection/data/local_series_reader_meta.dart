import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Reader settings that one Local series overrides, stored as a JSON map
/// under `local.reader.manga.<seriesId>`.
class LocalSeriesReaderMeta {
  LocalSeriesReaderMeta(this._preferences, {this.onChanged});

  static const namespace = 'local.reader.manga.';

  final SharedPreferences _preferences;

  /// Called after each [patch] with the series id. The values live in
  /// SharedPreferences, not the catalog, so sync records the change here.
  final FutureOr<void> Function(String seriesId)? onChanged;

  /// The overrides of [seriesId]; empty when none are saved or they cannot be
  /// read.
  Map<String, dynamic> read(String seriesId) {
    final encoded = _preferences.getString('$namespace$seriesId');
    if (encoded == null) return {};
    try {
      final decoded = jsonDecode(encoded);
      return decoded is Map<String, dynamic> ? decoded : {};
    } on FormatException {
      return {};
    }
  }

  /// Sets [key] to the text of [value], or removes it when [value] is null.
  /// Returns the overrides as saved.
  Future<Map<String, dynamic>> patch(
    String seriesId,
    String key,
    Object? value,
  ) async {
    final values = read(seriesId);
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value.toString();
    }
    await _preferences.setString('$namespace$seriesId', jsonEncode(values));
    await onChanged?.call(seriesId);
    return values;
  }

  /// Replaces the overrides of [seriesId] with what sync pulled; nothing is
  /// recorded for sync, since these are the server's values.
  Future<void> replaceSynced(String seriesId, Map<String, String> values) =>
      values.isEmpty
      ? _preferences.remove('$namespace$seriesId')
      : _preferences.setString('$namespace$seriesId', jsonEncode(values));
}
