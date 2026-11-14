// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kuchie/src/features/account/data/account_providers.dart';
import 'package:kuchie/src/features/account/domain/account_access.dart';
import 'package:kuchie/src/features/manga_book/domain/downloads/downloads_model.dart';
import 'package:kuchie/src/features/manga_book/domain/downloads_queue/downloads_queue_model.dart';
import 'package:kuchie/src/features/manga_book/presentation/downloads/controller/downloads_controller.dart';
import 'package:kuchie/src/features/manga_book/presentation/downloads/widgets/only_my_downloads.dart';
import 'package:kuchie/src/features/offline/data/download_live_activity.dart';
import 'package:kuchie/src/features/offline/data/offline_download_progress.dart';
import 'package:kuchie/src/features/offline/data/offline_repository.dart';
import 'package:kuchie/src/features/offline/data/offline_settings_providers.dart';
import 'package:kuchie/src/features/onboarding/data/onboarding_complete.dart';

class _OnboardingComplete extends OnboardingComplete {
  @override
  bool? build() => true;
}

class _OnboardingIncomplete extends OnboardingComplete {
  @override
  bool? build() => false;
}

class _OnlyMine extends OnlyMyDownloads {
  @override
  bool? build() => true;
}

Map<String, dynamic> _chapter(
  int id,
  String state,
  double progress, {
  bool inLibrary = true,
}) => {
  'chapter': {
    'id': id,
    'name': 'Chapter $id',
    'sourceOrder': id,
    'user': {'isDownloaded': false, '__typename': 'ChapterUserType'},
    'pageCount': 10,
    '__typename': 'ChapterType',
  },
  'manga': {
    'id': id,
    'title': 'Series $id',
    'user': {
      'downloadCount': 0,
      'inLibrary': inLibrary,
      '__typename': 'MangaUserType',
    },
    'thumbnailUrl': null,
    'source': null,
    '__typename': 'MangaType',
  },
  'progress': progress,
  'state': state,
  'tries': 0,
  'position': id,
  '__typename': 'DownloadType',
};

class _Pause extends OfflineDownloadsPaused {
  @override
  bool? build() => false;

  void pause() => state = true;
}

