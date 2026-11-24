import 'package:flutter_test/flutter_test.dart';
import 'package:kuchie/src/features/manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import 'package:kuchie/src/features/manga_book/presentation/manga_details/widgets/chapter_check_status.dart';
import 'package:kuchie/src/l10n/generated/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  Future<void> pump(WidgetTester tester, ChapterCheck? check) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: ChapterCheckStatus(check: check)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('says what the check found', (tester) async {
    await pump(tester, (state: ChapterCheckState.checking, count: 0));
    expect(find.text('Refreshing'), findsOneWidget);

    await pump(tester, (state: ChapterCheckState.upToDate, count: 0));
    expect(find.text('No new chapters found'), findsOneWidget);

    await pump(tester, (state: ChapterCheckState.newChapters, count: 53));
    expect(find.text('53 new chapters'), findsOneWidget);

    await pump(tester, (state: ChapterCheckState.failed, count: 0));
    expect(find.text("Couldn't check for new chapters"), findsOneWidget);

    await pump(tester, null);
    expect(find.byType(Text), findsNothing);
  });
}
