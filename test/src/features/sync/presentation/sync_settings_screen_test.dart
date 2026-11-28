import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kuchie/src/features/sync/controller/sync_controller.dart';
import 'package:kuchie/src/features/sync/data/sync_state_store.dart';
import 'package:kuchie/src/features/sync/domain/diagram/sync_methods.dart';
import 'package:kuchie/src/features/sync/domain/diagram/sync_scene.dart';
import 'package:kuchie/src/features/sync/domain/sync_status.dart';
import 'package:kuchie/src/features/sync/presentation/diagram/sync_diagram.dart';
import 'package:kuchie/src/features/sync/presentation/diagram/sync_explainer.dart';
import 'package:kuchie/src/features/sync/presentation/sync_hero_card.dart';
import 'package:kuchie/src/features/sync/presentation/sync_settings_screen.dart';
import 'package:kuchie/src/features/sync/presentation/sync_status_icon.dart';
import 'package:kuchie/src/global_providers/global_providers.dart';
import 'package:kuchie/src/l10n/generated/app_localizations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app(Widget child, {bool reduceMotion = false}) => MaterialApp(
  localizationsDelegates: const [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
    child: child!,
  ),
  home: child,
);

void main() {
  late SharedPreferences prefs;

  Future<void> pumpScreen(
    WidgetTester tester, {
    Map<String, Object> values = const {SyncStateStore.explainerSeenKey: true},
    bool reduceMotion = false,
  }) async {
    SharedPreferences.setMockInitialValues(values);
    prefs = await SharedPreferences.getInstance();
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          syncLibrarySizeProvider.overrideWith((ref) async => 12),
        ],
        child: _app(
          const SyncSettingsScreen(debugPreview: false),
          reduceMotion: reduceMotion,
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> pumpCard(
    WidgetTester tester,
    SyncScene scene, {
    VoidCallback? onPrimary,
    bool reduceMotion = false,
  }) async {
    final explainer = SyncExplainer();
    addTearDown(explainer.dispose);
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: SingleChildScrollView(
            child: SyncHeroCard(
              scene: scene,
              explainer: explainer,
              onPrimary: onPrimary,
              now: DateTime.utc(2026, 11, 27, 10, 2),
            ),
          ),
        ),
        reduceMotion: reduceMotion,
      ),
    );
    await tester.pump();
  }

  testWidgets('the explainer plays once, then again from (?)', (tester) async {
    await pumpScreen(tester, values: const {});
    await tester.pump();
    expect(
      find.text('Without sync, everything stays on your iPhone.'),
      findsOneWidget,
    );
    expect(find.text('Explainer 1/3'), findsOneWidget);
    expect(prefs.getBool(SyncStateStore.explainerSeenKey), isTrue);

    // Each step lasts about 3.8 seconds.
    await tester.pump(const Duration(milliseconds: 3900));
    expect(
      find.text('With sync, your library and progress are copied too.'),
      findsOneWidget,
    );
    // A tap on the caption moves on.
    await tester.tap(
      find.text('With sync, your library and progress are copied too.'),
    );
    await tester.pump();
    expect(
      find.text("Server out of reach? You can still read."),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 3900));
    expect(find.text('Explainer 3/3'), findsNothing);
    expect(find.text('Only on this iPhone'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await pumpScreen(
      tester,
      values: const {SyncStateStore.explainerSeenKey: true},
    );
    expect(find.text('Explainer 1/3'), findsNothing);
    await tester.tap(find.byTooltip('Play how it works'));
    await tester.pump();
    expect(find.text('Explainer 1/3'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Reduce Motion schedules no frames and steps the explainer by tap',
    (tester) async {
      await pumpScreen(tester, values: const {}, reduceMotion: true);
      await tester.pump();
      expect(find.text('Explainer 1/3'), findsOneWidget);
      expect(SchedulerBinding.instance.transientCallbackCount, 0);
      await tester.pump(const Duration(seconds: 10));
      expect(find.text('Explainer 1/3'), findsOneWidget);
      await tester.tap(
        find.text('Without sync, everything stays on your iPhone.'),
      );
      await tester.pump();
      expect(find.text('Explainer 2/3'), findsOneWidget);
      // Once the tap's ink has faded, nothing animates.
      await tester.pump(const Duration(seconds: 1));
      expect(SchedulerBinding.instance.transientCallbackCount, 0);
    },
  );

  testWidgets('without Reduce Motion the diagram ticks', (tester) async {
    await pumpScreen(tester);
    expect(SchedulerBinding.instance.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the card reads its status and explanation as one node', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpCard(
      tester,
      sceneFor(
        suwayomiMethod,
        SyncStatusKind.synced,
        figures: SyncFigures(lastSuccessAt: DateTime.utc(2026, 11, 27, 10)),
      ),
    );
    expect(
      find.bySemanticsLabel(
        'Synced · 2 minutes ago. Your library and reading progress match on '
        'this iPhone, the server and your other devices.',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp('^Downloads, on the server, synced')),
      findsOneWidget,
    );
    handle.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the main action follows the status', (tester) async {
    var taps = 0;
    Future<void> expectAction(
      SyncScene scene,
      String label, {
      required bool secondary,
      required bool enabled,
    }) async {
      await pumpCard(tester, scene, onPrimary: () => taps++);
      final button = find.ancestor(
        of: find.text(label),
        matching: find.byType(secondary ? OutlinedButton : FilledButton),
      );
      expect(button, findsOneWidget, reason: label);
      expect(
        tester.widget<ButtonStyleButton>(button).enabled,
        enabled,
        reason: label,
      );
    }

    await expectAction(
      sceneFor(localMethod, SyncStatusKind.local),
      'Connect sync',
      secondary: false,
      enabled: true,
    );
    await expectAction(
      sceneFor(suwayomiMethod, SyncStatusKind.synced),
      'Sync now',
      secondary: true,
      enabled: true,
    );
    await expectAction(
      sceneFor(suwayomiMethod, SyncStatusKind.syncing),
      'Syncing…',
      secondary: false,
      enabled: false,
    );
    await expectAction(
      sceneFor(suwayomiMethod, SyncStatusKind.waiting),
      'Try again',
      secondary: true,
      enabled: true,
    );
    await expectAction(
      sceneFor(suwayomiMethod, SyncStatusKind.action),
      'Sign in again',
      secondary: false,
      enabled: true,
    );
    await expectAction(
      sceneFor(icloudMethod, SyncStatusKind.synced),
      'Coming soon',
      secondary: false,
      enabled: false,
    );
    await tester.tap(find.text('Coming soon'));
    expect(taps, 0);
    await expectAction(
      sceneFor(suwayomiMethod, SyncStatusKind.waiting),
      'Try again',
      secondary: true,
      enabled: true,
    );
    await tester.tap(find.text('Try again'));
    expect(taps, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a Coming soon row opens a preview sheet', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('Komga'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      find.text('Coming soon. Kuchie syncs with a Suwayomi server for now.'),
      findsOneWidget,
    );
    expect(find.byType(SyncDiagram), findsNWidgets(2));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the page shows the methods and the questions', (tester) async {
    await pumpScreen(tester);
    expect(find.text('Off'), findsOneWidget);
    expect(find.text('Suwayomi server'), findsOneWidget);
    expect(find.text('Coming soon'), findsNWidgets(6));
    expect(find.text('What is Sync?'), findsOneWidget);
    await tester.tap(find.text('What is Sync?'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.textContaining('works even when the server is down'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });

  group('Library icon and More subtitle', () {
    Future<ProviderContainer> pumpIcon(
      WidgetTester tester,
      Map<String, Object> values,
    ) async {
      SharedPreferences.setMockInitialValues(values);
      prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _app(
            Scaffold(
              appBar: AppBar(
                title: Row(
                  children: [
                    const Text('Library'),
                    SyncStatusIcon(onPressed: () {}),
                  ],
                ),
              ),
              body: Consumer(
                builder: (context, ref, _) => Text(
                  syncSummary(context, ref.watch(syncControllerProvider)),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return container;
    }

    testWidgets('sync off has no icon and reads Off', (tester) async {
      await pumpIcon(tester, const {});
      expect(find.byType(SyncCloudIcon), findsNothing);
      expect(find.text('Off'), findsOneWidget);
    });

    testWidgets('Suwayomi synced shows the check and when', (tester) async {
      final container = await pumpIcon(tester, {
        SyncStateStore.methodKey: 'suwayomi',
        SyncStateStore.lastSuccessAtKey: DateTime.now()
            .subtract(const Duration(minutes: 5))
            .millisecondsSinceEpoch,
      });
      expect(find.byType(SyncCloudIcon), findsOneWidget);
      expect(
        find.byTooltip('Synced with Suwayomi, 5 minutes ago'),
        findsOneWidget,
      );
      expect(find.text('Suwayomi · 5 minutes ago'), findsOneWidget);
      expect(container.read(syncControllerProvider).status, isA<SyncIdle>());
    });

    testWidgets('a preview drives the icon too', (tester) async {
      final container = await pumpIcon(tester, const {});
      container
          .read(syncControllerProvider.notifier)
          .setPreview(
            const SyncPreview(SyncMethodKind.suwayomi, SyncStatusKind.action),
          );
      await tester.pump();
      expect(
        find.byTooltip('Suwayomi needs you to sign in again'),
        findsOneWidget,
      );
      container.read(syncControllerProvider.notifier).setPreview(null);
      await tester.pump();
      expect(find.byType(SyncCloudIcon), findsNothing);
    });
  });

  testWidgets('a preview run checks, syncs, then celebrates', (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    final controller = container.read(syncControllerProvider.notifier)
      ..setPreview(
        const SyncPreview(SyncMethodKind.local, SyncStatusKind.local),
      );
    var celebrated = false;
    controller.playPreviewRun(onFirstSync: () => celebrated = true);
    expect(
      container.read(syncControllerProvider).preview!.status,
      SyncStatusKind.analyzing,
    );
    await tester.pump(const Duration(milliseconds: 2900));
    expect(
      container.read(syncControllerProvider).preview!.status,
      SyncStatusKind.syncing,
    );
    await tester.pump(const Duration(seconds: 9));
    expect(
      container.read(syncControllerProvider).preview!.status,
      SyncStatusKind.synced,
    );
    expect(celebrated, isTrue);
  });
}
