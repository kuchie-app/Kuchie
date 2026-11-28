import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kuchie/src/features/local_collection/data/local_collection_providers.dart';
import 'package:kuchie/src/features/sync/controller/sync_disconnect.dart';
import 'package:kuchie/src/features/sync/data/sync_journal.dart';
import 'package:kuchie/src/features/sync/data/sync_state_store.dart';
import 'package:kuchie/src/features/sync/domain/sync_change.dart';
import 'package:kuchie/src/features/sync/domain/sync_method.dart';
import 'package:kuchie/src/global_providers/global_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../helpers/local_collection_fakes.dart';

void main() {
  late Directory workspace;
  late ProviderContainer container;
  late SyncStateStore store;
  late SyncJournal journal;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('kuchie-disconnect');
    final services = fakeLocalCollectionServices(workspace);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    store = SyncStateStore(prefs);
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        ...localCollectionOverrides(services),
      ],
    );
    final catalog = services.catalog..journalEnabled = true;
    journal = SyncJournal(catalog);
    await catalog.setInLibrary(seriesId: 's', title: 'S', inLibrary: true);
    await journal.putLink(
      'suwayomi',
      const SyncLink(kind: SyncLinkKind.series, localKey: 's', remoteId: '1'),
    );
    await journal.putBase('suwayomi', SyncRecordKind.series, 's', {
      'inLibrary': true,
    });
    await journal.putTransfer(
      SyncTransfer(
        seriesId: 's',
        chapterId: 'c',
        keepLocal: false,
        state: SyncTransferState.requested,
        updatedAt: DateTime.utc(2026),
      ),
    );
    await store.setMethod(SyncMethod.suwayomi);
    await store.setServerIdentity('server-a');
  });

  tearDown(() async {
    container.dispose();
    await workspace.delete(recursive: true);
  });

  test('disconnecting forgets the server and keeps the library', () async {
    final catalog = (await container.read(
      localCollectionServicesProvider.future,
    )).catalog;
    await container.read(syncDisconnectProvider).disconnect();
    expect(await journal.links('suwayomi'), isEmpty);
    expect(await journal.base('suwayomi', SyncRecordKind.series, 's'), isNull);
    expect(await journal.transfers(), isEmpty);
    expect(await journal.pending(), isEmpty);
    expect(store.method, SyncMethod.none);
    expect(store.serverIdentity, isNull);
    expect((await catalog.syncSeries()).single.inLibrary, isTrue);
    expect(catalog.journalEnabled, isFalse);
  });

  test('a pending disconnect finishes once nothing is downloading', () async {
    await store.setDisconnectAfterSaving();
    await container.read(syncDisconnectProvider).finishPendingDisconnect();
    expect(store.method, SyncMethod.none);
    expect(store.disconnectAfterSaving, isFalse);
  });
}
