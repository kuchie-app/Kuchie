// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:kuchie/src/constants/enum.dart';
import 'package:kuchie/src/constants/timeout_constants.dart';
import 'package:kuchie/src/features/settings/data/preference_migrations.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SharedPreferences> _prefs(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

Future<void> _runAll(SharedPreferences prefs) => runPreferenceMigrations(
  prefs,
  preferenceMigrations(windowWidth: 390),
  onError: (name, error, stack) => fail('$name failed: $error'),
);

void main() {
  test('steps keep their historical order', () {
    expect(preferenceMigrations(windowWidth: 390).map((m) => m.name), [
      'readerIgnoreSafeArea',
      'readerAnimation',
      'updatesGrouping',
      'firstRun',
      'serverUrlSplit',
      'lastReadSortDirection',
      'requestTimeout',
      'gridCover',
      'badges',
    ]);
  });

  test(
    'an upgrade from an old install applies each inline step once',
    () async {
      final prefs = await _prefs({
        'readerIgnoreSafeArea': false,
        'updatesGroupingMode': UpdatesGroupingMode.disabled.index,
        'serverUrl': 'http://192.168.1.2:4567',
        'mangaSortDirection': true,
        'serverRequestTimeout': 5000,
      });

      await _runAll(prefs);

      expect(prefs.getBool('readerIgnoreSafeArea'), isTrue);
      expect(
        prefs.getInt('updatesGroupingMode'),
        UpdatesGroupingMode.collapsed.index,
      );
      expect(prefs.getString('serverExternalUrl'), 'http://192.168.1.2:4567');
      expect(prefs.getBool('mangaSortDirection'), isFalse);
      expect(
        prefs.getInt('serverRequestTimeout'),
        TimeoutConstants.requestTimeoutDefaultMs,
      );
      expect(prefs.getBool('autoRefreshOnTimeout'), isTrue);
    },
  );

  test('running the steps again changes nothing', () async {
    final prefs = await _prefs({
      'mangaSortDirection': true,
      'serverUrl': 'http://192.168.1.2:4567',
    });
    await _runAll(prefs);
    final once = {for (final key in prefs.getKeys()) key: prefs.get(key)};

    // A user choice made after the upgrade must survive the next launch.
    await prefs.setBool('mangaSortDirection', true);
    await prefs.setInt('serverRequestTimeout', 9000);
    await _runAll(prefs);

    expect(prefs.getBool('mangaSortDirection'), isTrue);
    expect(prefs.getInt('serverRequestTimeout'), 9000);
    expect(prefs.getKeys(), once.keys.toSet());
  });

  test('an existing remote URL is not replaced by the active one', () async {
    final prefs = await _prefs({
      'serverExternalUrl': 'https://manga.example.org',
      'serverUrl': 'http://192.168.1.2:4567',
    });
    await _runAll(prefs);
    expect(prefs.getString('serverExternalUrl'), 'https://manga.example.org');
  });

  test('a failing step is reported and the rest still run', () async {
    final prefs = await _prefs({});
    final failures = <String>[];
    var after = false;
    await runPreferenceMigrations(prefs, [
      PreferenceMigration('broken', (_) async => throw StateError('boom')),
      PreferenceMigration('after', (_) async => after = true),
    ], onError: (name, error, stack) => failures.add(name));
    expect(failures, ['broken']);
    expect(after, isTrue);
  });
}
