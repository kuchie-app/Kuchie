import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuchie/src/constants/app_theme.dart';
import 'package:kuchie/src/features/sync/domain/diagram/sync_methods.dart';
import 'package:kuchie/src/features/sync/domain/diagram/sync_scene.dart';
import 'package:kuchie/src/features/sync/presentation/diagram/sync_diagram.dart';
import 'package:kuchie/src/utils/theme/app_theme_builder.dart';
import 'package:material_ui/material_ui.dart';

/// Goldens are recorded on macOS. Linux antialiases paths and text a few
/// percent differently, so they run only on macOS: locally, and in CI's
/// macOS job.
final _recordedHere = Platform.isMacOS;

/// Allows the small antialiasing differences between Macs.
class _TolerantComparator extends LocalFileComparator {
  _TolerantComparator(super.testFile);

  static const tolerance = .005;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (result.passed || result.diffPercent <= tolerance) {
      result.dispose();
      return true;
    }
    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}

ThemeData _theme(String name) => buildAppTheme(
  theme: AppTheme.indigoNight,
  brightness: name == 'light' ? Brightness.light : Brightness.dark,
  customSeed: const Color(0xFF7C7BFF),
  amoled: name == 'black',
);

/// Seven methods in their main statuses, and Suwayomi's own five.
final _scenes = <(SyncMethodSpec, SyncStatusKind)>[
  (localMethod, SyncStatusKind.local),
  for (final method in [
    suwayomiMethod,
    icloudMethod,
    syncyomiMethod,
    kosyncMethod,
    komgaMethod,
    driveMethod,
  ])
    for (final status in [
      SyncStatusKind.syncing,
      SyncStatusKind.synced,
      SyncStatusKind.waiting,
    ])
      (method, status),
  for (final status in [
    SyncStatusKind.analyzing,
    SyncStatusKind.action,
    SyncStatusKind.serverDownload,
    SyncStatusKind.moveToServer,
    SyncStatusKind.saveOffline,
  ])
    (suwayomiMethod, status),
];

void main() {
  setUpAll(() {
    final base = (goldenFileComparator as LocalFileComparator).basedir;
    goldenFileComparator = _TolerantComparator(
      base.resolve('sync_diagram_golden_test.dart'),
    );
  });

  for (final themeName in ['light', 'dark', 'black']) {
    for (final (method, status) in _scenes) {
      final name = '${method.kind.name}_${status.name}_$themeName';
      testWidgets(name, skip: !_recordedHere, (tester) async {
        tester.view.physicalSize = const Size(360, 262);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final theme = _theme(themeName);
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme,
            home: Material(
              color: theme.colorScheme.surfaceContainerLow,
              child: Align(
                alignment: Alignment.topCenter,
                child: RepaintBoundary(
                  key: const ValueKey('diagram'),
                  child: ColoredBox(
                    color: theme.colorScheme.surfaceContainerLow,
                    child: SyncDiagram(scene: sceneFor(method, status)),
                  ),
                ),
              ),
            ),
          ),
        );
        // Freeze the clock at 1.5 seconds, one 50 ms frame at a time.
        for (var i = 0; i < 31; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        await expectLater(
          find.byKey(const ValueKey('diagram')),
          matchesGoldenFile('goldens/$name.png'),
        );
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
