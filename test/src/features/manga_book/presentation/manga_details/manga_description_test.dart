import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kuchie/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:kuchie/src/features/manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import 'package:kuchie/src/features/manga_book/presentation/manga_details/controller/next_update_controller.dart';
import 'package:kuchie/src/features/manga_book/presentation/manga_details/widgets/manga_description.dart';
import 'package:kuchie/src/features/offline/data/offline_repository.dart';
import 'package:kuchie/src/global_providers/global_providers.dart';
import 'package:kuchie/src/l10n/generated/app_localizations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../reader/reader_test_fixtures.dart';

class _LibraryManga extends MangaWithId {
  @override
  Future<MangaDto?> build({required int mangaId}) async => testManga();
}

void main() {
  testWidgets('In library opens the category editor instead of removing', (
    tester,
  ) async {
    var edits = 0;
    var adds = 0;
    var refreshes = 0;
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          mangaNextUpdateProvider(mangaId: 1).overrideWith((ref) => null),
          mangaWithIdProvider(mangaId: 1).overrideWith(_LibraryManga.new),
          offlineEnabledProvider.overrideWithValue(false),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: MangaDescription(
                manga: testManga(),
                editLibraryCategories: () async {
                  edits++;
                },
                addMangaToLibrary: () async {
                  adds++;
                },
                onMigrate: () async {},
                refresh: () async {
                  refreshes++;
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('In library'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(edits, 1);
    expect(adds, 0);
    expect(refreshes, 1);
    expect(find.text('In library'), findsOneWidget);
  });
}
