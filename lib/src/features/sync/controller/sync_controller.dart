import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../settings/data/server_connection/server_url.dart';
import '../data/sync_state_store.dart';
import '../domain/diagram/sync_methods.dart';
import '../domain/diagram/sync_scene.dart';
import '../domain/sync_method.dart';
import '../domain/sync_status.dart';
import 'sync_engine.dart';
import 'sync_engine_provider.dart';

/// What the Sync page, the More row and the Library icon show.
class SyncOverview {
  const SyncOverview({
    required this.method,
    required this.status,
    this.serverAddress,
    this.preview,
  });

  final SyncMethod method;
  final SyncStatus status;

  /// The Suwayomi address, for the method list.
  final String? serverAddress;

  /// A fake scene from the debug menu, shown instead of the real state.
  final SyncPreview? preview;

  SyncMethodSpec get methodSpec =>
      syncMethods[switch (method) {
        SyncMethod.none => SyncMethodKind.local,
        SyncMethod.suwayomi => SyncMethodKind.suwayomi,
        SyncMethod.icloud => SyncMethodKind.icloud,
      }]!;

  /// The diagram status for [status].
  SyncStatusKind get statusKind => switch (status) {
    SyncOff() => SyncStatusKind.local,
    SyncIdle() => SyncStatusKind.synced,
    SyncInProgress() || SyncPending() => SyncStatusKind.syncing,
    SyncWaitingForServer() => SyncStatusKind.waiting,
    SyncActionNeeded() => SyncStatusKind.action,
  };

  SyncFigures figures({int librarySize = 0}) => switch (status) {
    SyncIdle(:final lastSuccessAt) => SyncFigures(
      librarySize: librarySize,
      lastSuccessAt: lastSuccessAt,
      pending: 0,
    ),
    SyncWaitingForServer(:final lastSuccessAt, :final pending) => SyncFigures(
      librarySize: librarySize,
      lastSuccessAt: lastSuccessAt,
      pending: pending,
    ),
    SyncPending(:final count) => SyncFigures(
      librarySize: librarySize,
      pending: count,
    ),
    _ => SyncFigures(librarySize: librarySize, pending: 0),
  };

  /// The scene to draw: the preview, or the real state.
  SyncScene scene({int librarySize = 0}) {
    if (preview case final preview?) {
      return sceneFor(
        syncMethods[preview.method]!,
        preview.status,
        figures: SyncFigures(
          lastSuccessAt: preview.status == SyncStatusKind.synced
              ? DateTime.now().subtract(const Duration(minutes: 2))
              : null,
          pending: 3,
        ),
      );
    }
    return sceneFor(
      methodSpec,
      statusKind,
      figures: figures(librarySize: librarySize),
    );
  }

  /// Unsynced for over a week while waiting: one informational banner.
  bool isStale(DateTime now) {
    if (preview case final preview?) return preview.stale;
    return status is SyncWaitingForServer &&
        (status as SyncWaitingForServer).isStale(now);
  }
}

/// A scene picked from the debug menu, since the engine arrives later.
class SyncPreview {
  const SyncPreview(this.method, this.status, {this.stale = false});

  final SyncMethodKind method;
  final SyncStatusKind status;

  /// Waiting for over a week.
  final bool stale;
}

class SyncController extends Notifier<SyncOverview> {
  SyncPreview? _preview;
  SyncStatus? _status;
  final _timers = <Timer>[];

  @override
  SyncOverview build() {
    ref.onDispose(_cancelTimers);
    ref.watch(syncStateStoreProvider);
    ref.watch(serverUrlProvider);
    final engine = ref.watch(syncEngineProvider);
    engine.onStatus = _onStatus;
    ref.onDispose(() {
      if (engine.onStatus == _onStatus) engine.onStatus = null;
    });
    unawaited(engine.prepare().catchError((Object _) {}));
    return _compose();
  }

  SyncOverview _compose() {
    final store = ref.read(syncStateStoreProvider);
    // A server just connected counts as Suwayomi until its first sync
    // switches the method on.
    final method =
        store.method == SyncMethod.none && ref.read(syncEngineProvider).enabled
        ? SyncMethod.suwayomi
        : store.method;
    return SyncOverview(
      method: method,
      status: method == SyncMethod.none
          ? const SyncOff()
          : _status ?? SyncIdle(lastSuccessAt: store.lastSuccessAt),
      serverAddress: ref.read(serverUrlProvider),
      preview: _preview,
    );
  }

  void _onStatus(SyncStatus status) {
    _status = status;
    state = _compose();
  }

  /// Runs a full cycle now: Sync now, the Library icon, pull-to-refresh.
  Future<SyncReport> syncNow() =>
      ref.read(syncEngineProvider).sync(manual: true);

  void _cancelTimers() {
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
  }

  /// Shows [preview] instead of the real state; null goes back.
  void setPreview(SyncPreview? preview) {
    _cancelTimers();
    _preview = preview;
    state = SyncOverview(
      method: state.method,
      status: state.status,
      serverAddress: state.serverAddress,
      preview: preview,
    );
  }

  /// In a preview, plays what the main action would do: check, sync, done.
  /// [onFirstSync] runs when the run finishes, for Kiri's moment.
  void playPreviewRun({void Function()? onFirstSync}) {
    final preview = _preview;
    if (preview == null) return;
    final method = preview.method == SyncMethodKind.local
        ? SyncMethodKind.suwayomi
        : preview.method;
    final checks = syncMethods[method]!.statuses.contains(
      SyncStatusKind.analyzing,
    );
    setPreview(
      SyncPreview(
        method,
        checks ? SyncStatusKind.analyzing : SyncStatusKind.syncing,
      ),
    );
    void later(Duration delay, void Function() action) =>
        _timers.add(Timer(delay, action));
    final syncAt = checks ? const Duration(milliseconds: 2800) : Duration.zero;
    if (checks) {
      later(syncAt, () {
        _preview = SyncPreview(method, SyncStatusKind.syncing);
        state = SyncOverview(
          method: state.method,
          status: state.status,
          serverAddress: state.serverAddress,
          preview: _preview,
        );
      });
    }
    later(syncAt + const Duration(seconds: 9), () {
      _preview = SyncPreview(method, SyncStatusKind.synced);
      state = SyncOverview(
        method: state.method,
        status: state.status,
        serverAddress: state.serverAddress,
        preview: _preview,
      );
      onFirstSync?.call();
    });
  }
}

final syncControllerProvider = NotifierProvider<SyncController, SyncOverview>(
  SyncController.new,
);
