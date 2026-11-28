import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'sync_background.dart';
import 'sync_engine.dart';
import 'sync_engine_provider.dart';

/// When a sync cycle runs on its own (design 4.4): Kuchie coming to the
/// foreground at most every 5 minutes, the network coming back, and 10
/// seconds after the reader stops reading. Manual syncs go straight to the
/// engine. Cycles stop when Kuchie goes to the background.
class SyncScheduler {
  SyncScheduler({
    required this.engine,
    Stream<List<ConnectivityResult>>? connectivity,
    DateTime Function()? clock,
    this.foregroundGap = const Duration(minutes: 5),
    this.readDelay = const Duration(seconds: 10),
    Future<void> Function(bool enabled)? background,
  }) : _connectivity = connectivity,
       _clock = clock ?? DateTime.now,
       _background = background;

  final SyncEngine engine;
  final Stream<List<ConnectivityResult>>? _connectivity;
  final DateTime Function() _clock;
  final Future<void> Function(bool enabled)? _background;
  final Duration foregroundGap;
  final Duration readDelay;

  StreamSubscription<List<ConnectivityResult>>? _network;
  bool? _online;
  Timer? _afterRead;
  DateTime? _lastForeground;
  bool _started = false;
  bool? _backgroundOn;

  /// Begins listening; safe to call more than once.
  void start() {
    if (_started) return;
    _started = true;
    unawaited(engine.prepare().catchError((Object _) {}));
    unawaited(syncSettingsChanged());
    _network = _connectivity?.listen((results) {
      final online = results.any((result) => result != ConnectivityResult.none);
      final cameBack = _online == false && online;
      _online = online;
      if (cameBack) _run();
    }, onError: (Object _) {});
    appShown();
  }

  /// Kuchie came to the foreground.
  void appShown() {
    final now = _clock();
    final last = _lastForeground;
    if (last != null && now.difference(last) < foregroundGap) return;
    _lastForeground = now;
    _run();
  }

  /// Kuchie went to the background: what is sent so far stays sent.
  void appHidden() {
    _afterRead?.cancel();
    _afterRead = null;
    engine.cancel();
  }

  /// The reader stopped or finished a chapter; its progress goes out soon.
  void notifyChapterRead() {
    if (!engine.enabled) return;
    _afterRead?.cancel();
    _afterRead = Timer(readDelay, () {
      _afterRead = null;
      _run();
    });
  }

  /// Sync turned on or off: background refresh follows it.
  Future<void> syncSettingsChanged() async {
    final enabled = engine.enabled;
    if (_backgroundOn == enabled) return;
    _backgroundOn = enabled;
    try {
      await _background?.call(enabled);
    } catch (_) {
      _backgroundOn = null;
      // Background refresh is a bonus (design 4.4); foreground still syncs.
    }
  }

  void _run() {
    if (!engine.enabled) return;
    unawaited(engine.sync().then((_) => syncSettingsChanged()));
  }

  void dispose() {
    _afterRead?.cancel();
    unawaited(_network?.cancel());
  }
}

final syncSchedulerProvider = Provider<SyncScheduler>((ref) {
  final scheduler = SyncScheduler(
    engine: ref.watch(syncEngineProvider),
    connectivity: Connectivity().onConnectivityChanged,
    background: scheduleBackgroundSync,
  );
  final lifecycle = AppLifecycleListener(
    onShow: scheduler.appShown,
    onHide: scheduler.appHidden,
  );
  ref.onDispose(() {
    lifecycle.dispose();
    scheduler.dispose();
  });
  return scheduler;
});
