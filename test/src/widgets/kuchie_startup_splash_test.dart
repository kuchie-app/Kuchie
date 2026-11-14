import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuchie/src/widgets/kuchie_startup_splash.dart';

void main() {
  final destination = Semantics(
    label: 'Startup destination',
    textDirection: TextDirection.ltr,
    child: const SizedBox.expand(),
  );

  Future<void> show(
    WidgetTester tester, {
    required bool ready,
    bool reduceMotion = false,
  }) => tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: KuchieStartupSplash(
        ready: ready,
        child: ready ? destination : null,
      ),
    ),
  );

  String imageAsset(Image image) => (image.image as ExactAssetImage).assetName;

  testWidgets('uses a still while loading with Reduce Motion', (tester) async {
    final semantics = tester.ensureSemantics();
    await show(tester, ready: false, reduceMotion: true);
    expect(tester.widgetList<Image>(find.byType(Image)).map(imageAsset), [
      'assets/kuchie/splash/kiri-loading.png',
    ]);
    expect(find.bySemanticsLabel('Loading Kuchie'), findsOneWidget);

    await show(tester, ready: true, reduceMotion: true);
    expect(find.byType(Image), findsNothing);
    expect(find.bySemanticsLabel('Startup destination'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('does not replay the greeting when it mounts already ready', (
    tester,
  ) async {
    await show(tester, ready: true);
    expect(find.byType(Image), findsNothing);
    expect(find.byWidget(destination), findsOneWidget);
  });

  testWidgets('starts the reading loop before the greeting', (tester) async {
    await show(tester, ready: false);
    expect(
      tester.widgetList<Image>(find.byType(Image)).map(imageAsset),
      contains('assets/kuchie/splash/kiri-loading.webp'),
    );
    expect(find.byWidget(destination), findsNothing);

    await show(tester, ready: true);
    expect(
      tester.widgetList<Image>(find.byType(Image)).map(imageAsset),
      contains('assets/kuchie/splash/kiri-ready.webp'),
    );
    await show(tester, ready: true, reduceMotion: true);
    expect(find.byType(Image), findsNothing);
    expect(find.byWidget(destination), findsOneWidget);
  });
}
