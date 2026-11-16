// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:shared_preferences/shared_preferences.dart';

import '../../../constants/enum.dart';
import '../../../constants/timeout_constants.dart';
import '../../library/data/badge_preference_migration.dart';
import '../../onboarding/data/onboarding_complete.dart';
import 'grid_cover_preference_migration.dart';
import 'reader_animation_preference_migration.dart';

/// One startup upgrade of stored preferences. Each step guards itself, so
/// running it again on an upgraded install changes nothing.
class PreferenceMigration {
  const PreferenceMigration(this.name, this.run);

  final String name;
  final Future<void> Function(SharedPreferences prefs) run;
}

/// The startup preference upgrades, oldest first. Append new steps at the end;
/// later steps may rely on earlier ones having run.
List<PreferenceMigration> preferenceMigrations({
  required double windowWidth,
}) => [
  const PreferenceMigration('readerIgnoreSafeArea', _readerIgnoreSafeAreaOn),
  const PreferenceMigration(
    'readerAnimation',
    migrateReaderAnimationPreference,
  ),
  const PreferenceMigration('updatesGrouping', _updatesGroupingCollapsed),
  const PreferenceMigration('firstRun', seedFirstRunPreferences),
  // Preserve the remote URL before the LAN resolver can replace serverUrl.
  const PreferenceMigration('serverUrlSplit', _splitServerUrl),
  const PreferenceMigration('lastReadSortDirection', _flipLastReadSort),
  const PreferenceMigration('requestTimeout', _requestTimeoutDefault),
  PreferenceMigration(
    'gridCover',
    (prefs) => migrateGridCoverPreference(prefs, windowWidth: windowWidth),
  ),
  const PreferenceMigration('badges', migrateBadgePreferences),
];

/// Runs [migrations] in order. A failing step is reported and skipped so
/// the others still run and the app still starts.
Future<void> runPreferenceMigrations(
  SharedPreferences prefs,
  List<PreferenceMigration> migrations, {
  required void Function(String name, Object error, StackTrace stack) onError,
}) async {
  for (final migration in migrations) {
    try {
      await migration.run(prefs);
    } catch (error, stack) {
      onError(migration.name, error, stack);
    }
  }
}

Future<void> _readerIgnoreSafeAreaOn(SharedPreferences prefs) async {
  const migratedKey = 'readerIgnoreSafeAreaDefaultOnMigrated';
  if (prefs.getBool(migratedKey) == true) return;
  if (prefs.getBool('readerIgnoreSafeArea') == false) {
    await prefs.setBool('readerIgnoreSafeArea', true);
  }
  await prefs.setBool(migratedKey, true);
}

Future<void> _updatesGroupingCollapsed(SharedPreferences prefs) async {
  const migratedKey = 'updatesGroupingCollapsedMigrated';
  if (prefs.getBool(migratedKey) == true) return;
  if (prefs.getInt('updatesGroupingMode') ==
      UpdatesGroupingMode.disabled.index) {
    await prefs.setInt(
      'updatesGroupingMode',
      UpdatesGroupingMode.collapsed.index,
    );
  }
  await prefs.setBool(migratedKey, true);
}

Future<void> _splitServerUrl(SharedPreferences prefs) async {
  const externalKey = 'serverExternalUrl';
  if (prefs.getString(externalKey) != null) return;
  final legacyUrl = prefs.getString('serverUrl');
  if (legacyUrl != null) await prefs.setString(externalKey, legacyUrl);
}

Future<void> _flipLastReadSort(SharedPreferences prefs) async {
  const migratedKey = 'lastReadSortDirectionMigrated';
  if (prefs.getBool(migratedKey) == true) return;
  final sortIdx = prefs.getInt('mangaSort');
  // An unset mangaSort defaults to Last-Read.
  final onLastRead = sortIdx == null || sortIdx == MangaSort.lastRead.index;
  final savedDir = prefs.getBool('mangaSortDirection');
  if (onLastRead && savedDir != null) {
    await prefs.setBool('mangaSortDirection', !savedDir);
  }
  await prefs.setBool(migratedKey, true);
}

Future<void> _requestTimeoutDefault(SharedPreferences prefs) async {
  const migratedKey = 'requestTimeout30sMigrated';
  if (prefs.getBool(migratedKey) == true) return;
  await prefs.setInt(
    'serverRequestTimeout',
    TimeoutConstants.requestTimeoutDefaultMs,
  );
  await prefs.setBool('autoRefreshOnTimeout', true);
  await prefs.setBool(migratedKey, true);
}
