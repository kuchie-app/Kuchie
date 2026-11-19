// The views shared by the server and Local collections render from plain
// data, so both collections show the same rows.

import 'package:flutter_test/flutter_test.dart';
import 'package:kuchie/src/features/browse_center/presentation/source/widgets/source_list_tile.dart';
import 'package:kuchie/src/features/history/presentation/widgets/history_item_tile.dart';
import 'package:kuchie/src/features/manga_book/presentation/manga_details/widgets/chapter_grid_tile.dart';
import 'package:kuchie/src/features/manga_book/presentation/manga_details/widgets/chapter_list_tile.dart';
import 'package:kuchie/src/l10n/generated/app_localizations.dart';
import 'package:kuchie/src/widgets/manga_cover/list/manga_cover_list_tile.dart';
import 'package:material_ui/material_ui.dart';

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  ),
);

void main() {
  testWidgets('chapter row joins date, resume page, scanlator and extra', (
    tester,
  ) async {
    var taps = 0;
    await _pump(
      tester,
      ChapterRowView(
        title: 'Chapter 7',
        date: '2d',
        scanlator: 'Team',
        extra: '3 / 9',
        lastPageRead: 3,
        isRead: false,
        isBookmarked: true,
        isSelected: false,
        onTap: () => taps++,
      ),
    );
    expect(find.text('Chapter 7'), findsOneWidget);
    expect(find.textContaining('2d • '), findsOneWidget);
    expect(find.textContaining(' • Team • 3 / 9'), findsOneWidget);
    await tester.tap(find.text('Chapter 7'));
    expect(taps, 1);
  });

  testWidgets('a read chapter row hides the resume page', (tester) async {
    await _pump(
      tester,
      ChapterRowView(
        title: 'Chapter 8',
        date: '1d',
        lastPageRead: 5,
        isRead: true,
        isBookmarked: false,
        isSelected: false,
        onTap: () {},
      ),
    );
    expect(find.text('1d', findRichText: true), findsOneWidget);
  });

  test('grid labels use the chapter number, or the position without one', () {
    expect(ChapterGridTileView.numberLabel(12, 3), '12');
    expect(ChapterGridTileView.numberLabel(12.5, 3), '12.5');
    expect(ChapterGridTileView.numberLabel(null, 3), '#3');
    expect(ChapterGridTileView.numberLabel(-1, 4), '#4');
  });

  testWidgets('source row offers Latest only when the source has it', (
    tester,
  ) async {
    Widget row({VoidCallback? latest}) => SourceListTileView(
      name: 'Source',
      language: 'English',
      icon: const SizedBox.square(dimension: 48),
      onOpen: () {},
      onOpenLatest: latest,
      pin: SourcePinButton(pinned: false, onPressed: () {}),
    );
    await _pump(tester, row());
    expect(find.text('Latest'), findsNothing);
    await _pump(tester, row(latest: () {}));
    expect(find.text('Latest'), findsOneWidget);
  });

  testWidgets('history row: reading time, day, and a remove button', (
    tester,
  ) async {
    var opened = 0;
    var removed = 0;
    await _pump(
      tester,
      HistoryRowView(
        cover: (size) => SizedBox.fromSize(size: size),
        seriesTitle: 'Series',
        chapterTitle: 'Chapter 2',
        readAt: DateTime.now(),
        readingTime: const Duration(minutes: 17),
        onTap: () => opened++,
        onRemove: () => removed++,
      ),
    );
    expect(find.text('Today'), findsOneWidget);
    expect(find.textContaining('17'), findsOneWidget);
    await tester.tap(find.text('Series'));
    expect(opened, 1);
    await tester.tap(find.byTooltip('Delete'));
    expect(removed, 1);
  });

  testWidgets('cover list tile renders on-device covers without a server '
      'manga', (tester) async {
    await _pump(
      tester,
      MangaCoverListTile(
        titleOverride: 'Local title',
        showBadges: false,
        onPressed: () {},
      ),
    );
    expect(find.text('Local title'), findsOneWidget);
    expect(find.byIcon(Icons.book_outlined), findsOneWidget);
  });
}
