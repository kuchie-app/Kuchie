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
  _Repository()
    : super(
        GraphQLClient(
          link: HttpLink('http://localhost:0'),
          cache: GraphQLCache(),
        ),
      );
  int sourceRequests = 0;

  @override
  Future<List<ChapterDto>?> getStoredChapterList(int mangaId) async => [
    ch(id: 1, number: 1),
  ];

  @override
  Future<List<ChapterDto>?> getMangaAndChapterList(int mangaId) async {
    sourceRequests++;
    return [ch(id: 1, number: 1), ch(id: 2, number: 2)];
  }
}

Future<(ProviderContainer, _Repository)> _open(
  Map<String, Object> prefsValues,
) async {
  SharedPreferences.setMockInitialValues(prefsValues);
  final prefs = await SharedPreferences.getInstance();
  final repo = _Repository();
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

  test('opening a series shows stored chapters, then the source scrape', () async {
    final (container, repo) = await _open({});
    addTearDown(container.dispose);
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);

    final first = await container.read(provider.future);
    expect(first!.map((chapter) => chapter.id), [1]);

    await pumpEventQueue();
    expect(repo.sourceRequests, 1);
    expect(ids(container), [1, 2]);
  });

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
}
