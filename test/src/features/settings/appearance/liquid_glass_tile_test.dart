import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kuchie/src/constants/db_keys.dart';
import 'package:kuchie/src/features/settings/presentation/appearance/widgets/liquid_glass/liquid_glass_tile.dart';
import 'package:kuchie/src/global_providers/global_providers.dart';
import 'package:kuchie/src/l10n/generated/app_localizations.dart';
import 'package:kuchie/src/widgets/ios/apple_glass_capability.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('classifies devices by iOS support and memory', () {
    AppleGlassCapability classify(bool os, int? memory) =>
        classifyAppleGlass(osSupported: os, memoryBytes: memory);
    const gib = 1024 * 1024 * 1024;

    expect(classify(false, 8 * gib), AppleGlassCapability.unsupported);
    // iPhone 11–13 report under 4 GiB.
    expect(classify(true, (3.7 * gib).round()), AppleGlassCapability.limited);
    // 6 GB devices report about 5.6 GiB.
    expect(classify(true, (5.6 * gib).round()), AppleGlassCapability.capable);
    expect(classify(true, 8 * gib), AppleGlassCapability.capable);
    expect(classify(true, null), AppleGlassCapability.capable);
  });

  test('glass is on by default only where the device is capable', () {
    bool resolve(AppleGlassCapability c, bool? saved) =>
        effectiveAppleGlass(capability: c, saved: saved);

    expect(resolve(AppleGlassCapability.capable, null), isTrue);
    expect(resolve(AppleGlassCapability.capable, false), isFalse);
    expect(resolve(AppleGlassCapability.limited, null), isFalse);
    // A saved "on" restored from a stronger device cannot force it on.
    expect(resolve(AppleGlassCapability.limited, true), isFalse);
    expect(resolve(AppleGlassCapability.unsupported, true), isFalse);
  });

  Future<SharedPreferences> pumpTile(
    WidgetTester tester,
    AppleGlassCapability capability,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AppleGlassScope(
            available: capability == AppleGlassCapability.capable,
            capability: capability,
            child: const Scaffold(body: LiquidGlassTile()),
          ),
        ),
      ),
    );
    return prefs;
  }

  testWidgets('a capable device starts on and can turn glass off', (
    tester,
  ) async {
    final prefs = await pumpTile(tester, AppleGlassCapability.capable);
    expect(find.text('Glass tab bar, toolbars and controls'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(prefs.getBool(DBKeys.liquidGlass.name), isFalse);
  });

  testWidgets('a limited device is locked off and says why', (tester) async {
    final prefs = await pumpTile(tester, AppleGlassCapability.limited);
    expect(find.text('Off to keep this device smooth'), findsOneWidget);
    final toggle = tester.widget<Switch>(find.byType(Switch));
    expect(toggle.value, isFalse);
    expect(toggle.onChanged, isNull);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(prefs.getBool(DBKeys.liquidGlass.name), isNull);
  });
}
