import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:kuchie/src/features/sync/domain/diagram/sync_methods.dart';
import 'package:kuchie/src/features/sync/presentation/diagram/sync_paths.dart';

void main() {
  const width = 360.0;

  test('at(u) moves forward at a constant speed along every line', () {
    for (final method in syncMethods.values) {
      final paths = buildPaths(method, width);
      for (final MapEntry(key: route, value: path) in paths.entries) {
        const steps = 40;
        final points = [for (var i = 0; i <= steps; i++) path.at(i / steps).at];
        final gaps = [
          for (var i = 1; i < points.length; i++)
            (points[i] - points[i - 1]).distance,
        ];
        final expected = path.length / steps;
        for (final gap in gaps) {
          // Chords of a curve are a little shorter than the arc.
          expect(
            gap,
            closeTo(expected, expected * .05),
            reason: '${method.kind.name} $route',
          );
        }
        expect(points.first, path.points.first);
        expect((points.last - path.points.last).distance, lessThan(1e-6));
      }
    }
  });

  test('at clamps outside 0 to 1 and gives a unit normal', () {
    final path = SyncPath(const [Offset(0, 0), Offset(10, 0), Offset(20, 0)]);
    expect(path.length, 20);
    expect(path.at(-1).at, Offset.zero);
    expect(path.at(2).at, const Offset(20, 0));
    expect(path.at(.25).at, const Offset(5, 0));
    expect(path.at(.5).normal, const Offset(0, 1));
    expect(path.reversed.at(.25).at, const Offset(15, 0));
  });

  test('lines start and end 3 px outside the node outlines', () {
    for (final method in syncMethods.values) {
      final paths = buildPaths(method, width);
      for (final link in method.links) {
        final path = paths['${link.a}>${link.b}']!;
        for (final (id, end) in [
          (link.a, path.points.first),
          (link.b, path.points.last),
        ]) {
          final node = method.node(id)!;
          final center = nodeCenter(node, width);
          final (hw, hh) = nodeHalfSize[node.kind]!;
          final d = end - center;
          if (node.isRound) {
            // An ellipse 3 px larger than the node.
            final r = math.sqrt(
              math.pow(d.dx / (hw + 3), 2) + math.pow(d.dy / (hh + 3), 2),
            );
            expect(r, closeTo(1, .02), reason: '${method.kind.name} $id');
          } else {
            final outside = math.max(d.dx.abs() - hw, d.dy.abs() - hh);
            expect(
              outside,
              inInclusiveRange(1.5, 3.01),
              reason: '${method.kind.name} $id',
            );
          }
        }
      }
    }
  });

  test('both directions of a line are the same curve', () {
    final paths = buildPaths(suwayomiMethod, width);
    final there = paths['phone>hub']!, back = paths['hub>phone']!;
    expect(there.length, closeTo(back.length, 1e-9));
    expect(there.points.first, back.points.last);
  });
}
