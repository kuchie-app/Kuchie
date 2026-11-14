import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuchie/src/features/app_icon/presentation/app_icon_settings_tile.dart';
import 'package:kuchie/src/l10n/generated/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('icon selection follows UIKit and shows a rejected change', (
    tester,
  ) async {
    const channel = MethodChannel('kuchie/app_icon');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final requested = <String?>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'state') {
        return {'available': true, 'current': 'AppIcon-PanelKiri'};
      }
      expect(call.method, 'setAlternateIcon');
      final name = call.arguments as String?;
      requested.add(name);
      if (name == 'AppIcon-CapKertas') {
        throw PlatformException(code: 'icon_change_failed');
      }
      return {'available': true, 'current': name};
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: AppIconSettingsTile()),
      ),
    );
    await tester.tap(find.text('App icon'));
    await tester.pumpAndSettle();

    ListTile tile(String name) => tester.widget<ListTile>(
      find.ancestor(of: find.text(name), matching: find.byType(ListTile)),
    );
    expect(tile('Panel Kiri').selected, isTrue);
    expect(tile('Open Frame').selected, isFalse);

    await tester.tap(find.text('Cap Kertas'));
    await tester.pumpAndSettle();
    expect(tile('Panel Kiri').selected, isTrue);
    expect(
      find.text('iOS could not change the app icon. Try again.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Open Frame'));
    await tester.pumpAndSettle();
    expect(tile('Open Frame').selected, isTrue);

    await tester.tap(find.text('Kiri'));
    await tester.pumpAndSettle();
    expect(tile('Kiri').selected, isTrue);
    expect(requested, ['AppIcon-CapKertas', 'AppIcon-OpenFrame', null]);
    expect(tester.takeException(), isNull);
  });
}
