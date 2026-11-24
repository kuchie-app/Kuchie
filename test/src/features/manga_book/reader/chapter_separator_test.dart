import 'package:flutter_test/flutter_test.dart';
import 'package:kuchie/src/features/manga_book/presentation/reader/widgets/reader_mode/infinity_continuous/infinity_continuous_feedback.dart';
import 'package:kuchie/src/l10n/generated/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget separator) => tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: separator),
    ),
  );

  testWidgets('between chapters it names the finished and the current one', (
    tester,
  ) async {
    await pump(
      tester,
      const InfinityContinuousChapterSeparator(
        chapterName: 'Chapter 931',
        nextChapterName: 'Chapter 932',
        isChapterStart: false,
      ),
    );
    expect(find.text('Finished:'), findsOneWidget);
    expect(find.text('Chapter 931'), findsOneWidget);
    expect(find.text('Current:'), findsOneWidget);
    expect(find.text('Chapter 932'), findsOneWidget);
    expect(find.byType(Icon), findsNothing, reason: 'text only, no icons');
  });

  testWidgets('at the start it names the chapter beginning', (tester) async {
    await pump(
      tester,
      const InfinityContinuousChapterSeparator(
        chapterName: 'Chapter 931',
        isChapterStart: true,
      ),
    );
    expect(find.text('Finished:'), findsNothing);
    expect(find.text('Current:'), findsOneWidget);
    expect(find.text('Chapter 931'), findsOneWidget);
  });

  testWidgets('at the end it says nothing follows', (tester) async {
    await pump(
      tester,
      const InfinityContinuousChapterSeparator(
        chapterName: 'Chapter 936',
        isChapterStart: false,
        note: "There's no next chapter",
      ),
    );
    expect(find.text('Finished:'), findsOneWidget);
    expect(find.text('Chapter 936'), findsOneWidget);
    expect(find.text('Current:'), findsNothing);
    expect(find.text("There's no next chapter"), findsOneWidget);
  });
}
