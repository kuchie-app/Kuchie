import 'dart:math' as math;
import 'dart:ui';

import '../../domain/diagram/sync_methods.dart';

/// A point on a path, with the unit normal to its left.
typedef PathPoint = ({Offset at, Offset normal});

/// A curve sampled into points with cumulative lengths, so tokens can move
/// along it at a constant speed.
class SyncPath {
  SyncPath(this.points) : assert(points.length >= 2) {
    var total = 0.0;
    lengths.add(0);
    for (var i = 1; i < points.length; i++) {
      total += (points[i] - points[i - 1]).distance;
      lengths.add(total);
    }
  }

  final List<Offset> points;
  final lengths = <double>[];

  double get length => lengths.last;

  SyncPath get reversed => SyncPath(points.reversed.toList());

  /// The point [u] of the way along, by arc length.
  PathPoint at(double u) {
    final target = u.clamp(0.0, 1.0) * length;
    var i = 1;
    while (i < lengths.length - 1 && lengths[i] < target) {
      i++;
    }
    final segment = lengths[i] - lengths[i - 1];
    final k = segment == 0 ? 0.0 : (target - lengths[i - 1]) / segment;
    final a = points[i - 1], b = points[i];
    final tangent = b - a;
    final norm = tangent.distance == 0 ? 1.0 : tangent.distance;
    return (
      at: a + tangent * k,
      normal: Offset(-tangent.dy / norm, tangent.dx / norm),
    );
  }
}

/// Samples a cubic bezier into [samples] + 1 points.
List<Offset> cubicBezier(
  Offset p0,
  Offset c1,
  Offset c2,
  Offset p1, {
  int samples = 48,
}) => [
  for (var i = 0; i <= samples; i++)
    () {
      final u = i / samples, v = 1 - u;
      return p0 * (v * v * v) +
          c1 * (3 * v * v * u) +
          c2 * (3 * v * u * u) +
          p1 * (u * u * u);
    }(),
];

/// The centre of [node] in a diagram [width] wide. A Mac's screen sits above
/// its stand.
Offset nodeCenter(DiagramNode node, double width) =>
    Offset(node.x * width, node.y - (node.kind == NodeKind.mac ? 4 : 0));

/// Where a line from [node] towards [toward] leaves its outline, 3 px out.
Offset nodeAnchor(DiagramNode node, Offset toward, double width) {
  final c = nodeCenter(node, width);
  final (hw, hh) = nodeHalfSize[node.kind]!;
  final d = toward - c;
  final l = d.distance == 0 ? 1.0 : d.distance;
  final unit = d / l;
  if (node.isRound) {
    return c + Offset(unit.dx * (hw + 3), unit.dy * (hh + 3));
  }
  final s = math.min(
    hw / math.max(d.dx.abs(), 1e-6),
    hh / math.max(d.dy.abs(), 1e-6),
  );
  return c + d * s + unit * 3;
}

/// Every line of [method] in both directions, keyed `a>b`.
Map<String, SyncPath> buildPaths(SyncMethodSpec method, double width) {
  final paths = <String, SyncPath>{};
  for (final link in method.links) {
    final a = method.node(link.a)!, b = method.node(link.b)!;
    final ca = nodeCenter(a, width), cb = nodeCenter(b, width);
    final p0 = nodeAnchor(a, cb, width), p1 = nodeAnchor(b, ca, width);
    final d = p1 - p0;
    final l = d.distance == 0 ? 1.0 : d.distance;
    final normal = Offset(-d.dy / l, d.dx / l);
    Offset lerp(double k) => p0 + d * k;
    final Offset c1, c2;
    if (link.role == LinkRole.source ||
        link.role == LinkRole.source2 ||
        link.role == LinkRole.sourceOther) {
      // An arc bowing upwards.
      final bend = (p1.dx < p0.dx ? 1 : -1) * 22.0;
      c1 = lerp(.3) + normal * bend;
      c2 = lerp(.7) + normal * bend;
    } else {
      // A gentle S.
      c1 = lerp(.35) + normal * 16;
      c2 = lerp(.65) - normal * 16;
    }
    final path = SyncPath(cubicBezier(p0, c1, c2, p1));
    paths['${link.a}>${link.b}'] = path;
    paths['${link.b}>${link.a}'] = path.reversed;
  }
  return paths;
}
