import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kuchie/src/features/local_collection/data/local_backups.dart';
import 'package:kuchie/src/features/local_collection/data/local_catalog.dart';
import 'package:kuchie/src/features/local_collection/data/local_reading_stats.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('scheduled backups run when due and keep only the newest', () async {
    SharedPreferences.setMockInitialValues({});
    final root = await Directory.systemTemp.createTemp('kuchie-backups');
    addTearDown(() => root.delete(recursive: true));
    final catalog = LocalCatalog(Directory('${root.path}/catalog'));
    addTearDown(catalog.close);
    final backups = LocalBackups.instance
      ..directoryForTesting = Directory('${root.path}/backups');

    // Off: nothing is written.
    await backups.runIfDue(catalog);
    expect(await backups.list(), isEmpty);

    await backups.setFrequency(LocalBackupFrequency.daily);
    await backups.setMaxBackups(1);
    await backups.runIfDue(catalog);
    expect(await backups.list(), hasLength(1));
    expect((await backups.list()).single.automatic, isTrue);

    // Not due again within the day.
    await backups.runIfDue(catalog);
    expect(await backups.list(), hasLength(1));

    // A manual backup is kept beside the automatic one, and pruning only
    // counts automatic backups.
    await Future<void>.delayed(const Duration(seconds: 1));
    await backups.create(catalog);
    await Future<void>.delayed(const Duration(seconds: 1));
    await backups.create(catalog, automatic: true);
    final files = await backups.list();
    expect(files.where((backup) => backup.automatic), hasLength(1));
    expect(files.where((backup) => !backup.automatic), hasLength(1));
  });

  test('reading time adds up per series and ignores taps', () async {
    SharedPreferences.setMockInitialValues({});
    final stats = LocalReadingStats.instance;
    await stats.add('a', 'Alpha', const Duration(minutes: 13));
    await stats.add('b', 'Beta', const Duration(hours: 1, minutes: 2));
    await stats.add('a', 'Alpha', const Duration(minutes: 2));
    await stats.add('b', 'Beta', const Duration(seconds: 1));

    expect(stats.timeFor('a'), const Duration(minutes: 15));
    expect(stats.ranked.map((entry) => entry.title), ['Beta', 'Alpha']);
    expect(formatReadingTime(stats.total), '1 h 17 m');
    expect(formatReadingTime(const Duration(seconds: 30)), '< 1 m');
  });
}
