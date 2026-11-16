// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'local_catalog.dart';

/// [saved] entries open from device storage; the rest reopen from their source.
typedef LocalHistoryEntry = ({
  LocalSeries book,
  LocalChapter chapter,
  bool saved,
});

/// Merges saved chapters with chapters read online, newest first.
///
/// A chapter that was saved after being read online keeps one entry, opened
/// from storage, with whichever read time is newer.
List<LocalHistoryEntry> mergeLocalHistory(
  List<LocalSeries> books,
  List<LocalRemoteRead> remoteReads,
) {
  String key(String seriesId, String chapterId) => '$seriesId\n$chapterId';
  final booksById = {for (final book in books) book.id: book};
  final entries = <String, LocalHistoryEntry>{
    for (final book in books)
      for (final chapter in book.chapters)
        if (chapter.lastReadAt != null)
          key(book.id, chapter.id): (book: book, chapter: chapter, saved: true),
  };
  for (final read in remoteReads) {
    final id = key(read.seriesId, read.chapterId);
    final book = booksById[read.seriesId];
    LocalChapter? saved;
    for (final chapter in book?.chapters ?? const <LocalChapter>[]) {
      if (chapter.id == read.chapterId) saved = chapter;
    }
    if (book != null && saved != null) {
      final savedAt = saved.lastReadAt;
      if (savedAt == null || read.lastReadAt.isAfter(savedAt)) {
        entries[id] = (
          book: book,
          chapter: LocalChapter(
            id: saved.id,
            title: saved.title,
            pages: saved.pages,
            progress: saved.progress,
            bookmarked: saved.bookmarked,
            lastReadAt: read.lastReadAt,
          ),
          saved: true,
        );
      }
      continue;
    }
    entries[id] = (
      book: book != null && book.source != null
          ? book
          : LocalSeries(
              id: read.seriesId,
              title: book?.title ?? read.seriesTitle,
              chapters: book?.chapters ?? const [],
              categories: book?.categories ?? const [],
              inLibrary: book?.inLibrary ?? false,
              source: book?.source ?? read.source,
            ),
      chapter: LocalChapter(
        id: read.chapterId,
        title: read.chapterTitle,
        pages: const [],
        progress: read.progress,
        lastReadAt: read.lastReadAt,
      ),
      saved: false,
    );
  }
  return entries.values.toList()
    ..sort((a, b) => b.chapter.lastReadAt!.compareTo(a.chapter.lastReadAt!));
}
