import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kuchie/src/features/sync/controller/connect_analysis.dart';
import 'package:kuchie/src/features/sync/controller/sync_engine.dart';
import 'package:kuchie/src/features/sync/controller/sync_engine_provider.dart';
import 'package:kuchie/src/features/sync/data/suwayomi/suwayomi_identity.dart';
import 'package:kuchie/src/features/sync/data/suwayomi/suwayomi_library_reader.dart';
import 'package:kuchie/src/features/sync/data/sync_state_store.dart';
import 'package:kuchie/src/features/sync/presentation/suwayomi_connect_flow.dart';
import 'package:kuchie/src/global_providers/global_providers.dart';
import 'package:kuchie/src/l10n/generated/app_localizations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records first syncs instead of running them.
class _RecordingEngine extends SyncEngine {
  _RecordingEngine(SyncStateStore store)
    : super(
        catalog: () => throw UnimplementedError(),
        store: store,
        probe: () => throw UnimplementedError(),
        backendAt: (_) => throw UnimplementedError(),
        localSources: () => throw UnimplementedError(),
        ensureServerIdentity: (_) => throw UnimplementedError(),
      );

  final runs = <bool>[];

  @override
  Future<void> prepare() async {}

  @override
  Future<SyncReport> sync({bool manual = false}) async {
    runs.add(manual);
    return const SyncReport(SyncOutcome.skipped);
  }
}

LocalSeriesRef _local(String id, {String? source = 'p:1'}) => LocalSeriesRef(
  id: id,
  title: id,
  sourceId: source,
  locator: source == null ? null : '/$id',
);

RemoteSeriesRef _remote(int id, String url, {String source = '1'}) =>
    RemoteSeriesRef(id: id, title: url, sourceId: source, url: '/$url');

ConnectAnalysis _analyze(
  List<LocalSeriesRef> local,
  List<RemoteSeriesRef> remote,
) => analyzeConnection(
  serverAddress: 'http://server',
  local: local,
  server: ServerLibrary(series: remote, packages: {'p'}),
  localSourceIds: {'1'},
);

void main() {
  test('an empty iPhone copies the server', () {
    final a = _analyze([], [_remote(1, 'a'), _remote(2, 'b')]);
    expect(a.branch, ConnectBranch.localEmpty);
    expect(a.impliedChoice, ConnectChoice.useServer);
    expect((a.localCount, a.remoteCount, a.onlyRemote), (0, 2, 2));
  });

  test('an empty server gets this iPhone, except what it cannot read', () {
    final a = _analyze([
      _local('a'),
      _local('b'),
      _local('cbz', source: null),
    ], []);
    expect(a.branch, ConnectBranch.remoteEmpty);
    expect(a.impliedChoice, ConnectChoice.useLocal);
    expect((a.sendable, a.unsendable), (2, 1));
  });

  test('matching libraries just sync', () {
    final a = _analyze(
      [_local('a'), _local('b')],
      [_remote(1, 'a'), _remote(2, 'b')],
    );
    expect(a.branch, ConnectBranch.allMatched);
    expect(a.impliedChoice, ConnectChoice.merge);
    expect(a.matched, 2);
  });

  test('different libraries ask, with every number of the report', () {
    final a = _analyze(
      [_local('a'), _local('b'), _local('cbz', source: null)],
      [_remote(1, 'a'), _remote(2, 'c'), _remote(3, 'd', source: '9')],
    );
    expect(a.branch, ConnectBranch.differs);
    expect(a.impliedChoice, isNull);
    expect((a.localCount, a.remoteCount, a.matched), (3, 3, 1));
    expect((a.onlyLocal, a.sendable, a.unsendable), (2, 1, 1));
    expect((a.onlyRemote, a.readableHere, a.notReadableHere), (2, 1, 1));
  });

  test(
    'the choice is saved for the engine and forgotten on disconnect',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = SyncStateStore(await SharedPreferences.getInstance());
      expect(store.connectChoice, isNull);
      await store.setConnectChoice(ConnectChoice.useServer);
      expect(store.connectChoice, ConnectChoice.useServer);
      await store.forgetServer();
      expect(store.connectChoice, isNull);
    },
  );

  group('report', () {
    Future<List<ConnectChoice>> pump(
      WidgetTester tester,
      ConnectAnalysis a,
    ) async {
      final saved = <ConnectChoice>[];
      var choice = ConnectChoice.merge;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SingleChildScrollView(
                child: ConnectReport(
                  analysis: a,
                  choice: choice,
                  onChoice: (value) => setState(() => choice = value),
                  onSave: saved.add,
                ),
              ),
            ),
          ),
        ),
      );
      return saved;
    }

    testWidgets('libraries that differ offer three choices', (tester) async {
      final saved = await pump(
        tester,
        _analyze(
          [_local('a'), _local('b')],
          [_remote(1, 'a'), _remote(2, 'c')],
        ),
      );
      expect(find.text('The libraries differ'), findsOneWidget);
      expect(
        find.text('1 series leave the iPhone library. Downloads stay.'),
        findsOneWidget,
      );
      expect(find.text('1 series leave the server library.'), findsOneWidget);
      await tester.tap(find.text('Use the server library'));
      await tester.pump();
      await tester.ensureVisible(find.text('Start sync'));
      await tester.tap(find.text('Start sync'));
      expect(saved, [ConnectChoice.useServer]);
    });

    testWidgets('other branches save their own way without asking', (
      tester,
    ) async {
      final saved = await pump(tester, _analyze([], [_remote(1, 'a')]));
      expect(find.text('Copy the server library'), findsOneWidget);
      expect(find.byType(RadioListTile<ConnectChoice>), findsNothing);
      await tester.ensureVisible(find.text('Start sync'));
      await tester.tap(find.text('Start sync'));
      expect(saved, [ConnectChoice.useServer]);
    });
  });

  testWidgets('the flow saves the choice and starts the first sync', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final engine = _RecordingEngine(SyncStateStore(prefs));
    final analysis = _analyze([], [_remote(1, 'a')]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          connectAnalysisProvider.overrideWith((ref) async => analysis),
          syncEngineProvider.overrideWithValue(engine),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SuwayomiConnectFlow(skipServerStep: true),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Copy the server library'), findsOneWidget);
    await tester.ensureVisible(find.text('Start sync'));
    await tester.tap(find.text('Start sync'));
    await tester.pump();
    expect(find.text('Sync started'), findsOneWidget);
    // The cycle itself writes the rest; the recording engine runs none.
    expect(prefs.getKeys().where((key) => key.startsWith('sync.')), [
      SyncStateStore.connectChoiceKey,
    ]);
    expect(SyncStateStore(prefs).connectChoice, ConnectChoice.useServer);
    expect(engine.runs, [true]);
  });
}
