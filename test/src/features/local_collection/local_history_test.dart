import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kuchie/src/features/local_collection/data/local_catalog.dart';
import 'package:kuchie/src/features/local_collection/data/local_history.dart';

void main() {
  final day = DateTime(2026, 11, 15);
  const source = LocalSeriesSource(
    sourceId: 'shinigami',
    mangaId: 'demon',
    locator: '/demon',
  );

  LocalRemoteRead online(String chapterId, DateTime at, {int progress = 0}) =>
      LocalRemoteRead(
        seriesId: 'demon',
        seriesTitle: 'Crazy Demon',
        source: source,
        chapterId: chapterId,
        chapterTitle: 'Chapter $chapterId',
        progress: progress,
        lastReadAt: at,
      );

  test('chapters read online appear without a saved series', () {
    final history = mergeLocalHistory(const [], [
      online('165', day, progress: 2),
    ]);
    final entry = history.single;
    expect(entry.saved, isFalse);
    expect(entry.book.title, 'Crazy Demon');
    expect(entry.book.source?.locator, '/demon');
    expect(entry.chapter.title, 'Chapter 165');
    expect(entry.chapter.progress, 2);
    expect(entry.chapter.lastReadAt, day);
  });

  test('a saved chapter opens from storage with the newer read time', () {
    final page = File('page-1.png');
    final series = LocalSeries(
      id: 'demon',
      title: 'Crazy Demon',
      source: source,
      chapters: [
        LocalChapter(
          id: '166',
          title: 'Chapter 166',
          pages: [page],
          progress: 4,
          lastReadAt: day,
        ),
        LocalChapter(id: '167', title: 'Chapter 167', pages: [page]),
      ],
    );
    final later = day.add(const Duration(hours: 1));
    final history = mergeLocalHistory(
      [series],
      [
        online('166', later),
        online('167', day.subtract(const Duration(hours: 1))),
        online('165', day.add(const Duration(minutes: 1))),
      ],
    );
    expect(
      [for (final entry in history) (entry.chapter.id, entry.saved)],
      [('166', true), ('165', false), ('167', true)],
    );
    expect(history.first.chapter.pages, [page]);
    expect(history.first.chapter.progress, 4);
    expect(history.first.chapter.lastReadAt, later);
  });
}
