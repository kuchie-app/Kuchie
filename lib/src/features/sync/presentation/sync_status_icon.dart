import 'dart:math' as math;

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../utils/motion/reduce_motion.dart';
import '../../local_collection/presentation/local_ui.dart';
import '../controller/sync_controller.dart';
import '../domain/diagram/sync_methods.dart';
import '../domain/diagram/sync_scene.dart';
import '../domain/sync_status.dart';
import 'sync_hero_card.dart';

/// The More row's subtitle: "Off", "Suwayomi · 2 minutes ago", "Waiting for
/// the server" or "Sign in again" (design 3.2).
String syncSummary(BuildContext context, SyncOverview overview) {
  final name = overview.methodSpec.kind == SyncMethodKind.suwayomi
      ? 'Suwayomi'
      : syncCopy(context, overview.methodSpec.name);
  return switch (overview.status) {
    SyncOff() => localText(context, 'Off', 'Mati'),
    SyncIdle(:final lastSuccessAt?) =>
      '$name · ${syncAgo(context, lastSuccessAt)}',
    SyncIdle() => name,
    SyncInProgress() ||
    SyncPending() => localText(context, 'Syncing…', 'Menyinkronkan…'),
    SyncWaitingForServer() => localText(
      context,
      'Waiting for the server',
      'Menunggu server',
    ),
    SyncActionNeeded() => localText(
      context,
      'Sign in again',
      'Perlu masuk lagi',
    ),
  };
}

/// What VoiceOver reads for the Library icon, such as "Synced with Suwayomi,
/// 2 minutes ago".
String syncIconLabel(BuildContext context, SyncScene scene) {
  final name = scene.method.kind == SyncMethodKind.suwayomi
      ? 'Suwayomi'
      : syncCopy(context, scene.method.name);
  final base = switch (scene.spec.icon) {
    SyncIconKind.check => localText(
      context,
      'Synced with $name',
      'Tersinkron dengan $name',
    ),
    SyncIconKind.spin => localText(
      context,
      'Syncing with $name',
      'Menyinkronkan dengan $name',
    ),
    SyncIconKind.wait => localText(
      context,
      'Waiting for $name',
      'Menunggu $name',
    ),
    SyncIconKind.alert => localText(
      context,
      '$name needs you to sign in again',
      '$name perlu masuk lagi',
    ),
    SyncIconKind.none => '',
  };
  return switch (scene.detail) {
    AgoDetail(:final at) => '$base, ${syncAgo(context, at)}',
    _ => base,
  };
}

/// The small cloud beside the Library title (design 3.1). Nothing when
/// sync is off. Tapping it opens the Sync page.
class SyncStatusIcon extends ConsumerWidget {
  const SyncStatusIcon({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scene = ref.watch(syncControllerProvider).scene();
    final kind = scene.spec.icon;
    if (kind == SyncIconKind.none) return const SizedBox.shrink();
    return IconButton(
      tooltip: syncIconLabel(context, scene),
      onPressed: onPressed,
      icon: SyncCloudIcon(kind: kind),
    );
  }
}

/// A cloud with a check, turning arrows, a grey dot or a red mark.
class SyncCloudIcon extends StatefulWidget {
  const SyncCloudIcon({super.key, required this.kind, this.size = 26});

  final SyncIconKind kind;
  final double size;

  @override
  State<SyncCloudIcon> createState() => _SyncCloudIconState();
}

class _SyncCloudIconState extends State<SyncCloudIcon>
    with SingleTickerProviderStateMixin {
  late final _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  void _update() {
    if (widget.kind == SyncIconKind.spin && !context.reduceMotion) {
      if (!_spin.isAnimating) _spin.repeat();
    } else {
      _spin
        ..stop()
        ..value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _update();
  }

  @override
  void didUpdateWidget(SyncCloudIcon old) {
    super.didUpdateWidget(old);
    _update();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (widget.kind) {
      SyncIconKind.wait => scheme.onSurfaceVariant,
      SyncIconKind.alert => scheme.error,
      _ => scheme.primary,
    };
    return SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: _spin,
        builder: (context, _) => CustomPaint(
          painter: _CloudPainter(widget.kind, color, _spin.value),
        ),
      ),
    );
  }
}

class _CloudPainter extends CustomPainter {
  _CloudPainter(this.kind, this.color, this.turn);

  final SyncIconKind kind;
  final Color color;
  final double turn;

  @override
  void paint(Canvas canvas, Size size) {
    // Drawn on a 27 × 27 grid, like the prototype's icon.
    canvas.scale(size.width / 27, size.height / 27);
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final cloud = Path()
      ..moveTo(7.5, 20)
      ..lineTo(19.5, 20)
      ..arcToPoint(
        const Offset(20.1, 11.04),
        radius: const Radius.circular(4.5),
        clockwise: false,
      )
      ..arcToPoint(
        const Offset(7.6, 9.5),
        radius: const Radius.circular(6.5),
        clockwise: false,
      )
      ..arcToPoint(
        const Offset(7.5, 20),
        radius: const Radius.circular(5.25),
        clockwise: false,
      )
      ..close();
    canvas.drawPath(cloud, line);
    switch (kind) {
      case SyncIconKind.check:
        canvas.drawPath(
          Path()
            ..moveTo(10.5, 14.5)
            ..lineTo(12.7, 16.7)
            ..lineTo(17, 12.1),
          line,
        );
      case SyncIconKind.spin:
        canvas.save();
        canvas.translate(13.2, 14);
        canvas.rotate(turn * 2 * math.pi);
        final arrows = Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round;
        final rect = Rect.fromCircle(center: Offset.zero, radius: 3.4);
        canvas.drawArc(rect, math.pi, math.pi * .75, false, arrows);
        canvas.drawArc(rect, 0, math.pi * .75, false, arrows);
        canvas.restore();
      case SyncIconKind.wait:
        canvas.drawCircle(const Offset(13.5, 15), 1.6, Paint()..color = color);
      case SyncIconKind.alert:
        canvas.drawLine(
          const Offset(13.5, 11.5),
          const Offset(13.5, 14.7),
          line..strokeWidth = 1.9,
        );
        canvas.drawCircle(
          const Offset(13.5, 17.3),
          1.1,
          Paint()..color = color,
        );
      case SyncIconKind.none:
        break;
    }
  }

  @override
  bool shouldRepaint(_CloudPainter old) =>
      old.kind != kind || old.color != color || old.turn != turn;
}
