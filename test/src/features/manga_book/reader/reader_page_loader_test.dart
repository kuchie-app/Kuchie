import 'package:flutter_test/flutter_test.dart';
import 'package:kuchie/src/features/manga_book/presentation/reader/widgets/reader_page_loader.dart';
import 'package:kuchie/src/l10n/generated/app_localizations.dart';
import 'package:kuchie/src/widgets/kuchie_brush_loader.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  Widget host(Widget child, {bool reduceMotion = false}) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Scaffold(body: Center(child: child)),
    ),
  );

  testWidgets('names the page and offers a retry once it times out', (
    tester,
  ) async {
    var retries = 0;
    await tester.pumpWidget(
      host(ReaderPageLoader(pageNumber: 4, onRetry: () => retries++)),
    );
    expect(find.text('Page 4'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);

    await tester.pump(kReaderPageTimeout - const Duration(seconds: 1));
    expect(find.text('Retry'), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Taking longer than usual'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(retries, 1);
    expect(find.text('Retry'), findsNothing, reason: 'the wait starts over');
  });

  testWidgets('data still arriving holds off the timeout', (tester) async {
    Widget at(double progress) => host(
      ReaderPageLoader(progress: progress, pageNumber: 1, onRetry: () {}),
    );
    await tester.pumpWidget(at(.1));
    await tester.pump(const Duration(seconds: 15));
    await tester.pumpWidget(at(.4));
    await tester.pump(const Duration(seconds: 15));
    expect(find.text('Retry'), findsNothing);

    await tester.pump(const Duration(seconds: 6));
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('keeps moving while it waits, even when progress stalls', (
    tester,
  ) async {
    await tester.pumpWidget(host(const KuchieBrushLoader(progress: .3)));
    await tester.pump(kBrushLoaderStall + const Duration(milliseconds: 100));
    expect(tester.hasRunningAnimations, isTrue);

    await tester.pumpWidget(host(const KuchieBrushLoader()));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.hasRunningAnimations, isTrue);
  });

  testWidgets('holds still with reduced motion', (tester) async {
    await tester.pumpWidget(
      host(const KuchieBrushLoader(), reduceMotion: true),
    );
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
  });
}
