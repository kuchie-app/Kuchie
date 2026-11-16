// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:pub_semver/pub_semver.dart';

/// Newest version of each package across stores, sorted by name once.
///
/// Built when the store data changes, so typing a search or tapping Install
/// only filters an already sorted list instead of re-parsing thousands of
/// versions and re-sorting on every frame.
class PackageCatalogIndex<T> {
  PackageCatalogIndex(
    Iterable<T> packages, {
    required String Function(T) id,
    required String Function(T) name,
    required String Function(T) version,
    required String Function(T) language,
  }) : _language = language {
    final newest = <String, ({T package, Version version})>{};
    for (final package in packages) {
      final parsed = Version.parse(version(package));
      final existing = newest[id(package)];
      if (existing == null || parsed > existing.version) {
        newest[id(package)] = (package: package, version: parsed);
      }
    }
    _entries = [
      for (final entry in newest.entries)
        (
          id: entry.key,
          package: entry.value.package,
          version: entry.value.version,
          lowerName: name(entry.value.package).toLowerCase(),
        ),
    ]..sort((a, b) => a.lowerName.compareTo(b.lowerName));
    _byId = {for (final entry in _entries) entry.id: entry};
  }

  final String Function(T) _language;
  late final List<({String id, T package, Version version, String lowerName})>
  _entries;
  late final Map<
    String,
    ({String id, T package, Version version, String lowerName})
  >
  _byId;

  int get length => _entries.length;

  T? operator [](String id) => _byId[id]?.package;

  /// [installed] maps package ids to the version on this iPhone.
  ///
  /// Updates and each language's list come back in name order.
  ({List<T> updates, Map<String, List<T>> byLanguage}) group({
    required Map<String, String> installed,
    required String query,
    bool Function(String language)? languageAllowed,
  }) {
    final needle = query.trim().toLowerCase();
    final updates = <T>[];
    final byLanguage = <String, List<T>>{};
    for (final entry in _entries) {
      final language = _language(entry.package);
      if (languageAllowed != null && !languageAllowed(language)) continue;
      if (needle.isNotEmpty && !entry.lowerName.contains(needle)) continue;
      final owned = installed[entry.id];
      if (owned == null) {
        (byLanguage[language] ??= []).add(entry.package);
      } else if (entry.version > Version.parse(owned)) {
        updates.add(entry.package);
      }
    }
    return (updates: updates, byLanguage: byLanguage);
  }
}