void main() {
  testWidgets('iOS publishes progress and ends when downloads pause', (
    tester,
  ) async {
    const channel = MethodChannel('kuchie/download_live_activity');
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return null;
    });
    var pendingSubscriptions = 0;
    var pendingDisposals = 0;
    final container = ProviderContainer(
      overrides: [
        offlineActiveProvider.overrideWith((ref) => true),
        onboardingCompleteProvider.overrideWith(_OnboardingIncomplete.new),
        downloadLiveActivityPendingProvider.overrideWith((ref) {
          pendingSubscriptions++;
          ref.onDispose(() => pendingDisposals++);
          return Stream.value(3);
        }),
        offlineDownloadsPausedProvider.overrideWith(_Pause.new),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const DownloadLiveActivityHost(),
      ),
    );
    await tester.pump(const Duration(seconds: 3));
    expect(calls.map((call) => call.method), ['end']);
    expect(pendingSubscriptions, 0);
    calls.clear();

    final progress = container.read(offlineDownloadProgressProvider.notifier);
    progress.start(1, done: 1, total: 4);
    await tester.pump();
    expect(pendingSubscriptions, 1);
    expect(calls.map((call) => call.method), ['update']);
    expect(calls.single.arguments, {
      'source': 'device',
      'progress': 0.25,
      'remaining': 1,
      'reduceMotion': false,
    });

    progress.start(1, done: 2, total: 4);
    progress.start(1, done: 3, total: 4);
    await tester.pump(const Duration(seconds: 2));
    expect(calls.map((call) => call.method), ['update', 'update']);
    expect(calls.last.arguments, {
      'source': 'device',
      'progress': 0.75,
      'remaining': 3,
      'reduceMotion': false,
    });

    final previousCalls = calls.length;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(calls.length - previousCalls, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(calls.length - previousCalls, 2);

    (container.read(offlineDownloadsPausedProvider.notifier) as _Pause).pause();
    await tester.pump(const Duration(seconds: 2));
    expect(calls.last.method, 'end');
    expect(calls.where((call) => call.method == 'end'), hasLength(1));
    expect(pendingDisposals, 1);
  }, variant: const TargetPlatformVariant({TargetPlatform.iOS}));

  testWidgets(
    'single-user server includes downloads outside the library and yields to the phone',
    (tester) async {
      const channel = MethodChannel('kuchie/download_live_activity');
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        return null;
      });
      final updates = StreamController<DownloadUpdatesDto?>.broadcast();
      addTearDown(updates.close);
      var queries = 0;
      var queueSorts = 0;
      final resumeStatus = Completer<DownloadStatusDto?>();
      final container = ProviderContainer(
        overrides: [
          offlineActiveProvider.overrideWith((ref) => true),
          offlineDownloadsPausedProvider.overrideWith(_Pause.new),
          downloadLiveActivityPendingProvider.overrideWith(
            (ref) => Stream.value(1),
          ),
          onboardingCompleteProvider.overrideWith(_OnboardingComplete.new),
          settledAccountAccessProvider.overrideWithValue(
            AccountAccess(capability: AccountCapability.unsupported),
          ),
          downloadUpdatesProvider.overrideWith((ref) => updates.stream),
          onlyMyDownloadsProvider.overrideWith(_OnlyMine.new),
          downloadStatusProvider.overrideWith(
            (ref) async => ++queries > 1
                ? resumeStatus.future
                : DownloadStatusDto.fromJson({
                    'state': 'STARTED',
                    'queue': [
                      _chapter(1, 'DOWNLOADING', 0.8, inLibrary: false),
                      _chapter(5, 'DOWNLOADING', 0.5),
                      _chapter(4, 'DOWNLOADING', 0.4),
                      _chapter(3, 'QUEUED', 0),
                      _chapter(2, 'ERROR', 0.3),
                    ],
                    '__typename': 'DownloadStatus',
                  }),
          ),
          downloadsChapterIdsProvider.overrideWith((ref) {
            queueSorts++;
            final chapters = ref.watch(downloadsMapProvider).values.toList()
              ..sort((a, b) => a.position.compareTo(b.position));
            return chapters.map((download) => download.chapter.id).toList();
          }),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const DownloadLiveActivityHost(),
        ),
      );
      await tester.pump();
      expect(calls.last.arguments, {
        'source': 'server',
        'progress': 0.8,
        'remaining': 4,
        'reduceMotion': false,
      });
      expect(queueSorts, 0);

      final progress = container.read(offlineDownloadProgressProvider.notifier);
      progress.start(9, done: 1, total: 2);
      await tester.pump(const Duration(seconds: 2));
      expect(calls.last.arguments, {
        'source': 'device',
        'progress': 0.5,
        'remaining': 1,
        'reduceMotion': false,
      });

      progress.clear(9);
      await tester.pump(const Duration(seconds: 2));
      expect(calls.last.arguments, {
        'source': 'server',
        'progress': 0.8,
        'remaining': 4,
        'reduceMotion': false,
      });

      updates.add(
        DownloadUpdatesDto.fromJson({
          'state': 'STARTED',
          'omittedUpdates': false,
          'updates': [],
          'initial': null,
          '__typename': 'DownloadUpdates',
        }),
      );
      await tester.pump();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(queries, 1);
      expect(calls.last.arguments, {
        'source': 'server',
        'progress': 0.8,
        'remaining': 4,
        'reduceMotion': false,
      });
      calls.clear();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(queries, 2);
      expect(calls, isEmpty);
      resumeStatus.complete(
        DownloadStatusDto.fromJson({
          'state': 'STOPPED',
          'queue': [_chapter(4, 'DOWNLOADING', 0.4)],
          '__typename': 'DownloadStatus',
        }),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(calls.last.method, 'end');
    },
    variant: const TargetPlatformVariant({TargetPlatform.iOS}),
  );

  testWidgets('Reduce Motion updates the active download without ending it', (
    tester,
  ) async {
    const channel = MethodChannel('kuchie/download_live_activity');
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return null;
    });
    final container = ProviderContainer(
      overrides: [
        offlineActiveProvider.overrideWith((ref) => true),
        onboardingCompleteProvider.overrideWith(_OnboardingIncomplete.new),
        downloadLiveActivityPendingProvider.overrideWith(
          (ref) => Stream.value(1),
        ),
        offlineDownloadsPausedProvider.overrideWith(_Pause.new),
      ],
    );
    addTearDown(container.dispose);

    Future<void> showActivity({required bool reduced}) => tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: const DownloadLiveActivityHost(),
        ),
      ),
    );

    await showActivity(reduced: false);
    final progress = container.read(offlineDownloadProgressProvider.notifier);
    progress.start(1, done: 2, total: 4);
    await tester.pump(const Duration(seconds: 2));
    calls.clear();

    const snapshot = {'source': 'device', 'progress': 0.5, 'remaining': 1};
    await showActivity(reduced: true);
    expect(calls.map((call) => call.method), ['update']);
    expect(calls.single.arguments, {...snapshot, 'reduceMotion': true});

    await showActivity(reduced: false);
    expect(calls.map((call) => call.method), ['update', 'update']);
    expect(calls.last.arguments, {...snapshot, 'reduceMotion': false});
  }, variant: const TargetPlatformVariant({TargetPlatform.iOS}));

  testWidgets('Android does not subscribe to downloads for Live Activities', (
    tester,
  ) async {
    var observedQueue = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          downloadLiveActivityPendingProvider.overrideWith((ref) {
            observedQueue = true;
            return Stream.value(3);
          }),
        ],
        child: const DownloadLiveActivityHost(),
      ),
    );
    expect(observedQueue, isFalse);
  }, variant: const TargetPlatformVariant({TargetPlatform.android}));

  test('downloads activity links identify their originating tab', () {
    expect(
      isDownloadLiveActivityLink(Uri.parse('kuchie://downloads?tab=device')),
      isTrue,
    );
    expect(
      isDownloadLiveActivityLink(Uri.parse('kuchie://downloads?tab=server')),
      isTrue,
    );
    expect(
      isDownloadLiveActivityLink(Uri.parse('kuchie://downloads?tab=local')),
      isTrue,
    );
    for (final url in [
      'https://downloads?tab=device',
      'kuchie://downloads?tab=other',
      'kuchie://tracker-oauth?tab=device',
      'kuchie://downloads/unexpected?tab=device',
    ]) {
      expect(isDownloadLiveActivityLink(Uri.parse(url)), isFalse);
    }
  });
}
