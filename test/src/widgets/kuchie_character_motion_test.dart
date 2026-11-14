import 'package:flutter_test/flutter_test.dart';
import 'package:kuchie/src/widgets/kuchie_character_motion.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('Reduce Motion swaps animation for its matching still', (
    tester,
  ) async {
    Future<void> show({required bool reduceMotion, bool visible = true}) =>
        tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(disableAnimations: reduceMotion),
            child: TickerMode(
              enabled: visible,
              child: const Center(
                child: KuchieCharacterMotion(
                  phase: KuchieCharacterPhase.loading,
                ),
              ),
            ),
          ),
        );

    String imagePath() =>
        ((tester.widget<Image>(find.byType(Image)).image as ResizeImage)
                    .imageProvider
                as ExactAssetImage)
            .assetName;

    await show(reduceMotion: false);
    expect(imagePath(), endsWith('loading.webp'));
    await show(reduceMotion: true);
    expect(imagePath(), endsWith('loading.png'));
    await show(reduceMotion: false, visible: false);
    expect(imagePath(), endsWith('loading.png'));
    await show(reduceMotion: false);
    expect(imagePath(), endsWith('loading.webp'));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Inline poses decode at their displayed size', (tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(devicePixelRatio: 3),
        child: Center(
          child: KuchieCharacterMotion(
            phase: KuchieCharacterPhase.error,
            width: 64,
            play: false,
          ),
        ),
      ),
    );
    final image = tester.widget<Image>(find.byType(Image));
    final resized = image.image as ResizeImage;
    expect(resized.width, 192);
    expect(
      (resized.imageProvider as ExactAssetImage).assetName,
      endsWith('error.png'),
    );
  });
}
