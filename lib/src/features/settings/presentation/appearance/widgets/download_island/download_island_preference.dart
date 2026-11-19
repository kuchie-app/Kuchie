import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum DownloadIslandVariant {
  kiriRing('kiri-face-ring', 'wajah-kiri-ring'),
  kiriPercentage('kiri-face-percentage', 'wajah-kiri-persen'),
  scarf('bookmark-scarf', 'syal-penanda'),
  mangaPanel('manga-panel', 'panel-manga');

  const DownloadIslandVariant(this.id, this._legacyId);

  final String id;

  /// The ID Kuchie 1.0.0 saved, before the assets had English names.
  final String _legacyId;

  static DownloadIslandVariant fromId(String? id) => values.firstWhere(
    (variant) => variant.id == id || variant._legacyId == id,
    orElse: () => kiriRing,
  );
}

final class DownloadIslandPreference {
  const DownloadIslandPreference._();

  static const _channel = MethodChannel('kuchie/download_live_activity');

  static bool get isIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static Future<DownloadIslandVariant> read() async {
    final id = await _channel.invokeMethod<String>('getIslandVariant');
    return DownloadIslandVariant.fromId(id);
  }

  static Future<void> write(DownloadIslandVariant variant) =>
      _channel.invokeMethod<void>('setIslandVariant', variant.id);
}
