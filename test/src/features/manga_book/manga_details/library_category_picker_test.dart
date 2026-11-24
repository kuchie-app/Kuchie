import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kuchie/src/features/library/data/default_category.dart';
import 'package:kuchie/src/features/library/domain/category/category_model.dart';
import 'package:kuchie/src/features/library/domain/category/graphql/__generated__/fragment.graphql.dart';
import 'package:kuchie/src/features/library/presentation/category/controller/edit_category_controller.dart';
import 'package:kuchie/src/features/library/presentation/library/controller/library_controller.dart';
import 'package:kuchie/src/features/library/presentation/library/controller/library_manga_list.dart';
import 'package:kuchie/src/features/manga_book/data/manga_book/manga_book_repository.dart';
import 'package:kuchie/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:kuchie/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:kuchie/src/features/manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import 'package:kuchie/src/features/manga_book/presentation/manga_details/widgets/add_to_library_category.dart';
import 'package:kuchie/src/graphql/__generated__/schema.graphql.dart';
import 'package:kuchie/src/l10n/generated/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

import '../reader/reader_test_fixtures.dart';

CategoryDto _cat(int id, String name) => Fragment$CategoryDto(
  defaultCategory: false,
  id: id,
  includeInDownload: Enum$IncludeOrExclude.UNSET,
  includeInUpdate: Enum$IncludeOrExclude.UNSET,
  name: name,
  order: id,
  mangas: Fragment$CategoryDto$mangas(totalCount: 0),
  meta: const [],
);

class _Repo extends MangaBookRepository {
  _Repo({this.current = const []})
    : super(
        GraphQLClient(
          link: HttpLink('http://localhost:0'),
          cache: GraphQLCache(),
        ),
      );
  final List<CategoryDto> current;
  final addedToLibrary = <int>[];
  final updates = <({Set<int> addTo, Set<int> removeFrom})>[];

  @override
  Future<MangaDto?> addMangaToLibrary(int mangaId) async {
    addedToLibrary.add(mangaId);
    return null;
  }

  @override
  Future<void> updateMangasCategories(
    List<int> mangaIds, {
    List<int> addTo = const [],
    List<int> removeFrom = const [],
    bool clearCategories = false,
  }) async =>
      updates.add((addTo: addTo.toSet(), removeFrom: removeFrom.toSet()));

  @override
  Future<List<CategoryDto>?> getMangaCategoryList({
    required int mangaId,
  }) async => current;
}

class _Categories extends CategoryController {
  @override
  Future<List<CategoryDto>?> build() async => [
    _cat(0, 'Default'),
    _cat(1, 'Complete'),
    _cat(2, 'Pornhwa'),
  ];
}

class _AlwaysAsk extends LibraryDefaultCategory {
  @override
  int? build() => -1;
}

class _OpenSeries extends MangaWithId {
  @override
  Future<MangaDto?> build({required int mangaId}) async =>
      _manga(inLibrary: false);
}

MangaDto _manga({required bool inLibrary}) {
  final manga = testManga().copyWith.call(id: 76, title: 'Manga 76');
  return manga.copyWith(user: manga.user.copyWith(inLibrary: inLibrary));
}

ProviderContainer _container(_Repo repo) => ProviderContainer(
  overrides: [
    defaultCategoryIdProvider.overrideWith((ref) async => 0),
    mangaBookRepositoryProvider.overrideWithValue(repo),
    categoryControllerProvider.overrideWith(_Categories.new),
    libraryDefaultCategoryProvider.overrideWith(_AlwaysAsk.new),
    libraryMangaListProvider.overrideWith((ref) async => const <MangaDto>[]),
    mangaWithIdProvider(mangaId: 76).overrideWith(_OpenSeries.new),
  ],
);

Widget _harness(
  ProviderContainer c,
  Future<void> Function(WidgetRef ref, BuildContext context) action,
) => UncontrolledProviderScope(
  container: c,
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Consumer(
      builder: (context, ref, _) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => action(ref, context),
            child: const Text('go'),
          ),
        ),
      ),
    ),
  ),
);

bool? _checked(WidgetTester tester, String label) => tester
    .widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, label))
    .value;

TextButton _button(WidgetTester tester, String label) =>
    tester.widget<TextButton>(find.widgetWithText(TextButton, label));

void main() {
  testWidgets('adding starts with nothing checked and files under every pick', (
    tester,
  ) async {
    final repo = _Repo();
    final c = _container(repo);
    addTearDown(c.dispose);
    final series = mangaWithIdProvider(mangaId: 76);
    final keep = c.listen(series, (_, _) {});
    addTearDown(keep.close);
    await c.read(series.future);
    bool? added;
    await tester.pumpWidget(
      _harness(c, (ref, context) async {
        added = await addMangaToLibraryWithCategory(
          ref,
          context,
          _manga(inLibrary: false),
        );
      }),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.text('Set categories'), findsOneWidget);
    expect(find.text('Default'), findsNothing);
    expect(_checked(tester, 'Complete'), isFalse);
    expect(_checked(tester, 'Pornhwa'), isFalse);
    expect(_button(tester, 'Add to library').onPressed, isNull);

    await tester.tap(find.text('Complete'));
    await tester.tap(find.text('Pornhwa'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to library'));
    await tester.pumpAndSettle();

    expect(added, isTrue);
    expect(repo.addedToLibrary, [76]);
    expect(repo.updates.single.addTo, {1, 2});
    expect(repo.updates.single.removeFrom, isEmpty);
    // The open series page flips without waiting for a refetch.
    expect(c.read(series).value!.user.inLibrary, isTrue);
  });

  testWidgets('cancelling the picker adds nothing', (tester) async {
    final repo = _Repo();
    final c = _container(repo);
    addTearDown(c.dispose);
    bool? added;
    await tester.pumpWidget(
      _harness(c, (ref, context) async {
        added = await addMangaToLibraryWithCategory(
          ref,
          context,
          _manga(inLibrary: false),
        );
      }),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(added, isFalse);
    expect(repo.addedToLibrary, isEmpty);
    expect(repo.updates, isEmpty);
  });

  testWidgets('editing pre-checks current categories and moves the series', (
    tester,
  ) async {
    final repo = _Repo(current: [_cat(1, 'Complete')]);
    final c = _container(repo);
    addTearDown(c.dispose);
    await tester.pumpWidget(
      _harness(
        c,
        (ref, context) =>
            editMangaLibraryCategories(ref, context, _manga(inLibrary: true)),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.text('Edit category'), findsOneWidget);
    expect(_checked(tester, 'Complete'), isTrue);
    expect(_checked(tester, 'Pornhwa'), isFalse);

    await tester.tap(find.text('Complete'));
    await tester.tap(find.text('Pornhwa'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(repo.addedToLibrary, isEmpty);
    expect(repo.updates.single.addTo, {2});
    expect(repo.updates.single.removeFrom, {1});
  });

  testWidgets('unchecking every category turns Save into Remove', (
    tester,
  ) async {
    Set<int>? result = {-1};
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showLibraryCategoryPicker<int>(
                context,
                options: const [(id: 1, name: 'Complete')],
                initial: const {1},
                inLibrary: true,
              );
            },
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Save'), findsOneWidget);

    await tester.tap(find.text('Complete'));
    await tester.pumpAndSettle();
    expect(find.text('Save'), findsNothing);
    await tester.tap(find.text('Remove from library'));
    await tester.pumpAndSettle();

    expect(result, isEmpty);
  });
}
