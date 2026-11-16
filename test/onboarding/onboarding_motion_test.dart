import 'package:flutter_test/flutter_test.dart';
import 'package:kuchie/src/features/onboarding/presentation/onboarding_motion.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  const local = MangaChoice(
    label: 'Local',
    caption: 'Read on this phone.',
    icon: Icons.phone_iphone_rounded,
    art: 'assets/kuchie/splash/kiri-ready.png',
  );
  const server = MangaChoice(
    label: 'Server',
    caption: 'Read from your server.',
    icon: Icons.cloud_outlined,
    art: 'assets/kuchie/character/loading.png',
  );

  Future<void> pumpFirstRun(
    WidgetTester tester, {
    required bool reduceMotion,
    ValueChanged<int>? onSelected,
  }) async {
    tester.view
      ..physicalSize = const Size(402, 874)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(402, 874),
            disableAnimations: reduceMotion,
          ),
          child: Scaffold(
            body: OnboardingBackdrop(
              child: ListView(
                children: [
                  MangaModeChooser(
                    first: local,
                    second: server,
                    selected: null,
                    onSelected: onSelected ?? (_) {},
                  ),
                  const FlyingKuchie(
                    title: Text("You're all set"),
                    subtitle: Text('Ready'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('Reduce Motion shows the finished first run with no frames', (
    tester,
  ) async {
    await pumpFirstRun(tester, reduceMotion: true);
    await tester.pump();

    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(find.text('Local').hitTestable(), findsOneWidget);
    expect(find.text('Server').hitTestable(), findsOneWidget);
    expect(find.text("You're all set"), findsOneWidget);
  });

  testWidgets('every first-run animation ends, so the screen goes idle', (
    tester,
  ) async {
    int? picked;
    await pumpFirstRun(
      tester,
      reduceMotion: false,
      onSelected: (index) => picked = index,
    );
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);

    // Taps land anywhere in a panel, not only on its speech bubble.
    await tester.tap(find.text('Read from your server.'));
    expect(picked, 1);
    await tester.tapAt(const Offset(40, 300));
    expect(picked, 1);
    await tester.tapAt(const Offset(320, 40));
    expect(picked, 0);
  });

  testWidgets('tapping Kiri in a panel chooses that panel', (tester) async {
    int? picked;
    await pumpFirstRun(
      tester,
      reduceMotion: true,
      onSelected: (index) => picked = index,
    );
    await tester.pump();

    Finder art(String asset) => find.byWidgetPredicate((w) {
      if (w is! Image) return false;
      final provider = w.image is ResizeImage
          ? (w.image as ResizeImage).imageProvider
          : w.image;
      return provider is AssetImage && provider.assetName == asset;
    }).first;

    await tester.tap(art(server.art));
    expect(picked, 1);
    await tester.tap(art(local.art));
    expect(picked, 0);
  });
}
