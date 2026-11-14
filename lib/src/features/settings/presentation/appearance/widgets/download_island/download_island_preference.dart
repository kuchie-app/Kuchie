import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum DownloadIslandVariant {
  kiriRing('wajah-kiri-ring'),
  kiriPercentage('wajah-kiri-persen'),
  scarf('syal-penanda'),
  mangaPanel('panel-manga');

  const DownloadIslandVariant(this.id);

  final String id;

  static DownloadIslandVariant fromId(String? id) =>
      values.firstWhere((variant) => variant.id == id, orElse: () => kiriRing);
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
