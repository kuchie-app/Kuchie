import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../domain/diagram/sync_methods.dart';
import '../../domain/diagram/sync_scene.dart';
import 'sync_diagram_motion.dart';
import 'sync_paths.dart';

/// Theme colours the diagram draws with.
class DiagramColors {
  const DiagramColors({
    required this.node,
    required this.accent,
    required this.accent2,
    required this.muted,
    required this.danger,
    required this.surface,
    required this.foreground,
    required this.onAccent,
  });

  factory DiagramColors.of(ThemeData theme) {
    final scheme = theme.colorScheme;
    return DiagramColors(
      node: Color.lerp(scheme.onSurface, scheme.primary, .18)!,
      accent: scheme.primary,
      accent2: scheme.tertiary,
      muted: scheme.onSurfaceVariant,
      danger: scheme.error,
      surface: scheme.surface,
      foreground: scheme.onSurface,
      onAccent: scheme.onPrimary,
    );
  }

  final Color node,
      accent,
      accent2,
      muted,
      danger,
      surface,
      foreground,
      onAccent;

  @override
  bool operator ==(Object other) =>
      other is DiagramColors &&
      other.node == node &&
      other.accent == accent &&
      other.accent2 == accent2 &&
      other.muted == muted &&
      other.danger == danger &&
      other.surface == surface &&
      other.foreground == foreground &&
      other.onAccent == onAccent;

  @override
  int get hashCode => Object.hash(
    node,
    accent,
    accent2,
    muted,
    danger,
    surface,
    foreground,
    onAccent,
  );
}

Color _a(Color color, double alpha) =>
    color.withValues(alpha: color.a * alpha.clamp(0.0, 1.0));

/// Draws the diagram from [motion]: backdrop, lines, nodes, tokens.
/// Node labels are widgets on top, so they follow Dynamic Type.
class SyncDiagramPainter extends CustomPainter {
  SyncDiagramPainter({required this.motion, required this.colors})
    : super(repaint: motion);

  final DiagramMotion motion;
  final DiagramColors colors;

  SyncMethodSpec? _pathsMethod;
  double _pathsWidth = -1;
  Map<String, SyncPath> _paths = const {};

  Map<String, SyncPath> _pathsFor(SyncMethodSpec method, double width) {
    if (!identical(method, _pathsMethod) || width != _pathsWidth) {
      _paths = buildPaths(method, width);
      _pathsMethod = method;
      _pathsWidth = width;
    }
    return _paths;
  }

  @override
  void paint(Canvas canvas, Size size) {
    _Frame(
      canvas: canvas,
      size: size,
      motion: motion,
      c: colors,
      paths: _pathsFor(motion.scene.method, size.width),
    ).draw();
  }

  @override
  bool shouldRepaint(SyncDiagramPainter old) =>
      old.motion != motion || old.colors != colors;
}

class _Frame {
  _Frame({
    required this.canvas,
    required this.size,
    required this.motion,
    required this.c,
    required this.paths,
  }) : scene = motion.scene,
       v = motion.values,
       reduce = motion.reduce,
       still = motion.reduce || !motion.ambient;

  final Canvas canvas;
  final Size size;
  final DiagramMotion motion;
  final DiagramColors c;
  final Map<String, SyncPath> paths;
  final SyncScene scene;
  final SceneValues v;
  final bool reduce;

  /// No ambient motion: Reduce Motion or Low Power Mode.
  final bool still;

  double get t => motion.t;
  double get sceneT => motion.sceneT;
  double get width => size.width;

  Paint _fill(Color color) => Paint()..color = color;

