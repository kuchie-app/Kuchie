import 'package:flutter_test/flutter_test.dart';
import 'package:kuchie/src/features/history/data/graphql/__generated__/query.graphql.dart';
import 'package:kuchie/src/features/history/domain/history_item.dart';
import 'package:kuchie/src/features/history/presentation/widgets/history_item_tile.dart';

HistoryItemDto _item({required int lastPageRead, bool isRead = false}) =>
    Fragment$HistoryChapterDto(
      id: 1,
      chapterNumber: 1,
      fetchedAt: '0',
      mangaId: 7,
      name: 'Chapter 1',
      pageCount: 18,
      sourceOrder: 1,
      uploadDate: '0',
      url: '/c/1',
      meta: const [],
      manga: Fragment$HistoryChapterDto$manga(
        id: 7,
        title: 'Series',
        meta: const [],
        user: Fragment$HistoryChapterDto$manga$user(
          inLibrary: true,
          unreadCount: 1,
        ),
      ),
      user: Fragment$HistoryChapterDto$user(
        isBookmarked: false,
        isDownloaded: false,
        isRead: isRead,
        lastPageRead: lastPageRead,
        lastReadAt: '1700000000',
      ),
    );

void main() {
  test('history counts the resume page from 1, like the reader', () {
    // The server stores page indices from 0: index 1 is the second page.
    expect(historyResumePage(_item(lastPageRead: 1)), 2);
    expect(historyResumePage(_item(lastPageRead: 16)), 17);
    expect(isHistoryChapterCompleted(_item(lastPageRead: 16)), isFalse);
    expect(isHistoryChapterCompleted(_item(lastPageRead: 17)), isTrue);
  });
}
