import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

enum AppIconDesign {
  kiri(null, 'Kiri', 'kiri'),
  panelKiri('AppIcon-PanelKiri', 'Panel Kiri', 'panel-kiri'),
  capKertas('AppIcon-CapKertas', 'Cap Kertas', 'cap-kertas'),
  syalPenanda('AppIcon-SyalPenanda', 'Syal Penanda', 'syal-penanda'),
  openFrame('AppIcon-OpenFrame', 'Open Frame', 'open-frame');

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
  static const _imageFileName = 'Kuchie-Icon.png';

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

  Future<Uint8List?> pickImage() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'heic', 'heif', 'webp'],
    );
    if (file == null) return null;
    final path = file.path;
    if (path == null) throw const FormatException('Picker returned no path');
    final bytes = await _platform.invokeMethod<Uint8List>('prepareImage', path);
    if (bytes == null || bytes.isEmpty) {
      throw const FormatException('Icon image is empty');
    }
    return bytes;
  }

  Future<bool> saveImage(Uint8List image) async {
    final saved = await FilePicker.saveFile(
      fileName: _imageFileName,
      bytes: image,
      mimeType: 'image/png',
    );
    return saved != null;
  }

  Future<bool> openShortcuts() => launchUrl(
    Uri.parse('shortcuts://create-shortcut'),
    mode: LaunchMode.externalApplication,
  );
}
