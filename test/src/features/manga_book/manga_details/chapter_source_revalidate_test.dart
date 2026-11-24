import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kuchie/src/constants/db_keys.dart';
import 'package:kuchie/src/features/auth/data/auth_credentials_store.dart';
import 'package:kuchie/src/features/manga_book/data/manga_book/manga_book_repository.dart';
import 'package:kuchie/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:kuchie/src/features/manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import 'package:kuchie/src/features/offline/data/offline_repository.dart';
import 'package:kuchie/src/global_providers/global_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chapter_test_helpers.dart';

class _SessionStore extends AuthCredentialsStore {
  @override
  Future<AuthCredentialsState> build() async => const AuthCredentialsState();
}

class _Repository extends MangaBookRepository {
  _Repository({this.scraped})
    : super(
        GraphQLClient(
          link: HttpLink('http://localhost:0'),
          cache: GraphQLCache(),
        ),
      );
  int sourceRequests = 0;

  /// What the source returns; null makes the scrape fail.
  final List<ChapterDto>? Function()? scraped;

  @override
  Future<List<ChapterDto>?> getStoredChapterList(int mangaId) async => [
    ch(id: 1, number: 1),
  ];

  @override
  Future<List<ChapterDto>?> getMangaAndChapterList(int mangaId) async {
    sourceRequests++;
    final scraped = this.scraped;
    if (scraped == null) return [ch(id: 1, number: 1), ch(id: 2, number: 2)];
    final chapters = scraped();
    if (chapters == null) throw StateError('source down');
    return chapters;
  }
}

Future<(ProviderContainer, _Repository)> _open(
  Map<String, Object> prefsValues, {
  List<ChapterDto>? Function()? scraped,
}) async {
  SharedPreferences.setMockInitialValues(prefsValues);
  final prefs = await SharedPreferences.getInstance();
  final repo = _Repository(scraped: scraped);
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      authCredentialsStoreProvider.overrideWith(_SessionStore.new),
      mangaBookRepositoryProvider.overrideWithValue(repo),
      offlineSyncProvider.overrideWithValue(null),
      offlineReadDatabaseProvider.overrideWithValue(null),
    ],
  );
  await container.read(authCredentialsStoreProvider.future);
  return (container, repo);
}

void main() {
  final provider = mangaChapterListProvider(mangaId: 1);
  List<int>? ids(ProviderContainer c) =>
      c.read(provider).value?.map((chapter) => chapter.id).toList();

  test(
    'opening a series shows stored chapters, then the source scrape',
    () async {
      final (container, repo) = await _open({});
      addTearDown(container.dispose);
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);

      final first = await container.read(provider.future);
      expect(first!.map((chapter) => chapter.id), [1]);

      await pumpEventQueue();
      expect(repo.sourceRequests, 1);
      expect(ids(container), [1, 2]);
    },
  );

  test('turning source refresh off keeps the stored chapters only', () async {
    final (container, repo) = await _open({
      DBKeys.refreshChaptersFromSource.name: false,
    });
    addTearDown(container.dispose);
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);

    await container.read(provider.future);
    await pumpEventQueue();
    expect(repo.sourceRequests, 0);
    expect(ids(container), [1]);
  });

  group('the line above the chapter list', () {
    final check = mangaChapterCheckProvider(mangaId: 1);

    Future<ChapterCheck?> checkAfterOpen(
      List<ChapterDto>? Function() scraped,
    ) async {
      final (container, _) = await _open({}, scraped: scraped);
      addTearDown(container.dispose);
      final states = <ChapterCheck?>[];
      final keepCheck = container.listen(
        check,
        (_, next) => states.add(next),
        fireImmediately: true,
      );
      addTearDown(keepCheck.close);
      final keepList = container.listen(provider, (_, _) {});
      addTearDown(keepList.close);
      await container.read(provider.future);
      await pumpEventQueue();
      expect(
        states.map((s) => s?.state),
        contains(ChapterCheckState.checking),
        reason: 'it says it is refreshing first',
      );
      return container.read(check);
    }

    test('counts chapters the source added', () async {
      final result = await checkAfterOpen(
        () => [
          ch(id: 1, number: 1),
          ch(id: 2, number: 2),
          ch(id: 3, number: 3),
        ],
      );
      expect(result, (state: ChapterCheckState.newChapters, count: 2));
    });

    test('says nothing is new when the source has the same chapters', () async {
      final result = await checkAfterOpen(() => [ch(id: 1, number: 1)]);
      expect(result, (state: ChapterCheckState.upToDate, count: 0));
    });

    test('says the check failed when the source is down', () async {
      final result = await checkAfterOpen(() => null);
      expect(result, (state: ChapterCheckState.failed, count: 0));
    });
  });
}
