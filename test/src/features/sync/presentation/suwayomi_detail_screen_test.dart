import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kuchie/src/features/local_collection/data/local_catalog.dart';
import 'package:kuchie/src/features/sync/controller/unsynced_series.dart';
import 'package:kuchie/src/features/sync/data/sync_state_store.dart';
import 'package:kuchie/src/features/sync/presentation/suwayomi_detail_screen.dart';
import 'package:kuchie/src/global_providers/global_providers.dart';
import 'package:kuchie/src/l10n/generated/app_localizations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

LocalSyncSeries _series(String id, {String? source = 'p:1'}) => LocalSyncSeries(
  id: id,
  title: id,
  inLibrary: true,
  source: source == null
      ? null
      : LocalSeriesSource(sourceId: source, mangaId: id, locator: '/$id'),
);

void main() {
  test('series only on this iPhone get their reason', () {
    final result = unsyncedSeries(
      library: [
        _series('import', source: null),
        _series('repo', source: 'kuchie.repo'),
        _series(
          'shinigami',
          source: 'eu.kanade.tachiyomi.extension.id.shinigami',
        ),
        _series('missing'),
        _series('failed'),
        _series('new'),
        _series('synced'),
      ],
      linked: {'failed', 'synced'},
      errors: {'missing': 'notOnServer', 'failed': 'requestFailed'},
    );
    expect(
      {for (final entry in result) entry.series.id: entry.reason},
      {
        'import': UnsyncedReason.importedFile,
        'repo': UnsyncedReason.kuchieRepo,
        // Built-in Shinigami syncs as the server's Shinigami extension.
        'shinigami': UnsyncedReason.waiting,
        'missing': UnsyncedReason.notOnServer,
        'failed': UnsyncedReason.requestFailed,
        'new': UnsyncedReason.waiting,
      },
    );
  });

  Future<SharedPreferences> pump(WidgetTester tester, Widget screen) async {
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: screen,
        ),
      ),
    );
    await tester.pump();
    return prefs;
  }

  testWidgets('Advanced switches what syncs', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await pump(tester, const SuwayomiAdvancedScreen());
    final meta = find.widgetWithText(SwitchListTile, 'Rating, tags & notes');
    expect(tester.widget<SwitchListTile>(meta).value, isFalse);
    await tester.tap(meta);
    await tester.pump();
    expect(SyncStateStore(prefs).includes(SyncDataKind.seriesMeta), isTrue);
    expect(tester.widget<SwitchListTile>(meta).value, isTrue);
  });

  testWidgets('the log lists cycles, newest first', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = SyncStateStore(prefs);
    await store.appendLog(
      SyncLogEntry(at: DateTime.utc(2026, 11, 28, 8), outcome: 'unreachable'),
    );
    await store.appendLog(
      SyncLogEntry(
        at: DateTime.utc(2026, 11, 28, 9),
        outcome: 'synced',
        pulled: 2,
        pushed: 3,
      ),
    );
    await pump(tester, const SyncLogScreen());
    final titles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((tile) => (tile.title! as Text).data)
        .toList();
    expect(titles, ['Synced', 'Server not reachable']);
    expect(find.textContaining('2 in, 3 out'), findsOneWidget);
  });
}
