import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kuchie/src/features/local_collection/data/local_catalog.dart';
import 'package:kuchie/src/features/sync/data/suwayomi/suwayomi_identity.dart';
import 'package:kuchie/src/features/sync/data/sync_journal.dart';
import 'package:kuchie/src/features/sync/domain/sync_records.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory workspace;
  late LocalCatalog catalog;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('kuchie-sync-write');
    catalog = LocalCatalog(Directory(p.join(workspace.path, 'catalog')))
      ..journalEnabled = true;
  });

  tearDown(() async {
    await catalog.close();
    await workspace.delete(recursive: true);
  });

  test(
    'what a cycle pulls lands in one write and stays out of the outbox',
    () async {
      final readAt = DateTime.utc(2026, 10, 1, 8);
      await catalog.applySync(
        LocalSyncWrite(
          series: const [
            LocalSyncSeriesWrite(id: 's', title: 'S', inLibrary: true),
          ],
          categories: const {'Action'},
          memberships: const {
            's': {'Action'},
          },
          chapters: [
            LocalSyncChapterWrite(
              seriesId: 's',
              seriesTitle: 'S',
              chapterId: 'c1',
              chapterTitle: 'One',
              state: ChapterState(read: true, page: 3, readAt: readAt),
            ),
            const LocalSyncChapterWrite(
              seriesId: 's',
              seriesTitle: 'S',
              chapterId: 'c2',
              chapterTitle: 'Two',
              state: ChapterState(bookmarked: true),
            ),
          ],
        ),
      );
      expect(await SyncJournal(catalog).pending(), isEmpty);
      final series = (await catalog.syncSeries()).single;
      expect(series.inLibrary, isTrue);
      expect(series.categories, ['Action']);
      expect(await catalog.syncChapterStates('s'), {
        'c1': ChapterState(read: true, page: 3, readAt: readAt),
        'c2': const ChapterState(bookmarked: true),
      });
      expect((await catalog.remoteHistory()).single.chapterId, 'c1');
    },
  );

  test('taking a series off the library keeps its row and reading', () async {
    await catalog.setInLibrary(seriesId: 's', title: 'S', inLibrary: true);
    await catalog.applySync(
      const LocalSyncWrite(
        series: [LocalSyncSeriesWrite(id: 's', title: 'S', inLibrary: false)],
      ),
    );
    expect((await catalog.syncSeries()).single.inLibrary, isFalse);
  });

  test('a server URL gives the same id as a Mihon locator', () {
    // SHA-256 of "/manga/1", as LocalSources derives a runtime manga id.
    expect(
      kuchieLocatorId('/manga/1'),
      '44d528c67672573eccb299c9a3d8e1fbc534f3c6f07db8a43541317bde668b25',
    );
  });
}
