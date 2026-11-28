import 'package:flutter_test/flutter_test.dart';
import 'package:kuchie/src/features/sync/data/sync_state_store.dart';
import 'package:kuchie/src/features/sync/domain/sync_method.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences prefs;
  late SyncStateStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'other.key': 'kept'});
    prefs = await SharedPreferences.getInstance();
    store = SyncStateStore(prefs);
  });

  test('starts off, with everything but rating, tags and notes included', () {
    expect(store.method, SyncMethod.none);
    expect(store.serverIdentity, isNull);
    expect(store.userId, isNull);
    expect(store.lastSuccessAt, isNull);
    expect(store.lastError, isNull);
    expect(store.chapterCursor, isNull);
    expect(
      [
        for (final kind in SyncDataKind.values)
          if (!store.includes(kind)) kind,
      ],
      [SyncDataKind.seriesMeta],
    );
    expect(store.choseIncludes(SyncDataKind.seriesMeta), isFalse);
  });

  test('the log keeps the newest 200 cycles', () async {
    for (var i = 0; i < SyncStateStore.logLength + 5; i++) {
      await store.appendLog(
        SyncLogEntry(
          at: DateTime.utc(2026, 11, 28, 0, i),
          outcome: 'synced',
          pushed: i,
        ),
      );
    }
    final log = store.log;
    expect(log, hasLength(SyncStateStore.logLength));
    expect(log.first.pushed, SyncStateStore.logLength + 4);
    expect(log.first.at, DateTime.utc(2026, 11, 28, 0, 204));
    await store.forgetServer();
    expect(store.log, isEmpty);
  });

  test('keeps the method under sync.method; none removes it', () async {
    await store.setMethod(SyncMethod.suwayomi);
    expect(prefs.getString('sync.method'), 'suwayomi');
    expect(store.method, SyncMethod.suwayomi);
    await store.setMethod(SyncMethod.none);
    expect(prefs.containsKey('sync.method'), isFalse);
  });

  test('a success clears the last error', () async {
    await store.recordError('timeout');
    expect(store.lastError, 'timeout');
    final at = DateTime.utc(2026, 11, 27, 9, 15);
    await store.recordSuccess(at);
    expect(store.lastSuccessAt, at);
    expect(store.lastError, isNull);
  });

  test('stores identity, account, cursor and choices', () async {
    await store.setServerIdentity('abc');
    await store.setUserId('7');
    await store.setChapterCursor(1795716439);
    await store.setIncludes(SyncDataKind.readerMeta, false);
    expect(store.serverIdentity, 'abc');
    expect(store.userId, '7');
    expect(store.chapterCursor, 1795716439);
    expect(store.includes(SyncDataKind.readerMeta), isFalse);
    expect(prefs.getBool('sync.prefs.readerMeta'), isFalse);
    await store.setUserId(null);
    expect(store.userId, isNull);
  });

  test('forgetting the server keeps choices and other settings', () async {
    await store.setMethod(SyncMethod.suwayomi);
    await store.setServerIdentity('abc');
    await store.setUserId('7');
    await store.setChapterCursor(10);
    await store.recordSuccess(DateTime.utc(2026));
    await store.recordError('x');
    await store.setIncludes(SyncDataKind.bookmarks, false);

    await store.forgetServer();

    expect(prefs.getKeys(), {'sync.prefs.bookmarks', 'other.key'});
    expect(store.method, SyncMethod.none);
    expect(store.includes(SyncDataKind.bookmarks), isFalse);
  });
}