  /// A layer paint; saveLayer uses only its alpha.
  Paint _opacity(double alpha) =>
      Paint()..color = c.foreground.withValues(alpha: alpha.clamp(0.0, 1.0));
  Paint _pen(Color color, double width) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  RRect _rr(double x, double y, double w, double h, double r) =>
      RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(r));

  void draw() {
    _backdrop();
    canvas.saveLayer(Offset.zero & size, _opacity(motion.topologyFade));
    for (final link in scene.method.links) {
      _strokeLink(paths['${link.a}>${link.b}'], link.role);
    }
    var deviceIndex = 1;
    final nodes = scene.method.nodes;
    for (var i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      final floats =
          node.kind != NodeKind.source &&
          node.kind != NodeKind.hub &&
          node.kind != NodeKind.ghost;
      canvas.save();
      if (floats && !still) {
        canvas.translate(0, math.sin(t * 1.3 + i * 1.3) * 2);
      }
      switch (node.kind) {
        case NodeKind.source:
          _globe(node);
        case NodeKind.hub || NodeKind.ghost:
          _hub(node);
        case NodeKind.phone:
          _phone(node, motion.screens.screen('phone'));
        default:
          _device(node, motion.screens.screen(node.id), deviceIndex++);
      }
      canvas.restore();
    }
    _flows();
    _pulses();
    canvas.restore();
  }

  // ---------- Backdrop and lines ----------

  void _backdrop() {
    const step = 18.0;
    final offset = still ? 0.0 : (t * 5) % step;
    final paint = _fill(_a(c.node, .07));
    for (var y = 8.0; y < size.height; y += step) {
      for (var x = -step + offset; x < width + step; x += step) {
        canvas.drawCircle(Offset(x, y), 1, paint);
      }
    }
  }

  void _strokePoints(
    List<Offset> points,
    int last,
    int gapFrom,
    int gapTo,
    Paint paint, {
    List<double>? dash,
    double dashOffset = 0,
  }) {
    final path = Path();
    var pen = false;
    for (var i = 0; i <= last; i++) {
      if (i > gapFrom && i < gapTo) {
        pen = false;
        continue;
      }
      final q = points[i];
      if (!pen) {
        path.moveTo(q.dx, q.dy);
        pen = true;
      } else {
        path.lineTo(q.dx, q.dy);
      }
    }
    canvas.drawPath(
      dash == null ? path : _dashed(path, dash, dashOffset),
      paint,
    );
  }

  Path _dashed(Path source, List<double> pattern, double offset) {
    final out = Path();
    final period = pattern.fold<double>(0, (a, b) => a + b);
    for (final metric in source.computeMetrics()) {
      var distance = -(offset % period);
      var index = 0;
      while (distance < metric.length) {
        final length = pattern[index % pattern.length];
        if (index.isEven) {
          final start = math.max(0.0, distance);
          final end = math.min(metric.length, distance + length);
          if (end > start) {
            out.addPath(metric.extractPath(start, end), Offset.zero);
          }
        }
        distance += length;
        index++;
      }
    }
    return out;
  }

  void _stroke(
    SyncPath? path, {
    required double width,
    required Color color,
    required double alpha,
    double dash = 0,
    double march = 0,
    double progress = 1,
    double broken = 0,
  }) {
    if (path == null || alpha <= .01 || progress <= 0) return;
    final points = path.points, n = points.length;
    final last = math.min(n - 1, math.max(1, ((n - 1) * progress).round()));
    final gapFrom = broken > .05 ? (n * (.5 - .14 * broken)).floor() : n;
    final gapTo = broken > .05 ? (n * (.5 + .14 * broken)).ceil() : n;
    if (march != 0 && dash <= .01) {
      _strokePoints(
        points,
        last,
        gapFrom,
        gapTo,
        _stroke0(color, alpha * .22, width + 2),
      );
    }
    final paint = _stroke0(color, alpha, width);
    if (dash > .01) {
      _strokePoints(
        points,
        last,
        gapFrom,
        gapTo,
        paint,
        dash: [3, 5 + 3 * dash],
      );
    } else if (march != 0) {
      _strokePoints(
        points,
        last,
        gapFrom,
        gapTo,
        paint,
        dash: [2, 7],
        dashOffset: -motion.march * march.sign,
      );
    } else {
      _strokePoints(points, last, gapFrom, gapTo, paint);
    }
    if (broken > .5) {
      final tick = _stroke0(color, alpha, 1.6);
      for (final i in [gapFrom, gapTo]) {
        if (i >= n) continue;
        final m = points[i];
        canvas.drawLine(m + const Offset(-3, -5), m + const Offset(3, 5), tick);
      }
    }
  }

  Paint _stroke0(Color color, double alpha, double width) =>
      _pen(_a(color, alpha), width);

  void _strokeLink(SyncPath? path, LinkRole role) {
    final lineColor = v.dashed > .5 ? c.muted : c.accent;
    final march = reduce ? 0.0 : scene.spec.march;
    final drawOn = motion.drawOn;
    switch (role) {
      case LinkRole.sync:
        _stroke(
          path,
          width: 3,
          color: lineColor,
          alpha: v.sync,
          dash: v.dashed,
          march: march,
          progress: scene.spec.drawOn ? math.min(1, drawOn * 1.6) : 1,
          broken: v.broken,
        );
      case LinkRole.fan:
        _stroke(
          path,
          width: 2.4,
          color: lineColor,
          alpha: v.fan,
          dash: v.dashed,
          march: march,
          progress: scene.spec.drawOn ? math.max(0, drawOn * 2 - 1) : 1,
        );
      case LinkRole.ghost:
        _stroke(path, width: 2, color: c.muted, alpha: .45, dash: 1);
      case LinkRole.source:
        final hot = v.sourceHot > .5;
        _stroke(
          path,
          width: 1.8,
          color: hot ? c.accent2 : c.muted,
          alpha: math.max(v.source, v.source > .01 ? .18 : 0),
          march: hot && !reduce ? 24 : 0,
        );
      case LinkRole.source2:
        final hot = v.source2 > .7;
        _stroke(
          path,
          width: 1.8,
          color: hot ? c.accent2 : c.muted,
          alpha: math.max(v.source2 * (1 - v.broken), .1),
          dash: v.dashed,
          march: hot && !reduce ? 24 : 0,
        );
      case LinkRole.sourceOther:
        _stroke(
          path,
          width: 1.4,
          color: c.muted,
          alpha: .28 * math.max(v.others, .3),
          dash: .6,
        );
    }
  }

  // ---------- Node parts ----------

  void _text(double x, double y, String text, Color color, [double size = 11]) {
    if (text.isEmpty) return;
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout();
    painter.paint(
      canvas,
      Offset(x - painter.width / 2, y - painter.height / 2),
    );
    painter.dispose();
  }

  void _bar(double x, double y, double w, double p) {
    canvas.drawRRect(_rr(x, y, w, 4, 2), _fill(_a(c.node, .2)));
    if (p > 0) {
      canvas.drawRRect(_rr(x, y, w * math.min(1, p), 4, 2), _fill(c.accent));
    }
  }

  void _badge(double x, double y, int index) {
    final s = v.check * motion.checkPop[index.clamp(0, 3)];
    if (s <= .01) return;
    canvas.save();
    canvas.translate(x, y);
    canvas.scale(s, s);
    canvas.drawCircle(Offset.zero, 8.5, _fill(c.accent));
    canvas.drawPath(
      Path()
        ..moveTo(-3.8, 0)
        ..lineTo(-1, 2.8)
        ..lineTo(4, -2.8),
      _pen(c.onAccent, 2.1),
    );
    canvas.restore();
  }

  void _flash(RRect rect, double bump) {
    if (bump > .01) canvas.drawRRect(rect, _fill(_a(c.accent, .32 * bump)));
  }

  void _withBump(Offset center, double bump, void Function() draw) {
    final s = 1 + .07 * bump;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(s, s);
    canvas.translate(-center.dx, -center.dy);
    draw();
    canvas.restore();
  }

  void _frame(RRect rect, {bool dashed = false}) {
    canvas.drawRRect(rect, _fill(c.surface));
    final paint = _pen(c.node, 2.2);
    if (dashed) {
      canvas.drawPath(_dashed(Path()..addRRect(rect), const [4, 4], 0), paint);
    } else {
      canvas.drawRRect(rect, paint);
    }
  }

  void _phone(DiagramNode node, NodeScreen screen) {
    final center = nodeCenter(node, width);
    final bump = motion.bumps['phone'] ?? 0;
    _withBump(center, bump, () {
      const w = 48.0, h = 86.0;
      final x = center.dx - w / 2, y = center.dy - h / 2;
      _frame(_rr(x, y, w, h, 12));
      final inner = _rr(x + 4, y + 4, w - 8, h - 8, 9);
      canvas.drawRRect(inner, _fill(_a(c.accent, .1)));
      _flash(inner, bump);
      canvas.drawRRect(_rr(center.dx - 8, y + 6, 16, 4, 2), _fill(c.node));
      _text(
        center.dx,
        y + 21,
        screen.text,
        c.foreground,
        screen.text.length > 5 ? 9.5 : 11,
      );
      final lit = scene.status == SyncStatusKind.local
          ? 6
          : (screen.progress * 6).round();
      for (var i = 0; i < 6; i++) {
        final cx = x + 9 + (i % 3) * 11, cy = y + 32 + (i ~/ 3) * 15;
        canvas.drawRRect(
          _rr(cx, cy, 8, 11, 2),
          _fill(i < lit ? _a(c.accent, .9) : _a(c.node, .18)),
        );
      }
      _bar(x + 9, y + h - 18, w - 18, math.max(.04, screen.progress));
      canvas.drawRRect(
        _rr(center.dx - 9, y + h - 8, 18, 2.5, 1.2),
        _fill(_a(c.node, .6)),
      );
      _badge(x + w - 2, y + 2, 0);
    });
  }

  void _device(DiagramNode node, NodeScreen screen, int index) {
    final center = nodeCenter(node, width);
    final dashed = v.dashed > .3;
    final bump = motion.bumps[node.id] ?? 0;
    canvas.saveLayer(null, _opacity(math.max(v.others, .15)));
    _withBump(center, bump, () {
      switch (node.kind) {
        case NodeKind.tablet:
          const w = 66.0, h = 46.0;
          final x = center.dx - w / 2, y = center.dy - h / 2;
          _frame(_rr(x, y, w, h, 8), dashed: dashed);
          final inner = _rr(x + 4, y + 4, w - 8, h - 8, 5);
          canvas.drawRRect(inner, _fill(_a(c.accent, .1)));
          _flash(inner, bump);
          _text(center.dx, y + 19, screen.text, c.foreground, 11.5);
          _bar(x + 12, y + 31, w - 24, screen.progress);
          _badge(x + w - 2, y + 2, index);
        case NodeKind.mac:
          const w = 66.0, h = 42.0;
          final x = center.dx - w / 2, y = center.dy - h / 2 - 2;
          _frame(_rr(x, y, w, h, 6), dashed: dashed);
          final inner = _rr(x + 4, y + 4, w - 8, h - 8, 4);
          canvas.drawRRect(inner, _fill(_a(c.accent, .1)));
          _flash(inner, bump);
          _text(center.dx, y + 17, screen.text, c.foreground, 11.5);
          _bar(x + 12, y + 28, w - 24, screen.progress);
          canvas.drawRRect(_rr(center.dx - 3, y + h, 6, 7, 1), _fill(c.node));
          canvas.drawRRect(
            _rr(center.dx - 14, y + h + 7, 28, 3, 1.5),
            _fill(c.node),
          );
          _badge(x + w - 2, y + 2, index);
        case NodeKind.android:
          const w = 44.0, h = 82.0;
          final x = center.dx - w / 2, y = center.dy - h / 2;
          _frame(_rr(x, y, w, h, 9), dashed: dashed);
          final inner = _rr(x + 4, y + 4, w - 8, h - 8, 6);
          canvas.drawRRect(inner, _fill(_a(c.accent2, .1)));
          _flash(inner, bump);
          canvas.drawCircle(Offset(center.dx, y + 8), 2, _fill(c.node));
          _text(center.dx, y + 26, screen.text, c.foreground, 10.5);
          final lit = (screen.progress * 4).round();
          for (var i = 0; i < 4; i++) {
            canvas.drawRRect(
              _rr(x + 9 + (i % 2) * 14, y + 38 + (i ~/ 2) * 15, 12, 12, 2),
              _fill(i < lit ? _a(c.accent2, .85) : _a(c.node, .18)),
            );
          }
          _badge(x + w - 2, y + 2, index);
        case NodeKind.ereader:
          const w = 54.0, h = 76.0;
          final x = center.dx - w / 2, y = center.dy - h / 2;
          _frame(_rr(x, y, w, h, 7), dashed: dashed);
          final inner = _rr(x + 6, y + 6, w - 12, h - 20, 3);
          canvas.drawRRect(inner, _fill(_a(c.node, .12)));
          _flash(inner, bump);
          for (var i = 0; i < 5; i++) {
            canvas.drawRRect(
              _rr(x + 11, y + 13 + i * 6, w - 22 - (i % 2) * 8, 2, 1),
              _fill(_a(c.node, .45)),
            );
          }
          _text(center.dx, y + 50, screen.text, c.foreground, 11);
          canvas.drawRRect(
            _rr(center.dx - 8, y + h - 9, 16, 3, 1.5),
            _fill(_a(c.node, .5)),
          );
          _badge(x + w - 2, y + 2, index);
        default:
          break;
      }
    });
    canvas.restore();
  }

  void _hubGlyph(HubGlyph glyph, Offset center, Color color) {
    final line = _pen(color, 2);
    final fill = _fill(color);
    final x = center.dx, y = center.dy;
    switch (glyph) {
      case HubGlyph.cloud || HubGlyph.drive:
        final cloud = Path()
          ..moveTo(x - 11, y + 7)
          ..lineTo(x + 10, y + 7)
          ..arcTo(
            Rect.fromCircle(center: Offset(x + 9, y + 1), radius: 6),
            math.pi / 2,
            -math.pi,
            false,
          )
          ..arcTo(
            Rect.fromCircle(center: Offset(x + 1, y - 3), radius: 7.5),
            -.2,
            -(math.pi - .7),
            false,
          )
          ..arcTo(
            Rect.fromCircle(center: Offset(x - 9, y + 2), radius: 5),
            -math.pi / 2,
            -math.pi,
            false,
          )
          ..close();
        canvas.drawPath(cloud, line);
        if (glyph == HubGlyph.drive) {
          canvas.drawLine(Offset(x - 4, y + 1), Offset(x + 4, y + 1), line);
          canvas.drawLine(Offset(x - 4, y + 4), Offset(x + 2, y + 4), line);
        }
      case HubGlyph.syncyomi:
        for (var k = 0; k < 2; k++) {
          canvas.save();
          canvas.translate(x, y);
          canvas.rotate(k * math.pi);
          canvas.drawArc(
            Rect.fromCircle(center: Offset.zero, radius: 10),
            math.pi * 1.1,
            math.pi * .75,
            false,
            line,
          );
          final ex = math.cos(math.pi * 1.85) * 10,
              ey = math.sin(math.pi * 1.85) * 10;
          canvas.drawPath(
            Path()
              ..moveTo(ex - 5, ey - 1)
              ..lineTo(ex, ey)
              ..lineTo(ex + 1, ey + 5),
            line,
          );
          canvas.restore();
        }
      case HubGlyph.kosync:
        canvas.drawRRect(_rr(x - 11, y - 10, 22, 20, 3), line);
        canvas.drawPath(
          Path()
            ..moveTo(x + 2, y - 10)
            ..lineTo(x + 2, y + 1)
            ..lineTo(x + 5.5, y - 2)
            ..lineTo(x + 9, y + 1)
            ..lineTo(x + 9, y - 10)
            ..close(),
          fill,
        );
      case HubGlyph.media:
        for (final (dx, h, tilt) in const [
          (-11.0, 14.0, false),
          (-5.0, 16.0, true),
          (1.0, 12.0, false),
          (7.0, 15.0, true),
        ]) {
          canvas.save();
          canvas.translate(x + dx + 2, y + 9);
          if (tilt) canvas.rotate(-.18);
          canvas.drawRRect(_rr(-2.5, -h, 5, h, 1), line);
          canvas.restore();
        }
        canvas.drawLine(Offset(x - 13, y + 10), Offset(x + 13, y + 10), line);
      case HubGlyph.server:
        for (final (i, dy) in const [(0, -11.0), (1, 1.0)]) {
          canvas.drawRRect(_rr(x - 13, y + dy, 26, 10, 3), line);
          final on = scene.spec.leds && !reduce
              ? math.sin(t * (9 + i * 4) + i * 2) > -.1
              : v.hub > .6;
          canvas.drawCircle(
            Offset(x - 7.5, y + dy + 5),
            2,
            _fill(on ? c.accent2 : _a(c.node, .35)),
          );
          canvas.drawRRect(
            _rr(x - 2, y + dy + 4, 11, 2, 1),
            _fill(_a(c.node, .5)),
          );
        }
    }
  }

  void _hub(DiagramNode node) {
    final center = nodeCenter(node, width);
    final a = v.hub;
    const r = 28.0;
    final spec = scene.spec;
    if (node.kind == NodeKind.ghost) {
      final pulse = still ? 0.0 : (math.sin(t * 2) + 1) / 2;
      final ring = Path()..addOval(Rect.fromCircle(center: center, radius: 26));
      canvas.drawPath(
        _dashed(ring, const [4, 5], still ? 0 : -t * 6),
        _pen(_a(c.muted, .6 + .3 * pulse), 2),
      );
      final plus = _pen(c.muted, 2.4);
      canvas.drawLine(
        center + const Offset(-7, 0),
        center + const Offset(7, 0),
        plus,
      );
      canvas.drawLine(
        center + const Offset(0, -7),
        center + const Offset(0, 7),
        plus,
      );
      return;
    }
    if (spec.ripple > 0 && !still) {
      final period = spec.ripple;
      final rings = period > 2 ? 1 : 2;
      for (var k = 0; k < rings; k++) {
        final phase = ((t + k * period / 2) % period) / period;
        canvas.drawCircle(
          center,
          r + 4 + phase * 24,
          _pen(_a(c.accent, (1 - phase) * .45 * a), 1.6),
        );
      }
    }
    final dim = math.max(a, .2);
    final orbit = Path()
      ..addOval(Rect.fromCircle(center: center, radius: r + 7));
    canvas.drawPath(
      _dashed(orbit, const [2, 5], -motion.rotation * 12),
      _pen(_a(a > .6 ? c.accent : c.muted, .55 * dim), 1.4),
    );
    if (a > .6 && scene.continuous) {
      final angle = motion.rotation;
      canvas.drawCircle(
        center + Offset(math.cos(angle), math.sin(angle)) * (r + 7),
        3,
        _fill(_a(c.accent2, dim)),
      );
    }
    final bump = motion.bumps['hub'] ?? 0;
    _withBump(center, bump, () {
      final body = math.max(a, .25);
      canvas.drawCircle(center, r, _fill(_a(c.surface, body)));
      canvas.drawCircle(
        center,
        r - 3,
        _fill(_a(c.accent, (.12 + .25 * bump) * body)),
      );
      canvas.drawCircle(
        center,
        r,
        _pen(_a(a > .6 ? c.accent : c.muted, body), 2.2),
      );
      final glyph = scene.method.glyph;
      if (glyph != null) {
        _hubGlyph(glyph, center, _a(a > .6 ? c.foreground : c.muted, body));
      }
    });
    if (v.lock > .01) {
      final settle = math.min(sceneT, 1.2);
      final wobble = still
          ? 0.0
          : math.sin(settle * 14) * (1 - settle / 1.2) * .35;
      canvas.save();
      canvas.translate(center.dx + 21, center.dy - 21);
      canvas.rotate(wobble);
      canvas.drawCircle(Offset.zero, 10, _fill(_a(c.danger, v.lock)));
      canvas.drawArc(
        Rect.fromCircle(center: const Offset(0, -2.5), radius: 3.3),
        math.pi,
        math.pi,
        false,
        _pen(_a(c.surface, v.lock), 2),
      );
      canvas.drawRRect(
        _rr(-4.8, -2, 9.6, 6.6, 1.6),
        _fill(_a(c.surface, v.lock)),
      );
      canvas.restore();
    }
  }

  void _globe(DiagramNode node) {
    final center = nodeCenter(node, width);
    final sway = still ? 5.0 : 2 + (math.sin(t * .9)).abs() * 7;
    final line = _pen(c.muted, 1.6);
    canvas.drawCircle(center, 13, _fill(c.surface));
    canvas.drawCircle(center, 13, line);
    canvas.drawOval(
      Rect.fromCenter(center: center, width: sway * 2, height: 26),
      line,
    );
    canvas.drawLine(
      center + const Offset(-13, 0),
      center + const Offset(13, 0),
      line,
    );
  }

  // ---------- Tokens ----------

  void _token(TokenKind kind, Offset q, Color color, double fade, int i) {
    if (fade <= .01) return;
    canvas.saveLayer(null, _opacity(fade.clamp(0.0, 1.0)));
    final x = q.dx, y = q.dy;
    var k = kind;
    if (k == TokenKind.mix) k = i.isOdd ? TokenKind.dot : TokenKind.cover;
    switch (k) {
      case TokenKind.cover || TokenKind.dot || TokenKind.mix:
        canvas.drawRRect(_rr(x - 5, y - 7, 10, 14, 2), _fill(color));
        canvas.drawRRect(
          _rr(x - 3, y - 4.5, 6, 2, 1),
          _fill(_a(c.surface, .9)),
        );
      case TokenKind.page:
        final sheet = Path()
          ..moveTo(x - 6, y - 8)
          ..lineTo(x + 2, y - 8)
          ..lineTo(x + 6, y - 4)
          ..lineTo(x + 6, y + 8)
          ..lineTo(x - 6, y + 8)
          ..close();
        canvas.drawPath(sheet, _fill(c.surface));
        final line = _pen(color, 1.6);
        canvas.drawPath(sheet, line);
        canvas.drawLine(Offset(x - 3, y - 1), Offset(x + 3, y - 1), line);
        canvas.drawLine(Offset(x - 3, y + 3), Offset(x + 3, y + 3), line);
      case TokenKind.bundle:
        canvas.drawRRect(_rr(x - 9, y - 7, 18, 14, 3), _fill(color));
        final line = _pen(c.surface, 1.5);
        canvas.drawLine(Offset(x - 9, y - 2), Offset(x + 9, y - 2), line);
        canvas.drawLine(Offset(x, y - 7), Offset(x, y - 2), line);
      case TokenKind.mark:
        canvas.drawPath(
          Path()
            ..moveTo(x - 5, y - 8)
            ..lineTo(x + 5, y - 8)
            ..lineTo(x + 5, y + 8)
            ..lineTo(x, y + 4)
            ..lineTo(x - 5, y + 8)
            ..close(),
          _fill(c.accent2),
        );
      case TokenKind.file:
        final sheet = Path()
          ..moveTo(x - 7, y - 9)
          ..lineTo(x + 3, y - 9)
          ..lineTo(x + 7, y - 5)
          ..lineTo(x + 7, y + 9)
          ..lineTo(x - 7, y + 9)
          ..close();
        canvas.drawPath(sheet, _fill(c.surface));
        final line = _pen(color, 1.7);
        canvas.drawPath(sheet, line);
        canvas.drawPath(
          Path()
            ..moveTo(x, y + 5)
            ..lineTo(x, y - 3)
            ..moveTo(x - 3, y)
            ..lineTo(x, y - 3)
            ..lineTo(x + 3, y),
          line,
        );
    }
    canvas.restore();
  }

  void _comet(SyncPath path, double u, double lane, Color color, double fade) {
    for (var k = 3; k >= 0; k--) {
      final uu = u - k * .03;
      if (uu < 0) continue;
      final q = path.at(uu);
      canvas.drawCircle(
        q.at + q.normal * lane,
        math.max(1, 3.4 - k * .7),
        _fill(_a(color, (1 - k * .25) * fade)),
      );
    }
  }

  void _arrow(SyncPath path, double u, Color color, double lane) {
    final q = path.at(u), q2 = path.at(u + .02);
    final d = q2.at - q.at;
    final l = d.distance == 0 ? 1.0 : d.distance;
    final ux = d.dx / l, uy = d.dy / l;
    final p = q.at + q.normal * lane;
    canvas.drawPath(
      Path()
        ..moveTo(p.dx - ux * 7 - uy * 5, p.dy - uy * 7 + ux * 5)
        ..lineTo(p.dx, p.dy)
        ..lineTo(p.dx - ux * 7 + uy * 5, p.dy - uy * 7 - ux * 5),
      _pen(color, 2.2),
    );
  }

  void _flows() {
    final flows = scene.flows;
    for (var f = 0; f < flows.length; f++) {
      final flow = flows[f];
      final path = paths[flow.route];
      if (path == null) continue;
      final color = flow.from == 'source' ? c.accent2 : c.accent;
      if (reduce) {
        _arrow(
          path,
          .5,
          flow.token == TokenKind.mark ? c.accent2 : color,
          flow.lane,
        );
        continue;
      }
      if (flow.isPeriodic) {
        if (sceneT < flow.delay) continue;
        final phase = (sceneT - flow.delay) % flow.every!;
        if (phase > flow.travel!) continue;
        final u = phase / flow.travel!;
        final q = path.at(u);
        final fade =
            math.min(math.min(u / .08, (1 - u) / .08), 1.0) * motion.flowFade;
        _token(
          flow.token,
          q.at + Offset(0, math.sin(u * math.pi) * -6),
          color,
          fade,
          0,
        );
        continue;
      }
      for (var i = 0; i < flow.count; i++) {
        final u = (sceneT * flow.speed + i / flow.count) % 1;
        final edge =
            math.min(math.min(u / .1, (1 - u) / .1), 1.0) * motion.flowFade;
        if (flow.token == TokenKind.dot) {
          _comet(path, u, flow.lane, color, edge);
        } else {
          final q = path.at(u);
          final bob = still ? 0.0 : math.sin(t * 6 + u * 10) * 1.2;
          _token(
            flow.token,
            q.at + q.normal * flow.lane + Offset(0, bob),
            color,
            edge,
            i,
          );
        }
      }
    }
  }

  void _pulses() {
    final sync = paths['phone>hub'];
    if (sync == null) return;
    final spec = scene.spec;
    if (spec.scan && motion.drawOn >= 1 && !reduce) {
      _comet(sync, .5 - .5 * math.cos(sceneT * 2.2), 0, c.accent, 1);
    }
    if (spec.pulse && !still && !scene.periodic) {
      final phase = t % 6;
      if (phase < 1.2) {
        _comet(sync, phase / 1.2, 0, c.accent, math.sin(phase / 1.2 * math.pi));
      } else if (phase < 2.2) {
        final u = phase - 1.2;
        for (final id in const ['r1', 'r2', 'r']) {
          final fan = paths['hub>$id'];
          if (fan != null) _comet(fan, u, 0, c.accent, math.sin(u * math.pi));
        }
      }
    }
    if (spec.pending) {
      final dots = math.min(3, math.max(1, scene.figures.pending));
      final base = sync.at(.3).at;
      for (var i = 0; i < dots; i++) {
        final hop = reduce ? 0.0 : (math.sin(t * 3 + i * .9)).abs() * 5;
        canvas.drawCircle(
          Offset(base.dx - 8 + i * 9, base.dy - 16 - hop),
          3.3,
          _fill(c.accent),
        );
      }
    }
  }
}
