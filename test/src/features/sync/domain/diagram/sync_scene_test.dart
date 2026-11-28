import 'package:flutter_test/flutter_test.dart';
import 'package:kuchie/src/features/sync/domain/diagram/sync_methods.dart';
import 'package:kuchie/src/features/sync/domain/diagram/sync_scene.dart';

void main() {
  bool linked(SyncMethodSpec method, String a, String b) => method.links.any(
    (link) => (link.a == a && link.b == b) || (link.a == b && link.b == a),
  );

  group('every method in every status it has', () {
    for (final method in syncMethods.values) {
      for (final status in method.statuses) {
        test('${method.kind.name} · ${status.name}', () {
          final scene = sceneFor(method, status);
          expect(scene.method, same(method));
          expect(scene.status, status);
          for (final flow in scene.flows) {
            expect(
              linked(method, flow.from, flow.to),
              isTrue,
              reason: '${flow.route} has no line',
            );
          }
          for (final link in method.links) {
            expect(method.node(link.a), isNotNull, reason: link.a);
            expect(method.node(link.b), isNotNull, reason: link.b);
          }
          expect(scene.copy.status.en, isNotEmpty);
          expect(scene.copy.status.id, isNotEmpty);
          expect(scene.copy.explain.en, isNotEmpty);
          expect(scene.copy.explain.id, isNotEmpty);
          for (final t in [0.0, .7, 1.5, 4.2, 9.9]) {
            final screens = screensFor(scene, (t * 5).floor(), t);
            for (final node in method.nodes) {
              final screen = screens.screen(node.id);
              expect(screen.progress, inInclusiveRange(0, 1), reason: node.id);
            }
          }
        });
      }
    }
  });

  test('every method has a name, a description, nodes and a legend', () {
    expect(syncMethods.keys, SyncMethodKind.values);
    for (final method in syncMethods.values) {
      expect(method.name.en, isNotEmpty);
      expect(method.description.id, isNotEmpty);
      expect(method.legend, isNotEmpty);
      expect(method.node('phone'), isNotNull);
      expect(method.node('hub'), isNotNull);
      expect(method.statuses, contains(method.defaultStatus));
      expect(
        method.nodes.map((n) => n.id).toSet(),
        hasLength(method.nodes.length),
      );
    }
  });

  test('local has one status; Suwayomi has the five server-only ones', () {
    expect(localMethod.statuses, [SyncStatusKind.local]);
    expect(
      suwayomiMethod.statuses,
      containsAll([
        SyncStatusKind.analyzing,
        SyncStatusKind.action,
        SyncStatusKind.serverDownload,
        SyncStatusKind.moveToServer,
        SyncStatusKind.saveOffline,
      ]),
    );
    for (final method in syncMethods.values) {
      if (method.kind == SyncMethodKind.local) continue;
      expect(
        method.statuses,
        containsAll([
          SyncStatusKind.syncing,
          SyncStatusKind.synced,
          SyncStatusKind.waiting,
        ]),
        reason: method.kind.name,
      );
    }
  });

  test('waiting keeps reading from the source, where there is one', () {
    for (final method in syncMethods.values) {
      if (!method.statuses.contains(SyncStatusKind.waiting)) continue;
      final scene = sceneFor(method, SyncStatusKind.waiting);
      if (method.hasSourceToPhone) {
        expect(
          scene.flows.single.route,
          'source>phone',
          reason: method.kind.name,
        );
      } else {
        expect(
          scene.flows.where((flow) => flow.from == 'source'),
          isEmpty,
          reason: method.kind.name,
        );
        expect(scene.values.source, 0);
      }
      expect(scene.values.broken, 1);
    }
    expect(komgaMethod.hasSource, isFalse);
    expect(kavitaMethod.hasSource, isFalse);
  });

  test(
    'syncing moves the method\'s own data, and quiet statuses move none',
    () {
      for (final method in syncMethods.values) {
        if (!method.statuses.contains(SyncStatusKind.syncing)) continue;
        expect(
          sceneFor(method, SyncStatusKind.syncing).flows,
          method.syncFlows,
        );
        expect(sceneFor(method, SyncStatusKind.synced).flows, isEmpty);
      }
      expect(sceneFor(syncyomiMethod, SyncStatusKind.syncing).periodic, isTrue);
      expect(sceneFor(driveMethod, SyncStatusKind.syncing).periodic, isTrue);
      expect(
        sceneFor(suwayomiMethod, SyncStatusKind.syncing).periodic,
        isFalse,
      );
      expect(sceneFor(driveMethod, SyncStatusKind.synced).continuous, isFalse);
      expect(
        sceneFor(suwayomiMethod, SyncStatusKind.synced).continuous,
        isTrue,
      );
      expect(
        sceneFor(
          kosyncMethod,
          SyncStatusKind.syncing,
        ).flows.map((f) => f.token).toSet(),
        {TokenKind.mark},
      );
    },
  );

  test('the main action follows the status, and unavailable methods wait', () {
    SyncCta cta(SyncMethodSpec method, SyncStatusKind status) =>
        sceneFor(method, status).cta;
    expect(cta(localMethod, SyncStatusKind.local), SyncCta.connect);
    expect(cta(suwayomiMethod, SyncStatusKind.analyzing), SyncCta.checking);
    expect(cta(suwayomiMethod, SyncStatusKind.syncing), SyncCta.syncing);
    expect(cta(suwayomiMethod, SyncStatusKind.synced), SyncCta.syncNow);
    expect(cta(suwayomiMethod, SyncStatusKind.waiting), SyncCta.retry);
    expect(cta(suwayomiMethod, SyncStatusKind.action), SyncCta.signIn);
    expect(cta(suwayomiMethod, SyncStatusKind.moveToServer), SyncCta.pause);
    expect(cta(icloudMethod, SyncStatusKind.synced), SyncCta.comingSoon);
    expect(cta(icloudMethod, SyncStatusKind.syncing), SyncCta.syncing);
    expect(SyncCta.syncing.enabled, isFalse);
    expect(SyncCta.comingSoon.enabled, isFalse);
    expect(SyncCta.connect.secondary, isFalse);
    expect(SyncCta.syncNow.secondary, isTrue);
  });

  test('figures become the status detail and the screens', () {
    final at = DateTime.utc(2026, 11, 27, 10);
    expect(
      (sceneFor(
                suwayomiMethod,
                SyncStatusKind.synced,
                figures: SyncFigures(lastSuccessAt: at),
              ).detail
              as AgoDetail)
          .at,
      at,
    );
    expect(
      sceneFor(
        suwayomiMethod,
        SyncStatusKind.synced,
        figures: const SyncFigures(),
      ).detail,
      isNull,
    );
    expect(
      (sceneFor(
                suwayomiMethod,
                SyncStatusKind.waiting,
                figures: const SyncFigures(pending: 5),
              ).detail
              as PendingDetail)
          .count,
      5,
    );
    expect(
      sceneFor(
        suwayomiMethod,
        SyncStatusKind.waiting,
        figures: const SyncFigures(pending: 0),
      ).detail,
      isNull,
    );

    final syncing = sceneFor(
      suwayomiMethod,
      SyncStatusKind.syncing,
      figures: const SyncFigures(
        librarySize: 10,
        progress: SyncProgress(6, 10),
      ),
    );
    final screens = screensFor(syncing, 0, 0);
    expect(screens.screen('phone'), const NodeScreen('6/10', .6));
    expect(screens.screen('r1'), const NodeScreen('2/10', .2));
    expect(screens.screen('r2'), const NodeScreen('0/10', 0));
    expect(screens.phoneSub.en, '6/10 series');

    final waiting = screensFor(
      sceneFor(
        suwayomiMethod,
        SyncStatusKind.waiting,
        figures: const SyncFigures(pending: 2),
      ),
      0,
      0,
    );
    expect(waiting.screen('phone').text, '+2');
    expect(waiting.screen('r1').text, '?');
    expect(waiting.hubSub!.en, 'Unreachable');
  });

  test('periodic methods show the bundle or file arriving at the centre', () {
    final drive = sceneFor(driveMethod, SyncStatusKind.syncing);
    expect(screensFor(drive, 0, .5).hubSub!.en, 'Uploading file');
    expect(screensFor(drive, 0, 3).hubSub, isNull);
    final bundle = sceneFor(syncyomiMethod, SyncStatusKind.syncing);
    expect(screensFor(bundle, 0, .5).hubSub!.id, 'Menerima paket');
  });

  test('the explainer walks local, connected and away', () {
    expect(explainerSteps.map((step) => (step.$1.kind, step.$2)), [
      (SyncMethodKind.local, SyncStatusKind.local),
      (SyncMethodKind.suwayomi, SyncStatusKind.syncing),
      (SyncMethodKind.suwayomi, SyncStatusKind.waiting),
    ]);
  });

  test('values ease towards their target', () {
    const from = SceneValues(hub: 0, check: 0);
    const to = SceneValues(hub: 1, check: 1);
    final half = from.approach(to, .5);
    expect(half.hub, .5);
    expect(half.check, .5);
    expect(from.approach(to, 1), to);
  });
}
