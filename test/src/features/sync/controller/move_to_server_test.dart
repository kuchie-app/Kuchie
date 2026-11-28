import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuchie/src/features/local_collection/data/local_catalog.dart';
import 'package:kuchie/src/features/sync/controller/move_to_server.dart';
import 'package:kuchie/src/features/sync/data/sync_journal.dart';
import 'package:kuchie/src/features/sync/domain/sync_change.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory workspace;
  late LocalCatalog catalog;
  late SyncJournal journal;

  Future<String> save(String seriesId, int pages) async {
    await catalog.setInLibrary(
      seriesId: seriesId,
      title: seriesId,
      inLibrary: true,
    );
    final archive = Archive();
    for (var i = 0; i < pages; i++) {
      archive.addFile(ArchiveFile.bytes('$i.jpg', List.filled(100, i)));
    }
    final file = await File(
      p.join(
        workspace.path,
        '$seriesId-${DateTime.now().microsecondsSinceEpoch}.cbz',
      ),
    ).writeAsBytes(ZipEncoder().encode(archive));
    return (await catalog.importArchive(
      file,
      seriesId: seriesId,
    )).chapters.last.id;
  }

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('kuchie-move');
    catalog = LocalCatalog(Directory(p.join(workspace.path, 'catalog')));
    journal = SyncJournal(catalog);
  });

  tearDown(() async {
    await catalog.close();
    await workspace.delete(recursive: true);
  });

  test(
    'only chapters of series on the server move; the rest are counted',
    () async {
      final onServer = await save('linked', 3);
      await save('import', 2);
      await journal.putLink(
        'suwayomi',
        const SyncLink(
          kind: SyncLinkKind.series,
          localKey: 'linked',
          remoteId: '1',
        ),
      );
      final plan = await planMoveToServer(catalog);
      expect(plan.chapters, [(seriesId: 'linked', chapterId: onServer)]);
      expect(plan.excluded, 1);
      expect(plan.bytes, 300);
    },
  );

  test('a chapter already moving is not planned again', () async {
    final chapter = await save('linked', 1);
    await journal.putLink(
      'suwayomi',
      const SyncLink(
        kind: SyncLinkKind.series,
        localKey: 'linked',
        remoteId: '1',
      ),
    );
    await journal.putTransfer(
      SyncTransfer(
        seriesId: 'linked',
        chapterId: chapter,
        keepLocal: false,
        state: SyncTransferState.requested,
        updatedAt: DateTime.utc(2026),
      ),
    );
    expect((await planMoveToServer(catalog)).isEmpty, isTrue);
  });
}
