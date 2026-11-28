import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../utils/motion/reduce_motion.dart';
import '../../../local_collection/presentation/local_ui.dart';
import '../../domain/diagram/sync_methods.dart';
import '../../domain/diagram/sync_scene.dart';
import 'sync_diagram_motion.dart';
import 'sync_diagram_painter.dart';

/// The live diagram of one sync method in one status (design 3.9).
///
/// One ticker drives it. Statuses with moving data run at the display's
/// rate; quiet ones are capped near 30 fps. Reduce Motion draws a still
/// frame with arrows, and Low Power Mode stops the ambient motion once a
/// change has settled. TickerMode stops it while the page is covered.
class SyncDiagram extends StatefulWidget {
  const SyncDiagram({
    super.key,
    required this.scene,
    this.showLabels = true,
    this.lowPower = false,
  });

  final SyncScene scene;

  /// Node captions; hidden during the explainer.
  final bool showLabels;
  final bool lowPower;

  @override
  State<SyncDiagram> createState() => _SyncDiagramState();
}

class _SyncDiagramState extends State<SyncDiagram>
    with SingleTickerProviderStateMixin {
  late final DiagramMotion _motion;
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;
  double _sincePaint = 0;
  bool _reduce = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _motion = DiagramMotion(widget.scene, reduce: false)
      ..ambient = !widget.lowPower;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = context.reduceMotion;
    _motion.reduce = _reduce;
    _started = true;
    _schedule();
  }

  @override
  void didUpdateWidget(SyncDiagram old) {
    super.didUpdateWidget(old);
    _motion.show(widget.scene);
    _motion.ambient = !widget.lowPower;
    _schedule();
  }

  /// Whether frames are needed at all.
  bool get _animating =>
      !_reduce && (_motion.ambient || _motion.busy || _motion.settling);

  void _schedule() {
    if (!_started) return;
    if (_animating && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    } else if (!_animating && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _tick(Duration elapsed) {
    final dt = _last == Duration.zero
        ? 0.0
        : (elapsed - _last).inMicroseconds / Duration.microsecondsPerSecond;
    _last = elapsed;
    _sincePaint += dt;
    // Quiet statuses only need about 30 frames a second.
    if (!_motion.busy && !_motion.settling && _sincePaint < 1 / 30) return;
    _motion.step(_sincePaint);
    _sincePaint = 0;
    if (!_animating) _ticker.stop();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = DiagramColors.of(Theme.of(context));
    return SizedBox(
      height: diagramHeight,
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: SyncDiagramPainter(motion: _motion, colors: colors),
                ),
              ),
            ),
            if (widget.showLabels)
              ValueListenableBuilder(
                valueListenable: _motion.captions,
                builder: (context, captions, _) => _Labels(
                  method: widget.scene.method,
                  width: constraints.maxWidth,
                  hubSub: captions.$1,
                  phoneSub: captions.$2,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Labels extends StatelessWidget {
  const _Labels({
    required this.method,
    required this.width,
    required this.hubSub,
    required this.phoneSub,
  });

  final SyncMethodSpec method;
  final double width;
  final SyncCopy? hubSub;
  final SyncCopy phoneSub;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.onSurface,
      height: 1.2,
    );
    final sub = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
      height: 1.2,
    );
    String text(SyncCopy copy) => localText(context, copy.en, copy.id);
    const labelWidth = 116.0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (final node in method.nodes)
          Builder(
            builder: (context) {
              final (_, hh) = nodeHalfSize[node.kind]!;
              final double top;
              if (node.kind == NodeKind.source) {
                top = node.y - 40;
              } else if (node.y < 110 && node.id != 'phone') {
                top = node.y - hh - 38;
              } else {
                top = node.y + hh + (node.isRound ? 12 : 8);
              }
              final caption = switch (node.id) {
                'phone' => phoneSub,
                'hub' => hubSub ?? node.sub,
                _ => node.sub,
              };
              return Positioned(
                left: node.x * width - labelWidth / 2,
                top: top,
                width: labelWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      text(node.label),
                      style: title,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (caption != null && node.kind != NodeKind.source)
                      Text(
                        text(caption),
                        style: sub,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}
