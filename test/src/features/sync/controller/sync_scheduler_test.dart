import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuchie/src/features/sync/controller/sync_engine.dart';
import 'package:kuchie/src/features/sync/controller/sync_scheduler.dart';
import 'package:kuchie/src/features/sync/data/sync_state_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Counts cycles instead of running them.
class _CountingEngine extends SyncEngine {
  _CountingEngine(SyncStateStore store)
    : super(
        catalog: () => throw UnimplementedError(),
        store: store,
        probe: () => throw UnimplementedError(),
        backendAt: (_) => throw UnimplementedError(),
        localSources: () => throw UnimplementedError(),
        ensureServerIdentity: (_) => throw UnimplementedError(),
      );

  var cycles = 0;
  var cancels = 0;

  @override
  Future<void> prepare() async {}

  @override
  Future<SyncReport> sync({bool manual = false}) async {
    cycles++;
    return const SyncReport(SyncOutcome.synced);
  }

  @override
  void cancel() => cancels++;
}

void main() {
  late SyncStateStore store;
  late _CountingEngine engine;
  late StreamController<List<ConnectivityResult>> network;
  late DateTime now;
  late List<bool> background;

  SyncScheduler scheduler() => SyncScheduler(
    engine: engine,
    connectivity: network.stream,
    clock: () => now,
    background: (enabled) async => background.add(enabled),
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = SyncStateStore(await SharedPreferences.getInstance());
    await store.setConnectChoice(ConnectChoice.merge);
    engine = _CountingEngine(store);
    network = StreamController.broadcast();
    now = DateTime.utc(2026, 11, 28, 9);
    background = [];
  });

  tearDown(() => network.close());

  test('opening Kuchie syncs, at most every five minutes', () async {
    final schedule = scheduler()..start();
    await pumpEventQueue();
    expect(engine.cycles, 1);
    now = now.add(const Duration(minutes: 4));
    schedule.appShown();
    expect(engine.cycles, 1);
    now = now.add(const Duration(minutes: 2));
    schedule.appShown();
    expect(engine.cycles, 2);
    schedule.dispose();
  });

  test('the network coming back syncs', () async {
    final schedule = scheduler()..start();
    network.add([ConnectivityResult.wifi]);
    await pumpEventQueue();
    expect(engine.cycles, 1, reason: 'only the opening cycle');
    network.add([ConnectivityResult.none]);
    network.add([ConnectivityResult.wifi]);
    await pumpEventQueue();
    expect(engine.cycles, 2);
    schedule.dispose();
  });

  test('reading sends progress ten seconds after it stops', () {
    fakeAsync((async) {
      final schedule = scheduler()
        ..start()
        ..notifyChapterRead();
      async.elapse(const Duration(seconds: 5));
      schedule.notifyChapterRead();
      async.elapse(const Duration(seconds: 9));
      expect(engine.cycles, 1, reason: 'only the opening cycle');
      async.elapse(const Duration(seconds: 1));
      expect(engine.cycles, 2);
      schedule.dispose();
    });
  });

  test('going to the background stops the cycle and the pending push', () {
    fakeAsync((async) {
      final schedule = scheduler()
        ..start()
        ..notifyChapterRead()
        ..appHidden();
      async.elapse(const Duration(seconds: 30));
      expect(engine.cancels, 1);
      expect(engine.cycles, 1);
      schedule.dispose();
    });
  });

  test('background refresh follows whether sync is on', () async {
    final schedule = scheduler()..start();
    await pumpEventQueue();
    expect(background, [true]);
    await store.forgetServer();
    schedule.notifyChapterRead();
    schedule.appShown();
    await schedule.syncSettingsChanged();
    expect(background, [true, false]);
    expect(engine.cycles, 1, reason: 'nothing runs with sync off');
    schedule.dispose();
  });
}
