// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../constants/db_keys.dart';
import '../../../../../routes/router_config.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/motion/reduce_motion.dart';
import '../../../../../widgets/popup_widgets/app_dialog.dart';
import '../../../../library/data/default_category.dart';
import '../../../../library/domain/category/category_model.dart';
import '../../../../library/domain/duplicate_entry_mapper.dart';
import '../../../../library/domain/duplicate_matcher.dart';
import '../../../../library/presentation/category/controller/edit_category_controller.dart';
import '../../../../library/presentation/library/controller/library_controller.dart';
import '../../../../library/presentation/library/controller/library_manga_list.dart';
import '../../../../offline/data/offline_download_providers.dart';
import '../../../data/manga_book/manga_book_repository.dart';
import '../../../domain/manga/manga_model.dart';
import '../controller/manga_details_controller.dart';
import 'duplicate_manga_dialog.dart';
import 'migrate_duplicate.dart';

/// Adds [manga] to the library. Without a preferred category it asks where to
/// keep it, starting with nothing checked. Returns true once it was added.
Future<bool> addMangaToLibraryWithCategory(
  WidgetRef ref,
  BuildContext context,
  MangaDto manga, {
  @visibleForTesting
  Future<bool> Function(MangaDto from, MangaDto to)? migrateDuplicate,
  @visibleForTesting
  void Function(BuildContext context, MangaDto manga)? openEntry,
}) async {
  // Capture the container so writes and invalidation survive details-page disposal.
  final container = ProviderScope.containerOf(context, listen: false);
  final repo = container.read(mangaBookRepositoryProvider);
  final mangaId = manga.id;
  // Load the categories while the duplicate check runs instead of after it.
  final categoriesFuture = _pickableCategories(container)..ignore();

  if (!await _passesDuplicateGate(
    ref,
    container,
    context,
    manga,
    migrateDuplicate: migrateDuplicate,
    openEntry: openEntry,
  )) {
    return false;
  }
  if (!context.mounted) return false;

  final pref =
      container.read(libraryDefaultCategoryProvider) ??
      DBKeys.libraryDefaultCategory.initial;
  final categories = await categoriesFuture;
  if (!context.mounted) return false;

  final match = categories.where((c) => c.id == pref).toList();
  Future<void> Function() write;
  if (match.isNotEmpty) {
    write = () async {
      await repo.addMangaToLibrary(mangaId);
      await repo.addMangaToCategory(mangaId, match.first.id);
    };
  } else if (pref == 0 || categories.isEmpty) {
    // A deleted category preference falls through to the picker, not the uncategorized branch.
    write = () => repo.addMangaToLibrary(mangaId);
  } else {
    final picked = await showLibraryCategoryPicker<int>(
      context,
      options: [for (final c in categories) (id: c.id, name: c.name)],
      initial: const {},
      inLibrary: false,
      subtitle: manga.title,
      onEditCategories: () => const EditCategoriesRoute().push(context),
    );
    if (picked == null) return false; // cancelled
    write = () async {
      await repo.addMangaToLibrary(mangaId);
      // One request sets the exact choice, including any server auto-assignment.
      await repo.updateMangasCategories(
        [mangaId],
        addTo: picked.toList(),
        removeFrom: [
          for (final c in categories)
            if (!picked.contains(c.id)) c.id,
        ],
      );
    };
  }
  await _writeLibraryChange(container, mangaId, inLibrary: true, write: write);
  return true;
}

