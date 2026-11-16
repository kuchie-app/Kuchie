import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kuchie/src/features/onboarding/data/collection_mode.dart';
import 'package:kuchie/src/features/onboarding/data/onboarding_complete.dart';
import 'package:kuchie/src/features/onboarding/presentation/onboarding_screen.dart';
import 'package:kuchie/src/global_providers/global_providers.dart';
import 'package:kuchie/src/l10n/generated/app_localizations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SharedPreferences> migrate(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  final preferences = await SharedPreferences.getInstance();
  await seedFirstRunPreferences(preferences);
  await seedCollectionMode(preferences);
  return preferences;
}

void main() {
  void testOnIos(String description, Future<void> Function() body) {
    test(description, () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await body();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  testOnIos('clean install leaves the collection choice open', () async {
    final preferences = await migrate({});
    expect(readCollectionMode(preferences), isNull);
    expect(preferences.getBool('onboardingComplete'), isFalse);
  });

  testOnIos(
    'upgrading a configured server selects Server without losing it',
    () async {
      const server = 'http://192.168.1.77:4567';
      final preferences = await migrate({
        'onboardingComplete': true,
        'serverExternalUrl': server,
      });
      expect(readCollectionMode(preferences), CollectionMode.server);
      expect(preferences.getString('serverExternalUrl'), server);
      expect(preferences.getBool('onboardingComplete'), isTrue);
    },
  );

  testOnIos(
    'an older skipped setup opens the chooser without selecting a mode',
    () async {
      final preferences = await migrate({'onboardingComplete': true});
      expect(readCollectionMode(preferences), isNull);
      expect(preferences.getBool('onboardingComplete'), isFalse);
    },
  );

  testOnIos(
    'switching collection preserves the saved server and its setup',
    () async {
      const server = 'https://server.example.test';
      final preferences = await migrate({'serverUrl': server});
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
      );
      addTearDown(container.dispose);
      final mode = container.read(collectionModeProvider.notifier);
      expect(container.read(serverCollectionRuntimeEnabledProvider), isTrue);

      await mode.select(CollectionMode.local);
      expect(container.read(serverCollectionRuntimeEnabledProvider), isFalse);
      expect(readCollectionMode(preferences), CollectionMode.local);
      expect(preferences.getString('serverUrl'), server);
      expect(preferences.getBool('onboardingComplete'), isTrue);

      await mode.select(CollectionMode.server);
      expect(container.read(serverCollectionRuntimeEnabledProvider), isTrue);
    },
  );

  testOnIos(
    'entering Server setup does not start global server work',
    () async {
      final preferences = await migrate({});
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
      );
      addTearDown(container.dispose);
      await container
          .read(collectionModeProvider.notifier)
          .select(CollectionMode.server);
      expect(container.read(serverCollectionRuntimeEnabledProvider), isFalse);
      container.read(onboardingCompleteProvider.notifier).update(true);
      expect(container.read(serverCollectionRuntimeEnabledProvider), isTrue);
    },
  );
  Future<SharedPreferences> pumpWelcome(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(402, 874);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final prefs = await migrate({});
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

  Future<void> tapWelcome(WidgetTester tester, String label) async {
    final target = find.text(label);
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    expect(target.hitTestable(), findsOneWidget);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  final ios = TargetPlatformVariant.only(TargetPlatform.iOS);

  testWidgets('first-run Local bypasses the server screen', variant: ios, (
    tester,
  ) async {
    final prefs = await pumpWelcome(tester);
    expect(find.text('Local'), findsOneWidget);
    expect(find.text('Server'), findsOneWidget);
    await tapWelcome(tester, 'Local');
    await tapWelcome(tester, 'Start reading');

    // Local lands on All set too, then opens the library.
    expect(find.text("You're all set"), findsOneWidget);
    expect(find.text('Connect your server'), findsNothing);
    await tapWelcome(tester, 'Back');
    expect(find.text('How would you like to read?'), findsOneWidget);
    await tapWelcome(tester, 'Start reading');
    await tapWelcome(tester, 'Start reading');

    expect(find.text('Local destination'), findsOneWidget);
    expect(find.text('Connect your server'), findsNothing);
    expect(readCollectionMode(prefs), CollectionMode.local);
    expect(prefs.getBool('onboardingComplete'), isFalse);
  });

  testWidgets('first-run Server opens the address form', variant: ios, (
    tester,
  ) async {
    final prefs = await pumpWelcome(tester);
    await tapWelcome(tester, 'Server');
    await tapWelcome(tester, 'Next');

    expect(find.text('Connect your server'), findsOneWidget);
    final address = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == 'Server URL',
    );
    expect(address, findsOneWidget);
    expect(readCollectionMode(prefs), CollectionMode.server);
    expect(prefs.getBool('onboardingComplete'), isFalse);

    await tester.enterText(address, '192.0.2.42:4567');
    await tester.pumpAndSettle();
    await tapWelcome(tester, 'Back');
    expect(find.text('How would you like to read?'), findsOneWidget);
    await tapWelcome(tester, 'Next');
    expect(
      tester.widget<TextField>(address).controller?.text,
      '192.0.2.42:4567',
    );
  });
}
