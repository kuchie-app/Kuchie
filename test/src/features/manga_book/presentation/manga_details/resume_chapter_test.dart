// Resume follows the chapter read most recently, not the highest one read.

import 'package:flutter_test/flutter_test.dart';
import 'package:kuchie/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:kuchie/src/features/manga_book/domain/chapter/graphql/__generated__/fragment.graphql.dart';
import 'package:kuchie/src/features/manga_book/presentation/manga_details/manga_details_screen.dart';

ChapterDto _chapter(
  int order, {
  bool read = false,
  int page = 0,
  int readAt = 0,
}) => Fragment$ChapterDto(
  chapterNumber: order.toDouble(),
  fetchedAt: '0',
  id: order,
  mangaId: 1,
  name: 'Chapter $order',
  pageCount: 20,
  sourceOrder: order,
  uploadDate: '0',
  url: '/chapter/$order',
  meta: const [],
  user: Fragment$ChapterDto$user(
    isBookmarked: false,
    isDownloaded: false,
    isRead: read,
    lastPageRead: page,
    lastReadAt: '$readAt',
  ),
);

void main() {
  test('reading chapter 7 after chapter 10 resumes chapter 7', () {
    final chapters = [
      for (var i = 1; i <= 12; i++)
        switch (i) {
          10 => _chapter(10, page: 4, readAt: 1000),
          7 => _chapter(7, page: 6, readAt: 2000),
          _ => _chapter(i),
        },
    ];
    expect(resumeChapter(chapters)?.id, 7);
  });

  test('a finished latest chapter resumes the next unread after it', () {
    final chapters = [
      _chapter(5, read: true, readAt: 500),
      _chapter(6, read: true, readAt: 3000),
      _chapter(7, read: true),
      _chapter(8),
      _chapter(9),
    ];
    expect(resumeChapter(chapters)?.id, 8);
  });

  test('nothing read yet falls back to the first unread chapter', () {
    final first = _chapter(1);
    expect(resumeChapter([first, _chapter(2)], fallback: first)?.id, 1);
  });
}
