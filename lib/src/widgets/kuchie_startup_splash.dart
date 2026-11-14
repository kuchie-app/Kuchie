import 'dart:async';

import 'package:flutter/widgets.dart';

import '../utils/theme/launch_colors.dart';

const _assetFolder = 'assets/kuchie/splash';
const _loadingPose = ExactAssetImage('$_assetFolder/kiri-loading.png');

/// Keep the native launch screen visible until Flutter has the matching pose.
void prepareKuchieStartupFrame(WidgetsBinding binding) {
  binding.deferFirstFrame();
  final stream = _loadingPose.resolve(ImageConfiguration.empty);
  late final Timer timeout;
  late final ImageStreamListener listener;

  void release() {
    timeout.cancel();
    stream.removeListener(listener);
    binding.allowFirstFrame();
  }

  timeout = Timer(const Duration(milliseconds: 250), release);
  listener = ImageStreamListener((image, _) {
    image.dispose();
    release();
  }, onError: (_, _) => release());
  stream.addListener(listener);
}

/// Mount once per cold launch. Set [ready] when [child] can be shown.
class KuchieStartupSplash extends StatefulWidget {
  const KuchieStartupSplash({
    super.key,
    required this.ready,
    required this.child,
    this.reduceMotion = false,
    this.loadingLabel = 'Loading Kuchie',
  }) : assert(!ready || child != null);

  final bool ready;
  final Widget? child;
  final bool reduceMotion;
  final String loadingLabel;

  @override
  State<KuchieStartupSplash> createState() => _KuchieStartupSplashState();
}

enum _Phase { loading, greeting, fading, done }

class _KuchieStartupSplashState extends State<KuchieStartupSplash> {
  static const _background = kLaunchScreenBackground;
  static const _greetingLength = Duration(milliseconds: 480);
  static const _handoffLength = Duration(milliseconds: 160);
  static const _greetingBlend = Duration(milliseconds: 80);

  late _Phase _phase;
  bool _systemReducesMotion = false;
  bool _greetingVisible = false;
  bool _showLoadingLoop = true;
  bool _greetingFrameQueued = false;
  Timer? _timer;

  bool get _reduceMotion => widget.reduceMotion || _systemReducesMotion;

  @override
  void initState() {
    super.initState();
    _phase = widget.ready ? _Phase.done : _Phase.loading;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _systemReducesMotion = MediaQuery.disableAnimationsOf(context);
    _skipMotionIfNeeded();
  }

  @override
  void didUpdateWidget(KuchieStartupSplash oldWidget) {
    super.didUpdateWidget(oldWidget);
    _skipMotionIfNeeded();
    if (_phase != _Phase.loading || !widget.ready) return;

    _phase = _Phase.greeting;
    // Release the app if the local animation fails to deliver a first frame.
    _timer = Timer(const Duration(milliseconds: 800), _beginHandoff);
  }

  void _skipMotionIfNeeded() {
    if (_reduceMotion && widget.ready) {
      _timer?.cancel();
      _phase = _Phase.done;
    }
  }

  void _greetingDecoded({required bool succeeded}) {
    if (_phase != _Phase.greeting || _greetingFrameQueued) return;
    _greetingFrameQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _phase != _Phase.greeting) return;
      if (!succeeded) {
        _beginHandoff();
        return;
      }
      setState(() => _greetingVisible = true);
      _timer?.cancel();
      _timer = Timer(_greetingLength, _beginHandoff);
    });
  }

  void _beginHandoff() {
    if (!mounted || _phase != _Phase.greeting) return;
    _timer?.cancel();
    setState(() => _phase = _Phase.fading);
  }

  void _completeHandoff() {
    if (_phase == _Phase.fading) {
      setState(() => _phase = _Phase.done);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Widget _image(
    ImageProvider image, {
    ImageFrameBuilder? frameBuilder,
    ImageErrorWidgetBuilder? errorBuilder,
  }) {
    return Image(
      image: image,
      width: 224,
      height: 192,
      fit: BoxFit.contain,
      excludeFromSemantics: true,
      frameBuilder: frameBuilder,
      errorBuilder: errorBuilder ?? (_, _, _) => const SizedBox.shrink(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.child;
    final done = _phase == _Phase.done;

    return Stack(
      fit: StackFit.expand,
      alignment: Alignment.center,
      children: [
        if (child != null)
          Positioned.fill(
            key: const ValueKey('application'),
            child: ExcludeSemantics(
              excluding: !done,
              child: ExcludeFocus(
                excluding: !done,
                child: IgnorePointer(ignoring: !done, child: child),
              ),
            ),
          ),
        if (!done)
          Positioned.fill(
            key: const ValueKey('startup-splash'),
            child: AnimatedOpacity(
              opacity: _phase == _Phase.fading ? 0 : 1,
              duration: _handoffLength,
              onEnd: _completeHandoff,
              child: ColoredBox(
                color: _background,
                child: Semantics(
                  label: widget.loadingLabel,
                  liveRegion: true,
                  textDirection: TextDirection.ltr,
                  child: Center(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (_showLoadingLoop)
                          _reduceMotion
                              ? _image(_loadingPose)
                              : _image(
                                  const ExactAssetImage(
                                    '$_assetFolder/kiri-loading.webp',
                                  ),
                                  frameBuilder: (_, image, frame, _) =>
                                      frame == null
                                      ? _image(_loadingPose)
                                      : image,
                                  errorBuilder: (_, _, _) =>
                                      _image(_loadingPose),
                                ),
                        if (_phase != _Phase.loading)
                          AnimatedOpacity(
                            opacity: _greetingVisible ? 1 : 0,
                            duration: _greetingBlend,
                            onEnd: () {
                              if (_greetingVisible && _showLoadingLoop) {
                                setState(() => _showLoadingLoop = false);
                              }
                            },
                            child: ColoredBox(
                              color: _background,
                              child: _image(
                                const ExactAssetImage(
                                  '$_assetFolder/kiri-ready.webp',
                                ),
                                frameBuilder: (_, image, frame, _) {
                                  if (frame != null) {
                                    _greetingDecoded(succeeded: true);
                                  }
                                  return image;
                                },
                                errorBuilder: (_, _, _) {
                                  _greetingDecoded(succeeded: false);
                                  return const SizedBox.shrink();
                                },
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
