import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// The icons bundled with Kuchie, named after what each one shows.
enum AppIconDesign {
  /// The primary icon: a purple bookmark ribbon.
  bookmarkScarf(null, 'Bookmark Scarf', 'bookmark-scarf'),

  /// Kiri, the mascot, in a hood and scarf.
  kiri('AppIcon-Kiri', 'Kiri', 'kiri'),

  /// Kiri looking out of a manga panel frame.
  framePeek('AppIcon-FramePeek', 'Frame Peek', 'frame-peek'),

  /// Kiri on a round seal stamped on cream paper.
  paperSeal('AppIcon-PaperSeal', 'Paper Seal', 'paper-seal');

  const AppIconDesign(this.alternateName, this.title, this._assetName);

  final String? alternateName;
  final String title;
  final String _assetName;

  String get previewAsset => 'assets/icons/app-icon-$_assetName.png';
}

class AppleAppIconState {
  const AppleAppIconState({this.available = false, this.current});

  factory AppleAppIconState.fromPlatform(Map<String, Object?>? data) {
    if (data == null) return const AppleAppIconState();
    final currentName = data['current'];
    return AppleAppIconState(
      available: data['available'] == true,
      current: AppIconDesign.values
          .where((design) => design.alternateName == currentName)
          .firstOrNull,
    );
  }

  final bool available;
  final AppIconDesign? current;
}

class AppleAppIcon {
  const AppleAppIcon();

  static bool get isIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static const _platform = MethodChannel('kuchie/app_icon');

  Future<AppleAppIconState> load() async {
    final data = await _platform.invokeMapMethod<String, Object?>('state');
    return AppleAppIconState.fromPlatform(data);
  }

  Future<AppleAppIconState> apply(AppIconDesign design) async {
    final data = await _platform.invokeMapMethod<String, Object?>(
      'setAlternateIcon',
      design.alternateName,
    );
    return AppleAppIconState.fromPlatform(data);
  }

  Future<bool> openShortcuts() => launchUrl(
    Uri.parse('shortcuts://create-shortcut'),
    mode: LaunchMode.externalApplication,
  );
}
