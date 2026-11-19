import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_catalog.dart';

/// How often Kuchie backs up the Local collection on its own.
enum LocalBackupFrequency {
  off(null),
  every6Hours(Duration(hours: 6)),
  every12Hours(Duration(hours: 12)),
  daily(Duration(days: 1)),
  every2Days(Duration(days: 2)),
  weekly(Duration(days: 7));

  const LocalBackupFrequency(this.interval);

  final Duration? interval;
}

/// A backup file kept on this iPhone.
typedef LocalBackupFile = ({
  File file,
  DateTime createdAt,
  int bytes,
  bool automatic,
});

/// Backups of library metadata kept inside Kuchie, made by hand or on a
/// schedule, as Tachimanga's Backup & Restore keeps them.
class LocalBackups {
  LocalBackups._();

  static final instance = LocalBackups._();

  static const _frequencyKey = 'local.backup.frequency';
  static const _maxKey = 'local.backup.max';
  static const _lastAutoKey = 'local.backup.lastAutomatic';
  static const maxChoices = [1, 2, 3, 5, 10];

  final frequency = ValueNotifier<LocalBackupFrequency>(
    LocalBackupFrequency.off,
  );
  final maxBackups = ValueNotifier<int>(2);
  final lastAutomatic = ValueNotifier<DateTime?>(null);

  /// Bumped whenever the list of files changes.
  final revision = ValueNotifier<int>(0);

  Future<void>? _loading;
  Directory? _overrideDirectory;

  @visibleForTesting
  set directoryForTesting(Directory directory) =>
      _overrideDirectory = directory;

  Future<void> load() => _loading ??= () async {
    final prefs = await SharedPreferences.getInstance();
    frequency.value = LocalBackupFrequency.values.firstWhere(
      (value) => value.name == prefs.getString(_frequencyKey),
      orElse: () => LocalBackupFrequency.off,
    );
    final max = prefs.getInt(_maxKey);
    maxBackups.value = maxChoices.contains(max) ? max! : 2;
    final last = prefs.getInt(_lastAutoKey);
    lastAutomatic.value = last == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(last);
  }();

  Future<Directory> _directory() async {
    final directory =
        _overrideDirectory ??
        Directory(
          p.join((await getApplicationSupportDirectory()).path, 'backups'),
        );
    await directory.create(recursive: true);
    return directory;
  }

  Future<void> setFrequency(LocalBackupFrequency value) async {
    await load();
    frequency.value = value;
    await (await SharedPreferences.getInstance()).setString(
      _frequencyKey,
      value.name,
    );
  }

  Future<void> setMaxBackups(int value) async {
    if (!maxChoices.contains(value)) return;
    await load();
    maxBackups.value = value;
    await (await SharedPreferences.getInstance()).setInt(_maxKey, value);
    await _prune();
  }

  /// Backups on this iPhone, newest first.
  Future<List<LocalBackupFile>> list() async {
    final directory = await _directory();
    final files = <LocalBackupFile>[];
    await for (final entry in directory.list()) {
      if (entry is! File || !entry.path.endsWith('.json')) continue;
      final stat = await entry.stat();
      files.add((
        file: entry,
        createdAt: stat.modified,
        bytes: stat.size,
        automatic: p.basename(entry.path).contains('-auto'),
      ));
    }
    return files..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// Writes a backup of [catalog] and returns it.
  Future<File> create(LocalCatalog catalog, {bool automatic = false}) async {
    final directory = await _directory();
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    final stamp =
        '${now.year}-${two(now.month)}-${two(now.day)}_'
        '${two(now.hour)}-${two(now.minute)}-${two(now.second)}';
    final file = File(
      p.join(
        directory.path,
        'kuchie-local-$stamp${automatic ? '-auto' : ''}.json',
      ),
    );
    await catalog.exportMetadata(file);
    if (automatic) {
      lastAutomatic.value = now;
      await (await SharedPreferences.getInstance()).setInt(
        _lastAutoKey,
        now.millisecondsSinceEpoch,
      );
      await _prune();
    }
    revision.value++;
    return file;
  }

  /// Backs up [catalog] when the chosen interval has passed.
  Future<void> runIfDue(LocalCatalog catalog) async {
    await load();
    final interval = frequency.value.interval;
    if (interval == null) return;
    final last = lastAutomatic.value;
    if (last != null && DateTime.now().difference(last) < interval) return;
    await create(catalog, automatic: true);
  }

  Future<void> delete(File file) async {
    if (await file.exists()) await file.delete();
    revision.value++;
  }

  /// Keeps only the newest [maxBackups] automatic backups.
  Future<void> _prune() async {
    final automatic = [
      for (final backup in await list())
        if (backup.automatic) backup,
    ];
    for (final backup in automatic.skip(maxBackups.value)) {
      await backup.file.delete();
    }
    revision.value++;
  }
}
