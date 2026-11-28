// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../graphql/__generated__/schema.graphql.dart';
import '../../account/data/account_providers.dart';
import '../../account/domain/account_access.dart';
import '../../auth/data/auth_state.dart';
import '../../local_collection/data/local_collection_providers.dart';
import '../../local_collection/data/local_download_queue.dart';
import '../../manga_book/domain/downloads/downloads_model.dart';
import '../../manga_book/presentation/downloads/controller/downloads_controller.dart';
import '../../manga_book/presentation/downloads/widgets/only_my_downloads.dart';
import '../../onboarding/data/onboarding_complete.dart';
import '../../sync/controller/server_transfers.dart';
import 'offline_download_progress.dart';
import 'offline_repository.dart';
import 'offline_settings_providers.dart';

const _channel = MethodChannel('kuchie/download_live_activity');
const _updateInterval = Duration(seconds: 2);

enum _DownloadSource { device, local, server }

typedef _DownloadSnapshot = ({
  _DownloadSource source,
  double? progress,
  int remaining,
});

bool isDownloadLiveActivityLink(Uri uri) =>
    uri.scheme == 'kuchie' &&
    uri.host == 'downloads' &&
    uri.path.isEmpty &&
    _DownloadSource.values.any(
      (source) => uri.queryParameters['tab'] == source.name,
    );

final downloadLiveActivityPendingProvider = StreamProvider.autoDispose<int>((
  ref,
) {
  if (!ref.watch(offlineActiveProvider)) return Stream.value(0);
  return ref.watch(offlineDatabaseProvider).watchPendingDownloadCount();
});

final _deviceSnapshotProvider = Provider.autoDispose<_DownloadSnapshot?>((ref) {
  if (!ref.watch(offlineActiveProvider)) return null;
  if (ref.watch(offlineDownloadsPausedProvider) ?? false) return null;
  final active = ref.watch(offlineDownloadProgressProvider);
  if (active.isEmpty) return null;
  final pending = ref.watch(downloadLiveActivityPendingProvider).value ?? 0;
  // The percentage belongs to the first active chapter, not the whole queue.
  final chapter = active.values.first;
  return (
    source: _DownloadSource.device,
    progress: chapter.total > 0
        ? (chapter.done / chapter.total).clamp(0.0, 1.0)
        : null,
    remaining: pending < active.length ? active.length : pending,
  );
});

final _serverDownloadsAvailableProvider = Provider.autoDispose<bool>((ref) {
  return (ref.watch(onboardingCompleteProvider) ?? false) &&
      !ref.watch(needsReauthProvider) &&
      ref
          .watch(settledAccountAccessProvider)
          .allows(Enum$UserPermission.DOWNLOAD_CHAPTERS);
});

final _serverSnapshotProvider = Provider.autoDispose<_DownloadSnapshot?>((ref) {
  if (!ref.watch(_serverDownloadsAvailableProvider)) return null;
  final live = ref.watch(
    downloadUpdatesProvider.select((data) => data.asData?.value?.state),
  );
  final queried = ref.watch(
    downloadStatusProvider.select((data) => data.asData?.value?.state),
  );
  if ((live ?? queried) == DownloaderState.STOPPED) {
    return null;
  }
  final queue = ref.watch(downloadsMapProvider);
  final hasAccounts = ref.watch(
    settledAccountAccessProvider.select(
      (access) => access.capability == AccountCapability.supported,
    ),
  );
  // On single-user servers every download belongs to the same account.
  final onlyMine =
      hasAccounts &&
      (!ref.watch(manageAllDownloadsProvider) ||
          (ref.watch(onlyMyDownloadsProvider) ?? true));
  DownloadDto? firstActive;
  var remaining = 0;
  for (final chapter in queue.values) {
    if (onlyMine && !isMyDownload(chapter)) continue;
    if (chapter.state == DownloadState.DOWNLOADING) {
      if (firstActive == null || chapter.position < firstActive.position) {
        firstActive = chapter;
      }
      remaining++;
    } else if (chapter.state == DownloadState.QUEUED) {
      remaining++;
    }
  }
  if (firstActive == null) return null;
  final progress = firstActive.progress;
  return (
    source: _DownloadSource.server,
    progress: progress.isFinite ? progress.clamp(0.0, 1.0) : null,
    remaining: remaining,
  );
});

final _snapshotProvider = Provider.autoDispose<_DownloadSnapshot?>((ref) {
  final device = ref.watch(_deviceSnapshotProvider);
  final server = ref.watch(_serverSnapshotProvider);
  return device ?? server;
});

class DownloadLiveActivityHost extends HookConsumerWidget {
  const DownloadLiveActivityHost({
    super.key,
    this.enabled = true,
    this.serverEnabled = true,
  });

