import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kuchie/src/features/local_collection/data/local_collection_platform.dart';
import 'package:kuchie/src/features/onboarding/data/onboarding_complete.dart';
import 'package:kuchie/src/features/onboarding/presentation/onboarding_screen.dart';
import 'package:kuchie/src/global_providers/global_providers.dart';
import 'package:kuchie/src/l10n/generated/app_localizations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Kuchie 2.0 onboarding on iOS (PR 18): the library is always on this
// iPhone, and a Suwayomi server can join through Sync.

void main() {
  test('the Server runtime runs only where Local is not supported', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      expect(container.read(serverCollectionRuntimeEnabledProvider), isFalse);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
    final android = ProviderContainer();
    addTearDown(android.dispose);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      expect(android.read(serverCollectionRuntimeEnabledProvider), isTrue);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  Future<SharedPreferences> pumpWelcome(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(402, 874);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await seedFirstRunPreferences(prefs);
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const OnboardingScreen()),
        GoRoute(
          path: '/local',
          builder: (_, _) => const Scaffold(body: Text('Local destination')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return prefs;
  }

  Future<void> tap(WidgetTester tester, String label) async {
    final target = find.text(label);
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    expect(target.hitTestable(), findsOneWidget);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  final ios = TargetPlatformVariant.only(TargetPlatform.iOS);

  testWidgets(
    'starting here goes to the library, no server step',
    variant: ios,
    (tester) async {
      final prefs = await pumpWelcome(tester);
      expect(find.text('Your library lives on this iPhone.'), findsOneWidget);
      await tap(tester, 'Start here');
      await tap(tester, 'Start reading');
      expect(find.text("You're all set"), findsOneWidget);
      expect(find.text('Connect your server'), findsNothing);
      await tap(tester, 'Start reading');
      expect(find.text('Local destination'), findsOneWidget);
      expect(prefs.getBool('onboardingComplete'), isTrue);
      expect(prefs.getBool(connectSyncAfterOnboardingKey), isNull);
    },
  );

  testWidgets('a Suwayomi server joins through Sync afterwards', variant: ios, (
    tester,
  ) async {
    final prefs = await pumpWelcome(tester);
    await tap(tester, 'Add a server');
    await tap(tester, 'Start reading');
    await tap(tester, 'Start reading');
    expect(find.text('Local destination'), findsOneWidget);
    expect(find.text('Connect your server'), findsNothing);
    expect(prefs.getBool(connectSyncAfterOnboardingKey), isTrue);
    expect(prefs.getBool('onboardingComplete'), isTrue);
  });
}
