import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'local_collection_providers.dart';
import 'local_download_queue.dart';
import 'local_preferences.dart';

/// Applies the download preferences to a Local queue and decides what happens
/// to running downloads when Kuchie leaves the screen.
///
/// With background downloads on, iOS lends Kuchie a short stretch of time to
/// keep going. When that runs out, or with the setting off, the queue pauses
/// and the same chapters resume once Kuchie is back on screen. Pausing first
/// keeps a suspended download from ending up as failed.
class LocalDownloadLifecycle {
  LocalDownloadLifecycle(
    this.queue, {
    LocalPreferences? preferences,
    MethodChannel? channel,
    bool? supportsBackgroundTime,
  }) : _preferences = preferences ?? LocalPreferences.instance,
       _channel = channel ?? const MethodChannel('kuchie/background_downloads'),
       _supportsBackgroundTime =
           supportsBackgroundTime ??
           (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS);

  final LocalDownloadQueue queue;
  final LocalPreferences _preferences;
  final MethodChannel _channel;
  final bool _supportsBackgroundTime;

  AppLifecycleListener? _lifecycle;
  bool _disposed = false;
  bool _hidden = false;
  bool _borrowingTime = false;

  /// Chapters this class paused, to resume when Kuchie returns.
  final _pausedHere = <({String seriesId, String chapterId})>[];

  Future<void> start() async {
    await _preferences.load();
    if (_disposed) return;
    _preferences.downloadConcurrency.addListener(_applyConcurrency);
    _applyConcurrency();
    queue.addListener(_onQueueChanged);
    _lifecycle = AppLifecycleListener(onHide: onHidden, onShow: onShown);
    if (_supportsBackgroundTime) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'expired') await _pauseForBackground();
      });
    }
  }

  void _applyConcurrency() =>
      queue.concurrency = _preferences.downloadConcurrency.value;

  @visibleForTesting
  Future<void> onHidden() async {
    _hidden = true;
    if (!queue.running) return;
    if (_supportsBackgroundTime && _preferences.backgroundDownloads.value) {
      _borrowingTime = await _beginBackgroundTime();
      if (_borrowingTime) return;
    } else if (_preferences.backgroundDownloads.value) {
      // Other platforms keep the process alive for a while on their own.
      return;
    }
    await _pauseForBackground();
  }

  @visibleForTesting
  Future<void> onShown() async {
    _hidden = false;
    await _endBackgroundTime();
    final paused = [..._pausedHere];
    _pausedHere.clear();
    for (final chapter in paused) {
      await queue.resume(chapter.seriesId, chapter.chapterId);
    }
  }

  Future<void> _pauseForBackground() async {
    for (final item in queue.value) {
      if (item.state == LocalDownloadState.queued ||
          item.state == LocalDownloadState.downloading) {
        _pausedHere.add((
          seriesId: item.request.seriesId,
          chapterId: item.request.chapterId,
        ));
      }
    }
    await queue.pauseAll();
  }

  void _onQueueChanged() {
    // Hand the time back as soon as there is nothing left to download.
    if (_hidden && _borrowingTime && !queue.running) {
      unawaited(_endBackgroundTime());
    }
  }

  Future<bool> _beginBackgroundTime() async {
    try {
      return await _channel.invokeMethod<bool>('begin') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> _endBackgroundTime() async {
    if (!_borrowingTime) return;
    _borrowingTime = false;
    try {
      await _channel.invokeMethod<void>('end');
    } on MissingPluginException {
      // Nothing was borrowed.
    } on PlatformException {
      // iOS already took the time back.
    }
  }

  void dispose() {
    _disposed = true;
    _preferences.downloadConcurrency.removeListener(_applyConcurrency);
    queue.removeListener(_onQueueChanged);
    _lifecycle?.dispose();
    if (_supportsBackgroundTime) _channel.setMethodCallHandler(null);
    unawaited(_endBackgroundTime());
  }
}

/// Keeps a [LocalDownloadLifecycle] attached to the active Local queue for as
/// long as the app runs.
class LocalDownloadLifecycleHost extends HookConsumerWidget {
  const LocalDownloadLifecycleHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(activeLocalDownloadQueueProvider);
    useEffect(() {
      if (queue == null) return null;
      final lifecycle = LocalDownloadLifecycle(queue);
      unawaited(lifecycle.start());
      return lifecycle.dispose;
    }, [queue]);
    return const SizedBox.shrink();
  }
}
