// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Data, domain and controller code serves the UI; it must not depend on it.
/// A provider that data code needs belongs in a `data/` folder, not in the
/// widget file that happens to show it.
const _lowerLayers = ['/data/', '/domain/', '/controller/'];

/// Files that still read state owned by a presentation controller. Each one
/// waits on moving that state below the UI; remove the entry when it does.
/// New files are not added here.
const _pending = <String>{
  'lib/src/features/manga_book/data/recommendations/recommendation_repository.dart',
  'lib/src/features/migration/controller/bulk_migration_providers.dart',
  'lib/src/features/migration/controller/migration_controller.dart',
  'lib/src/features/offline/data/download_live_activity.dart',
  'lib/src/features/offline/data/offline_chapter_catchup.dart',
  'lib/src/features/offline/data/offline_download_providers.dart',
  'lib/src/features/offline/data/offline_sync.dart',
};

final _import = RegExp(r"^import '([^']+)'", multiLine: true);

bool _isGenerated(String path) =>
    path.endsWith('.g.dart') ||
    path.endsWith('.freezed.dart') ||
    path.endsWith('.graphql.dart') ||
    path.contains('/__generated__/');

String? _resolve(String from, String uri) {
  if (uri.startsWith('package:kuchie/')) {
    return 'lib/${uri.substring('package:kuchie/'.length)}';
  }
  if (uri.startsWith('package:') || uri.startsWith('dart:')) return null;
  return p.posix.normalize(p.posix.join(p.posix.dirname(from), uri));
}

/// Controllers under presentation/ are UI state, so they count as presentation.
bool _inPresentation(String path) => path.contains('/presentation/');

bool _isLowerLayer(String path) =>
    !_inPresentation(path) && _lowerLayers.any(path.contains);

void main() {
  final sources = Directory('lib/src')
      .listSync(recursive: true)
      .whereType<File>()
      .map((f) => f.path.replaceAll(r'\', '/'))
      .where((path) => path.endsWith('.dart') && !_isGenerated(path))
      .toList();

  test('data, domain and controller code does not import presentation', () {
    final offenders = <String>[];
    for (final path in sources) {
      if (!_isLowerLayer(path)) continue;
      if (_pending.contains(path)) continue;
      final text = File(path).readAsStringSync();
      for (final match in _import.allMatches(text)) {
        final target = _resolve(path, match.group(1)!);
        if (target != null && _inPresentation(target)) {
          offenders.add('$path -> $target');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Lower layers must not depend on widgets or screens. Move the '
          'provider or type they need into a data/ or domain/ folder:\n'
          '${offenders.join('\n')}',
    );
  });

  test('the pending list only names files that still need it', () {
    final stale = <String>[];
    for (final path in _pending) {
      final file = File(path);
      if (!file.existsSync()) {
        stale.add('$path (missing)');
        continue;
      }
      final imports = _import
          .allMatches(file.readAsStringSync())
          .map((m) => _resolve(path, m.group(1)!))
          .whereType<String>();
      if (!imports.any(_inPresentation)) stale.add(path);
    }
    expect(stale, isEmpty, reason: 'Remove these from _pending:\n$stale');
  });
}
