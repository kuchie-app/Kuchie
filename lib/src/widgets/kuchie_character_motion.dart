import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'kuchie_face.dart';

enum KuchieCharacterPhase {
  intro('intro'),
  loading('loading'),
  fetchFailed('fetch-failed'),
  offline('offline'),
  error('error'),
  empty('empty', face: KuchieFace.empty),
  noResults('no-results', face: KuchieFace.noResults),
  downloadPaused('download-paused', face: KuchieFace.paused),
  complete('complete');

  const KuchieCharacterPhase(this.assetName, {this.face});
  final String assetName;

  /// Quiet states show Kuchie as a text face instead of artwork.
  final String? face;
}

/// Kiri's illustration for a screen or operation state, or Kuchie's text
/// face for the quiet ones (empty, no results, paused).
///
/// Only the loading WebP loops. Each other scene plays once and retains its
/// last frame. A static pose is shown with Reduce Motion or a muted TickerMode.
class KuchieCharacterMotion extends StatelessWidget {
  const KuchieCharacterMotion({
    super.key,
    required this.phase,
    this.width = 176,
    this.play = true,
    this.semanticsLabel,
  }) : assert(width > 0 && width < double.infinity);

  final KuchieCharacterPhase phase;
  final double width;
  final bool play;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    if (phase.face case final face?) {
      final label = semanticsLabel;
      final shown = KuchieFace(face, width: width);
      return label == null ? shown : Semantics(label: label, child: shown);
    }
    final stem = 'assets/kuchie/character/${phase.assetName}';
    final stillPath = '$stem.png';
    final bundle = DefaultAssetBundle.of(context);
    final animate =
        play &&
        !(MediaQuery.maybeDisableAnimationsOf(context) ?? false) &&
        TickerMode.valuesOf(context).enabled;
    final decodeWidth =
        (width * (MediaQuery.maybeDevicePixelRatioOf(context) ?? 1))
            .round()
            .clamp(1, 480);

    final art = animate
        ? _CharacterPlayback(
            key: ValueKey((phase, bundle)),
            path: '$stem.webp',
            stillPath: stillPath,
            bundle: bundle,
            decodeWidth: decodeWidth,
          )
        : _still(stillPath, bundle, decodeWidth);
    final illustration = SizedBox(
      width: width,
      height: width * 0.75,
      child: art,
    );
    final label = semanticsLabel;
    return label == null
        ? illustration
        : Semantics(image: true, label: label, child: illustration);
  }
}

Widget _still(String path, AssetBundle bundle, int decodeWidth) => Image.asset(
  path,
  bundle: bundle,
  scale: 1,
  fit: BoxFit.contain,
  cacheWidth: decodeWidth,
  excludeFromSemantics: true,
  errorBuilder: (context, error, stack) => const SizedBox.expand(),
);

class _CharacterPlayback extends StatefulWidget {
  const _CharacterPlayback({
    super.key,
    required this.path,
    required this.stillPath,
    required this.bundle,
    required this.decodeWidth,
  });

  final String path;
  final String stillPath;
  final AssetBundle bundle;
  final int decodeWidth;

  @override
  State<_CharacterPlayback> createState() => _CharacterPlaybackState();
}

class _CharacterPlaybackState extends State<_CharacterPlayback> {
  // Flutter caches decoded image streams by bundle and asset name. Each mounted
  // playback gets a new bundle identity so revisiting a state starts at frame 1.
  late final _bundle = _PlaybackBundle(widget.bundle);

  ImageProvider _provider(int width) =>
      ResizeImage(ExactAssetImage(widget.path, bundle: _bundle), width: width);

  @override
  Widget build(BuildContext context) => Image(
    image: _provider(widget.decodeWidth),
    fit: BoxFit.contain,
    excludeFromSemantics: true,
    errorBuilder: (context, error, stack) =>
        _still(widget.stillPath, widget.bundle, widget.decodeWidth),
  );

  @override
  void didUpdateWidget(covariant _CharacterPlayback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.decodeWidth != widget.decodeWidth) {
      _evict(oldWidget.decodeWidth);
    }
  }

  Future<void> _evict(int width) async {
    final key = await _provider(width).obtainKey(ImageConfiguration.empty);
    PaintingBinding.instance.imageCache.evict(key, includeLive: false);
  }

  @override
  void dispose() {
    _evict(widget.decodeWidth);
    super.dispose();
  }
}

class _PlaybackBundle extends AssetBundle {
  _PlaybackBundle(this.source);

  final AssetBundle source;

  @override
  Future<ByteData> load(String key) => source.load(key);

  @override
  Future<ui.ImmutableBuffer> loadBuffer(String key) => source.loadBuffer(key);
}
