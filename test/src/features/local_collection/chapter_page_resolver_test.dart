import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuchie/src/features/local_collection/data/chapter_page_resolver.dart';
import 'package:kuchie/src/features/local_collection/data/local_sources.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/local_collection_fakes.dart';

class _FakeChapter extends Fake implements LocalSourceChapter {}

class _Server implements ServerChapterPages {
  _Server(this.answer);

  Future<List<LocalSourcePage>?> Function() answer;
  var calls = 0;

  @override
  Future<List<LocalSourcePage>?> pages(String seriesId, String chapterId) {
    calls++;
    return answer();
  }
}

final _serverPage = (url: Uri.parse('http://server/p/0'), headers: {'a': 'b'});
final _sourcePage = (
  url: Uri.parse('https://source/p/0'),
  headers: <String, String>{},
);

void main() {
  late MockLocalSources sources;
  final chapter = _FakeChapter();

  setUpAll(() => registerFallbackValue(_FakeChapter()));

  setUp(() {
    sources = MockLocalSources();
    when(
      () => sources.chapterPages(any(), any()),
    ).thenAnswer((_) async => [_sourcePage]);
  });

  Future<List<LocalSourcePage>> resolve(
    ServerChapterPages? server, {
    String? extensionId = 'p:1',
  }) => ChapterPageResolver(sources: sources, server: server).pages(
    seriesId: 's',
    chapterId: 'c',
    extensionId: extensionId,
    chapter: extensionId == null ? null : chapter,
  );

  test('the server comes before the source', () async {
    expect(await resolve(_Server(() async => [_serverPage])), [_serverPage]);
    verifyNever(() => sources.chapterPages(any(), any()));
  });

  test('without sync, a link or an answer, the source reads it', () async {
    expect(await resolve(null), [_sourcePage]);
    expect(await resolve(_Server(() async => null)), [_sourcePage]);
    expect(
      await resolve(_Server(() async => throw const SocketException('x'))),
      [_sourcePage],
    );
  });

  test('a slow server gives way to the source after 3 seconds', () {
    fakeAsync((async) {
      final server = _Server(() => Completer<List<LocalSourcePage>?>().future);
      List<LocalSourcePage>? pages;
      unawaited(resolve(server).then((value) => pages = value));
      async.elapse(const Duration(milliseconds: 2900));
      expect(pages, isNull);
      async.elapse(const Duration(milliseconds: 200));
      expect(pages, [_sourcePage]);
    });
  });

  test('no server and no extension here: it needs the server', () {
    expect(
      resolve(_Server(() async => null), extensionId: null),
      throwsA(isA<ChapterNeedsServer>()),
    );
  });

  test('no internet at all says so', () {
    when(
      () => sources.chapterPages(any(), any()),
    ).thenThrow(const SocketException('offline'));
    expect(resolve(null), throwsA(isA<ChapterOffline>()));
  });
}