  final bool enabled;
  final bool serverEnabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final container = ProviderScope.containerOf(context, listen: false);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final updates = useMemoized(_ActivityUpdates.new, [
      enabled,
      serverEnabled,
      container,
    ]);
    useEffect(() {
      updates.setReduceMotion(reduceMotion);
      return null;
    }, [updates, reduceMotion]);
    useEffect(() {
      if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return null;

      _DownloadSnapshot? serverSnapshot;
      LocalDownloadQueue? queue;
      // Downloads on the sync server (Kuchie 2.0), polled while open.
      ServerTransfers? transfers;
      try {
        transfers = ref.read(serverTransfersProvider);
      } catch (_) {
        // No sync storage in this container (tests, a session change).
      }
      _DownloadSnapshot? syncServerSnapshot() {
        final status = transfers?.status.value;
        if (status == null) return null;
        final (:open, :finished) = status;
        if (open == 0) return null;
        return (
          source: _DownloadSource.server,
          progress: finished / (finished + open),
          remaining: open,
        );
      }

      _DownloadSnapshot? currentSnapshot() {
        final jobs = queue?.value ?? const <LocalDownload>[];
        final job = jobs
            .where((item) => item.state == LocalDownloadState.downloading)
            .firstOrNull;
        if (job == null) return serverSnapshot ?? syncServerSnapshot();
        return (
          source: _DownloadSource.local,
          progress: job.pageCount == 0 ? null : job.done / job.pageCount,
          remaining: jobs
              .where(
                (item) =>
                    item.state == LocalDownloadState.downloading ||
                    item.state == LocalDownloadState.queued,
              )
              .length,
        );
      }

      void updateSnapshot() => updates.setSnapshot(currentSnapshot());
      void attachQueue() {
        queue?.removeListener(updateSnapshot);
        queue = ref.read(activeLocalDownloadQueueProvider);
        queue?.addListener(updateSnapshot);
        updateSnapshot();
      }

      final subscription = enabled && serverEnabled
          ? ref.listenManual(_snapshotProvider, (_, snapshot) {
              serverSnapshot = snapshot;
              updateSnapshot();
            }, fireImmediately: true)
          : null;
      final localQueueSubscription = ref.listenManual(
        activeLocalDownloadQueueProvider,
        (_, _) => attachQueue(),
      );
      attachQueue();
      transfers?.status.addListener(updateSnapshot);
      var resumeGeneration = 0;
      var wasPaused =
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.paused;
      Future<void> refreshOnResume() async {
        final generation = ++resumeGeneration;
        if (!enabled ||
            !serverEnabled ||
            !container.read(_serverDownloadsAvailableProvider)) {
          return;
        }
        // Reconnect the feed so its old run state can't override the new query.
        container.invalidate(downloadUpdatesProvider, asReload: true);
        container.invalidate(downloadStatusProvider);
        try {
          final status = await container.read(downloadStatusProvider.future);
          if (status == null) return;
          if (generation != resumeGeneration) return;
          serverSnapshot = container.read(_snapshotProvider);
          final snapshot = currentSnapshot();
          if (snapshot?.source != _DownloadSource.device &&
              snapshot?.source != _DownloadSource.local) {
            updates.refresh(snapshot);
          }
        } catch (_) {
          // Leave the old server activity stale if a fresh status is unavailable.
        }
      }

      final lifecycle = AppLifecycleListener(
        onPause: () {
          wasPaused = true;
          resumeGeneration++;
        },
        onResume: () {
          if (!wasPaused) {
            // Starting an activity can be denied while the app is inactive.
            updates.refreshCurrent();
            return;
          }
          wasPaused = false;
          updates.refreshDevice();
          unawaited(refreshOnResume());
        },
      );
      return () {
        resumeGeneration++;
        lifecycle.dispose();
        subscription?.close();
        localQueueSubscription.close();
        queue?.removeListener(updateSnapshot);
        transfers?.status.removeListener(updateSnapshot);
        updates.dispose();
      };
    }, [enabled, serverEnabled, container, updates]);
    return const SizedBox.shrink();
  }
}

class _ActivityUpdates {
  bool _reduceMotion = false;
  bool _sentInitial = false;
  bool _closed = false;
  _DownloadSnapshot? _latest;
  _DownloadSnapshot? _sent;
  Timer? _throttle;

  void setReduceMotion(bool value) {
    if (_reduceMotion == value) return;
    _reduceMotion = value;
    refreshCurrent();
  }

  void setSnapshot(_DownloadSnapshot? snapshot) {
    _latest = snapshot;
    if (snapshot == null) {
      // Give the next chapter time to start before removing the queue activity.
      if (_sent != null) {
        _throttle?.cancel();
        _throttle = Timer(_updateInterval, () {
          _throttle = null;
          _send();
        });
      } else if (!_sentInitial) {
        _send(); // Also clears a stale activity left by a previous app run.
      }
      return;
    }
    if (_sent == null) {
      _send();
    } else {
      _throttle ??= Timer(_updateInterval, () {
        _throttle = null;
        _send();
      });
    }
  }

  void refresh(_DownloadSnapshot? snapshot) {
    _latest = snapshot;
    _throttle?.cancel();
    _throttle = null;
    _send(force: true);
  }

  void refreshDevice() {
    if (_latest?.source == _DownloadSource.device ||
        _latest?.source == _DownloadSource.local) {
      refresh(_latest);
    }
  }

  void refreshCurrent() {
    if (_latest != null) refresh(_latest);
  }

  void _send({bool force = false}) {
    if (_closed || (!force && _sentInitial && _latest == _sent)) return;
    _sentInitial = true;
    _sent = _latest;
    unawaited(_deliver(_sent));
  }

  void dispose() {
    _throttle?.cancel();
    _closed = true;
    // A replacement host reconciles the active queue after a mode or session
    // change. Leave an ongoing Local activity in place until that happens.
    if (_sent != null && _sent?.source != _DownloadSource.local) {
      unawaited(_deliver(null));
    }
  }

  Future<void> _deliver(_DownloadSnapshot? snapshot) async {
    try {
      if (snapshot == null) {
        await _channel.invokeMethod<void>('end');
      } else {
        await _channel.invokeMethod<void>('update', {
          'source': snapshot.source.name,
          'progress': snapshot.progress,
          'remaining': snapshot.remaining,
          'reduceMotion': _reduceMotion,
        });
      }
    } on MissingPluginException {
      // Older builds can run downloads without a Live Activity.
    } on PlatformException {
      // A rejected activity must not interfere with downloads.
    }
  }
}
