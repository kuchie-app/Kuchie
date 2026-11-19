import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Browse settings for the Local collection.
class LocalBrowsePreferences {
  LocalBrowsePreferences._();

  static final instance = LocalBrowsePreferences._();

  static const _showNsfwKey = 'local.browse.showNsfw';

  /// Whether 18+ extensions and their sources are listed.
  final showNsfw = ValueNotifier<bool>(true);

  Future<void>? _loading;

  Future<void> load() => _loading ??= () async {
    final prefs = await SharedPreferences.getInstance();
    showNsfw.value = prefs.getBool(_showNsfwKey) ?? true;
  }();

  Future<void> setShowNsfw(bool value) async {
    await load();
    showNsfw.value = value;
    await (await SharedPreferences.getInstance()).setBool(_showNsfwKey, value);
  }
}
