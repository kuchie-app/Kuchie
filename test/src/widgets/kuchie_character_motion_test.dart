import 'package:flutter_test/flutter_test.dart';
import 'package:kuchie/src/widgets/kuchie_character_motion.dart';
import 'package:kuchie/src/widgets/kuchie_face.dart';
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

  testWidgets('quiet states show Kuchie as a text face, not artwork', (
    tester,
  ) async {
    for (final (phase, face) in [
      (KuchieCharacterPhase.empty, '( ` ` )>'),
      (KuchieCharacterPhase.noResults, '( ` ` )>?'),
      (KuchieCharacterPhase.downloadPaused, '( - - )>'),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(child: KuchieCharacterMotion(phase: phase, width: 68)),
        ),
      );
      expect(find.byType(Image), findsNothing);
      final shown = tester.widget<KuchieFace>(find.byType(KuchieFace));
      expect(shown.face, face);
      expect(
        tester.getSize(find.byType(KuchieFace)).width,
        lessThanOrEqualTo(68),
        reason: 'it shrinks to fit small spots such as a banner',
      );
    }
  });

  testWidgets('the scarf takes the accent colour', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Center(child: KuchieFace(KuchieFace.empty))),
    );
    final text = tester.widget<Text>(find.byType(Text));
    final spans = (text.textSpan! as TextSpan).children!.cast<TextSpan>();
    expect(spans.map((s) => s.text).join(), KuchieFace.empty);
    expect(spans.last.text, '>');
    final context = tester.element(find.byType(KuchieFace));
    expect(spans.last.style?.color, Theme.of(context).colorScheme.primary);
  });
}
