// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:material_ui/material_ui.dart';

import '../utils/motion/reduce_motion.dart';

/// How long progress may stand still before the loader shows it is still
/// working.
const kBrushLoaderStall = Duration(milliseconds: 1200);

/// The Kuchie scarf drawn as one brush line that follows [progress]. When
/// progress is unknown or stops moving, a short stroke keeps travelling
/// along the mark so the wait never looks frozen.
///
/// Muted on purpose: [color] (the reader's text colour by default) at low
/// opacity, so the page stays the focus.
class KuchieBrushLoader extends StatefulWidget {
  const KuchieBrushLoader({
    super.key,
    this.progress,
    this.size = 44,
    this.color,
  });

  /// From 0 to 1, or null when the size of the download is unknown.
  final double? progress;
  final double size;
  final Color? color;

  @override
  State<KuchieBrushLoader> createState() => _KuchieBrushLoaderState();
}

class _KuchieBrushLoaderState extends State<KuchieBrushLoader>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );
  final _sinceChange = Stopwatch()..start();
  double _shown = 0;

  @override
  void initState() {
    super.initState();
    _shown = widget.progress?.clamp(0.0, 1.0) ?? 0;
    _motion.addListener(_ease);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.reduceMotion) {
      _motion.stop();
    } else if (!_motion.isAnimating) {
      _motion.repeat();
    }
  }

  @override
  void didUpdateWidget(KuchieBrushLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.progress != oldWidget.progress) _sinceChange.reset();
    if (context.reduceMotion) _shown = widget.progress?.clamp(0.0, 1.0) ?? 0;
  }

  /// Glides the drawn line towards the latest progress.
  void _ease() {
    final target = widget.progress?.clamp(0.0, 1.0) ?? 0;
    _shown += (target - _shown) * .18;
  }

  bool get _stalled =>
      widget.progress == null || _sinceChange.elapsed > kBrushLoaderStall;

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.onSurface;
    final reduce = context.reduceMotion;
    return RepaintBoundary(
      child: SizedBox(
        width: widget.size,
        height: widget.size * _BrushPainter.aspect,
        child: AnimatedBuilder(
          animation: _motion,
          builder: (context, _) => CustomPaint(
            painter: _BrushPainter(
              progress: _shown,
              phase: _motion.value,
              travelling: !reduce && _stalled,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

class _BrushPainter extends CustomPainter {
  _BrushPainter({
    required this.progress,
    required this.phase,
    required this.travelling,
    required this.color,
  });

  final double progress;
  final double phase;
  final bool travelling;
  final Color color;

  /// The mark's drawing box (x 18–112, y 22–102), from the app icon.
  static const _box = Rect.fromLTWH(18, 22, 94, 80);
  static double get aspect => _box.height / _box.width;

  static final Path _mark = Path()
    ..moveTo(23, 92)
    ..cubicTo(37, 80, 41, 63, 51, 50)
    ..cubicTo(64, 32, 82, 27, 105, 26)
    ..lineTo(94, 40)
    ..lineTo(107, 51)
    ..cubicTo(88, 51, 77, 56, 67, 68)
    ..cubicTo(58, 79, 54, 91, 42, 100)
    ..lineTo(40, 87)
    ..close();

  static final PathMetric _metric = _mark.computeMetrics().first;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / _box.width;
    canvas
      ..save()
      ..scale(scale)
      ..translate(-_box.left, -_box.top);
    Paint stroke(double alpha, double width) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width / scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color.withValues(alpha: alpha);

    final length = _metric.length;
    canvas.drawPath(_mark, stroke(.08, 1.4));
    if (progress > 0) {
      canvas.drawPath(
        _metric.extractPath(0, length * progress),
        stroke(.42, 1.8),
      );
    }
    if (travelling) {
      // A short stroke runs along the mark, eased so it never looks stuck.
      final segment = length * .22;
      final head = length * Curves.easeInOut.transform(phase);
      final paint = stroke(.5, 1.8);
      final start = head - segment;
      if (start >= 0) {
        canvas.drawPath(_metric.extractPath(start, head), paint);
      } else {
        canvas
          ..drawPath(_metric.extractPath(0, head), paint)
          ..drawPath(
            _metric.extractPath(math.max(0, length + start), length),
            paint,
          );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BrushPainter old) =>
      old.progress != progress ||
      old.phase != phase ||
      old.travelling != travelling ||
      old.color != color;
}