/// Shows where [manga] is kept, pre-checked. Changing the checks moves it
/// between categories; unchecking all of them removes it from the library.
Future<void> editMangaLibraryCategories(
  WidgetRef ref,
  BuildContext context,
  MangaDto manga,
) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final repo = container.read(mangaBookRepositoryProvider);
  final mangaId = manga.id;
  final (categories, current) = await (
    _pickableCategories(container),
    repo.getMangaCategoryList(mangaId: mangaId),
  ).wait;
  if (!context.mounted) return;

  Future<void> remove() => _writeLibraryChange(
    container,
    mangaId,
    inLibrary: false,
    write: () => removeMangaFromLibraryAndPurge(container, mangaId),
  );

  if (categories.isEmpty) {
    if (await _confirmRemoval(context) && context.mounted) await remove();
    return;
  }
  final ids = {for (final c in categories) c.id};
  final before = {
    for (final c in current ?? const <CategoryDto>[])
      if (ids.contains(c.id)) c.id,
  };
  final picked = await showLibraryCategoryPicker<int>(
    context,
    options: [for (final c in categories) (id: c.id, name: c.name)],
    initial: before,
    inLibrary: true,
    subtitle: manga.title,
    onEditCategories: () => const EditCategoriesRoute().push(context),
  );
  if (picked == null || !context.mounted) return;
  if (picked.isEmpty) return remove();
  final addTo = picked.difference(before).toList();
  final removeFrom = before.difference(picked).toList();
  if (addTo.isEmpty && removeFrom.isEmpty) return;
  await repo.updateMangasCategories(
    [mangaId],
    addTo: addTo,
    removeFrom: removeFrom,
  );
  container.invalidate(mangaCategoryListProvider(mangaId));
  container.invalidate(categoryControllerProvider);
  container.invalidate(libraryMangaListProvider);
}

/// Categories a series can be filed under; the default category is implicit.
Future<List<CategoryDto>> _pickableCategories(
  ProviderContainer container,
) async {
  final (defaultId, categories) = await (
    container.read(defaultCategoryIdProvider.future),
    container.read(categoryControllerProvider.future),
  ).wait;
  if (defaultId == null) throw StateError('Default category unavailable');
  return [
    for (final c in categories ?? const <CategoryDto>[])
      if (c.id != defaultId) c,
  ];
}

/// Flips the open series page at once and undoes it if the write fails.
Future<void> _writeLibraryChange(
  ProviderContainer container,
  int mangaId, {
  required bool inLibrary,
  required Future<void> Function() write,
}) async {
  final provider = mangaWithIdProvider(mangaId: mangaId);
  void show(bool value) {
    if (container.read(provider.exists)) {
      container.read(provider.notifier).showInLibrary(value);
    }
  }

  show(inLibrary);
  try {
    await write();
  } catch (_) {
    show(!inLibrary);
    rethrow;
  }
  container.invalidate(mangaCategoryListProvider(mangaId));
  container.invalidate(libraryMangaListProvider);
}

Future<bool> _confirmRemoval(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AdaptiveAppAlert(
        title: Text(context.l10n.removeFromLibrary),
        content: Text(context.l10n.duplicatesRemoveConfirm(1)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.l10n.remove),
          ),
        ],
      ),
      animationStyle: context.motionStyle,
    ) ==
    true;

