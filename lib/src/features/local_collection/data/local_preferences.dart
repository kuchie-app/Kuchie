import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How the library is ordered, as in Tachimanga's Sort tab.
enum LocalLibrarySort { alphabetical, lastRead, unread, totalChapters }

/// Covers in a grid, or rows with details.
enum LocalLibraryDisplay { grid, list }

/// Which tab Kuchie opens on.
enum LocalDefaultTab { lastOpened, library, updates, browse, history, more }

/// Library and download settings for the Local collection.
class LocalPreferences {
  LocalPreferences._();

  static final instance = LocalPreferences._();

  static const _unreadBadgesKey = 'local.library.unreadBadges';
  static const _gridColumnsKey = 'local.library.gridColumns';
  static const _deleteAfterReadingKey = 'local.downloads.deleteAfterReading';

  /// The choices for items per row in portrait.
  static const gridColumnChoices = [2, 3, 4];

  /// Shows the unread chapter count on library covers.
  final unreadBadges = ValueNotifier<bool>(true);

  /// Library covers per row in portrait.
  final gridColumns = ValueNotifier<int>(2);

  /// Removes a saved chapter from this iPhone once it has been read to the
  /// end and the reader closes.
  final deleteAfterReading = ValueNotifier<bool>(false);

  /// Library filters: titles with unread saved chapters, titles with saved
  /// chapters.
  final filterUnread = ValueNotifier<bool>(false);
  final filterDownloaded = ValueNotifier<bool>(false);
  final sort = ValueNotifier<LocalLibrarySort>(LocalLibrarySort.alphabetical);
  final sortDescending = ValueNotifier<bool>(false);
  final display = ValueNotifier<LocalLibraryDisplay>(LocalLibraryDisplay.grid);

  /// Shows how many chapters are saved on this iPhone on library covers.
  final downloadedBadges = ValueNotifier<bool>(true);

  /// Shows the number of titles on each category tab.
  final categoryCounts = ValueNotifier<bool>(true);
  final defaultTab = ValueNotifier<LocalDefaultTab>(LocalDefaultTab.lastOpened);

  /// The tab open when Kuchie last closed, for [LocalDefaultTab.lastOpened].
  int lastTab = 0;

  /// Everything the library page reads, to rebuild it on any change.
  late final Listenable library = Listenable.merge([
    unreadBadges,
    downloadedBadges,
    gridColumns,
    filterUnread,
    filterDownloaded,
    sort,
    sortDescending,
    display,
    categoryCounts,
  ]);

  Future<void>? _loading;

  static T _enum<T extends Enum>(List<T> values, String? name, T fallback) =>
      values.firstWhere((value) => value.name == name, orElse: () => fallback);

  Future<void> _setBool(
    String key,
    ValueNotifier<bool> target,
    bool value,
  ) async {
    await load();
    target.value = value;
    await (await SharedPreferences.getInstance()).setBool(key, value);
  }

  Future<void> _setEnum<T extends Enum>(
    String key,
    ValueNotifier<T> target,
    T value,
  ) async {
    await load();
    target.value = value;
    await (await SharedPreferences.getInstance()).setString(key, value.name);
  }

  Future<void> setFilterUnread(bool value) =>
      _setBool('local.library.filterUnread', filterUnread, value);
  Future<void> setFilterDownloaded(bool value) =>
      _setBool('local.library.filterDownloaded', filterDownloaded, value);
  Future<void> setDownloadedBadges(bool value) =>
      _setBool('local.library.downloadedBadges', downloadedBadges, value);
  Future<void> setCategoryCounts(bool value) =>
      _setBool('local.library.categoryCounts', categoryCounts, value);
  Future<void> setDisplay(LocalLibraryDisplay value) =>
      _setEnum('local.library.display', display, value);
  Future<void> setDefaultTab(LocalDefaultTab value) =>
      _setEnum('local.general.defaultTab', defaultTab, value);

  /// Picks [value]; picking the current order again flips its direction.
  Future<void> setSort(LocalLibrarySort value) async {
    await load();
    if (sort.value == value) {
      await _setBool(
        'local.library.sortDescending',
        sortDescending,
        !sortDescending.value,
      );
    } else {
      await _setEnum('local.library.sort', sort, value);
      await _setBool('local.library.sortDescending', sortDescending, false);
    }
  }

  Future<void> setLastTab(int tab) async {
    lastTab = tab;
    await (await SharedPreferences.getInstance()).setInt(
      'local.general.lastTab',
      tab,
    );
  }

  Future<void> load() => _loading ??= () async {
    final prefs = await SharedPreferences.getInstance();
    unreadBadges.value = prefs.getBool(_unreadBadgesKey) ?? true;
    final columns = prefs.getInt(_gridColumnsKey);
    gridColumns.value = gridColumnChoices.contains(columns) ? columns! : 2;
    deleteAfterReading.value = prefs.getBool(_deleteAfterReadingKey) ?? false;
    filterUnread.value = prefs.getBool('local.library.filterUnread') ?? false;
    filterDownloaded.value =
        prefs.getBool('local.library.filterDownloaded') ?? false;
    sort.value = _enum(
      LocalLibrarySort.values,
      prefs.getString('local.library.sort'),
      LocalLibrarySort.alphabetical,
    );
    sortDescending.value =
        prefs.getBool('local.library.sortDescending') ?? false;
    display.value = _enum(
      LocalLibraryDisplay.values,
      prefs.getString('local.library.display'),
      LocalLibraryDisplay.grid,
    );
    downloadedBadges.value =
        prefs.getBool('local.library.downloadedBadges') ?? true;
    categoryCounts.value =
        prefs.getBool('local.library.categoryCounts') ?? true;
    defaultTab.value = _enum(
      LocalDefaultTab.values,
      prefs.getString('local.general.defaultTab'),
      LocalDefaultTab.lastOpened,
    );
    lastTab = prefs.getInt('local.general.lastTab') ?? 0;
  }();

  Future<void> setUnreadBadges(bool value) async {
    await load();
    unreadBadges.value = value;
    await (await SharedPreferences.getInstance()).setBool(
      _unreadBadgesKey,
      value,
    );
  }

  Future<void> setGridColumns(int value) async {
    if (!gridColumnChoices.contains(value)) return;
    await load();
    gridColumns.value = value;
    await (await SharedPreferences.getInstance()).setInt(
      _gridColumnsKey,
      value,
    );
  }

  Future<void> setDeleteAfterReading(bool value) async {
    await load();
    deleteAfterReading.value = value;
    await (await SharedPreferences.getInstance()).setBool(
      _deleteAfterReadingKey,
      value,
    );
  }
}