/// Allow adds on duplicate-check read failure; false means opened, migrated, or cancelled.
Future<bool> _passesDuplicateGate(
  WidgetRef ref,
  ProviderContainer container,
  BuildContext context,
  MangaDto manga, {
  Future<bool> Function(MangaDto from, MangaDto to)? migrateDuplicate,
  void Function(BuildContext context, MangaDto manga)? openEntry,
}) async {
  // A library page that is open already holds the list; fetching all of it
  // again was what made the button feel slow.
  final loaded = container.read(libraryMangaListProvider.exists)
      ? container.read(libraryMangaListProvider).value
      : null;
  List<MangaDto>? libraryOrNull = loaded;
  if (libraryOrNull == null) {
    try {
      libraryOrNull = await container.read(libraryMangaListProvider.future);
    } catch (_) {
      libraryOrNull = null;
    }
  }
  if (!context.mounted) return false;
  final library = libraryOrNull;
  if (library == null) return true; // list unavailable ⇒ fail open

  final entries = library.map(dupEntryFromManga).toList();
  final candidate = dupEntryFromManga(manga);
  final titleHits = titleDuplicates(
    candidateId: manga.id,
    candidateTitle: manga.title,
    entries: entries,
  );
  final trackerHits = trackerDuplicates(
    candidateId: manga.id,
    candidatePairs: candidate.trackerPairs,
    entries: entries,
  );
  final hitIds = {
    ...titleHits.map((e) => e.id),
    ...trackerHits.map((e) => e.id),
  };
  if (hitIds.isEmpty) return true;

  final trackerNames = container.read(libraryTrackerNamesProvider);
  final migrate =
      migrateDuplicate ??
      (MangaDto from, MangaDto to) =>
          migrateDuplicateIntoCandidate(ref, context, from: from, to: to);
  final open =
      openEntry ??
      (BuildContext ctx, MangaDto target) =>
          MangaRoute(mangaId: target.id).push(ctx);

  MangaDto? toOpen;
  final result = await showDialog<DuplicateDialogResult>(
    context: context,
    barrierDismissible: true, // barrier tap ⇒ null ⇒ cancel (below)
    builder: (_) => DuplicateMangaDialog(
      candidate: manga,
      duplicates: library.where((m) => hitIds.contains(m.id)).toList(),
      certainIds: trackerHits.map((e) => e.id).toSet(),
      trackerNameOf: (id) => trackerNames[id],
      onMigrate: (dup) => migrate(dup, manga),
      onOpenEntry: (m) => toOpen = m,
    ),
    animationStyle: context.motionStyle,
  );
  if (!context.mounted) return false;
  if (result == DuplicateDialogResult.openedEntry) {
    final target = toOpen;
    if (target != null) open(context, target);
    return false;
  }
  return result == DuplicateDialogResult.addAnyway;
}

/// A category the picker offers: a server category id or a local category name.
typedef LibraryCategoryOption<T> = ({T id, String name});

/// Asks where a series is kept. Returns the checked ids, or null when
/// cancelled. While [inLibrary], an empty choice means removing the series.
Future<Set<T>?> showLibraryCategoryPicker<T>(
  BuildContext context, {
  required List<LibraryCategoryOption<T>> options,
  required Set<T> initial,
  required bool inLibrary,
  String? subtitle,
  VoidCallback? onEditCategories,
}) => showDialog<Set<T>>(
  context: context,
  animationStyle: context.motionStyle,
  builder: (_) => LibraryCategoryPicker<T>(
    options: options,
    initial: initial,
    inLibrary: inLibrary,
    subtitle: subtitle,
    onEditCategories: onEditCategories,
  ),
);

class LibraryCategoryPicker<T> extends HookWidget {
  const LibraryCategoryPicker({
    super.key,
    required this.options,
    required this.initial,
    required this.inLibrary,
    this.subtitle,
    this.onEditCategories,
  });

  final List<LibraryCategoryOption<T>> options;
  final Set<T> initial;
  final bool inLibrary;
  final String? subtitle;
  final VoidCallback? onEditCategories;

  @override
  Widget build(BuildContext context) {
    final selected = useState<Set<T>>({...initial});
    final removing = inLibrary && selected.value.isEmpty;
    final cs = context.theme.colorScheme;
    return AppDialogPanel(
      title: inLibrary ? context.l10n.editCategory : context.l10n.setCategories,
      subtitle: subtitle.isNotBlank ? subtitle : null,
      scrollContent: false,
      content: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: context.height * .6),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final option in options)
                CheckboxListTile(
                  controlAffinity: ListTileControlAffinity.leading,
                  value: selected.value.contains(option.id),
                  title: Text(option.name),
                  onChanged: (value) {
                    final next = {...selected.value};
                    value.ifNull()
                        ? next.add(option.id)
                        : next.remove(option.id);
                    selected.value = next;
                  },
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (onEditCategories != null)
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onEditCategories!();
            },
            child: Text(context.l10n.edit),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        TextButton(
          // Adding needs a category; while in the library, none means remove.
          onPressed: !inLibrary && selected.value.isEmpty
              ? null
              : () => Navigator.pop(context, selected.value),
          style: removing
              ? TextButton.styleFrom(foregroundColor: cs.error)
              : null,
          child: Text(
            removing
                ? context.l10n.removeFromLibrary
                : inLibrary
                ? context.l10n.save
                : context.l10n.addToLibrary,
          ),
        ),
      ],
    );
  }
}
