import 'package:material_ui/material_ui.dart';

import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/motion/reduce_motion.dart';
import '../../local_collection/presentation/local_ui.dart';
import '../domain/diagram/sync_methods.dart';
import '../domain/diagram/sync_scene.dart';
import 'diagram/sync_diagram.dart';
import 'diagram/sync_explainer.dart';

String syncCopy(BuildContext context, SyncCopy copy) =>
    localText(context, copy.en, copy.id);

/// "2 minutes ago", in the app's language.
String syncAgo(BuildContext context, DateTime at, {DateTime? now}) {
  final l10n = context.l10n;
  final elapsed = (now ?? DateTime.now()).difference(at);
  if (elapsed.inMinutes < 1) return l10n.justNow;
  if (elapsed.inHours < 1) return l10n.minutesAgo(elapsed.inMinutes);
  if (elapsed.inDays < 1) return l10n.hoursAgo(elapsed.inHours);
  return l10n.daysAgo(elapsed.inDays);
}

/// The status line: the status, then its detail, such as how long ago.
String syncStatusLine(BuildContext context, SyncScene scene, {DateTime? now}) {
  final status = syncCopy(context, scene.copy.status);
  final detail = switch (scene.detail) {
    AgoDetail(:final at) => syncAgo(context, at, now: now),
    PendingDetail(:final count) => localText(
      context,
      count == 1 ? '1 change' : '$count changes',
      '$count perubahan',
    ),
    ProgressDetail(:final progress) => localText(
      context,
      '${progress.done} of ${progress.total}',
      '${progress.done} dari ${progress.total}',
    ),
    null => null,
  };
  return detail == null ? status : '$status · $detail';
}

/// The top of the Sync page (design 3.2): method and status pills, the live
/// diagram, what syncs, one status line, one explanation and one action.
class SyncHeroCard extends StatelessWidget {
  const SyncHeroCard({
    super.key,
    required this.scene,
    required this.explainer,
    this.onPrimary,
    this.lowPower = false,
    this.stale = false,
    this.lastSuccessAt,
    this.celebrate = false,
    this.now,
  });

  final SyncScene scene;
  final SyncExplainer explainer;

  /// The main action; null leaves the button disabled.
  final VoidCallback? onPrimary;
  final bool lowPower;

  /// Waiting for the server for over a week: banner and Kiri offline.
  final bool stale;
  final DateTime? lastSuccessAt;

  /// The first sync just finished: Kiri complete.
  final bool celebrate;

  /// For tests.
  final DateTime? now;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: explainer,
    builder: (context, _) {
      final explaining = explainer.active;
      final shown = explainer.scene ?? scene;
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      final status = syncStatusLine(context, scene, now: now);
      final explain = syncCopy(context, scene.copy.explain);
      final kiri = explaining
          ? null
          : celebrate
          ? 'complete'
          : stale && scene.status == SyncStatusKind.waiting
          ? 'offline'
          : null;
      return Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: scheme.outlineVariant),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: _MethodPill(
                        icon: explaining ? null : shown.method.pill,
                        label: explaining
                            ? localText(context, 'How it works', 'Cara kerja')
                            : syncCopy(context, shown.method.name),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _StatusPill(
                      label: explaining
                          ? localText(
                              context,
                              'Explainer ${explainer.step! + 1}/${SyncExplainer.stepCount}',
                              'Penjelasan ${explainer.step! + 1}/${SyncExplainer.stepCount}',
                            )
                          : syncCopy(context, shown.spec.pill),
                      tone: shown.spec.tone,
                      still: explaining || shown.spec.still,
                    ),
                  ],
                ),
                Semantics(
                  container: true,
                  label: explaining
                      ? localText(
                          context,
                          'Step ${explainer.step! + 1} of ${SyncExplainer.stepCount}. ${syncCopy(context, explainer.caption!)}',
                          'Langkah ${explainer.step! + 1} dari ${SyncExplainer.stepCount}. ${syncCopy(context, explainer.caption!)}',
                        )
                      : '$status. $explain',
                  child: ExcludeSemantics(
                    child: SyncDiagram(
                      scene: shown,
                      showLabels: !explaining,
                      lowPower: lowPower,
                    ),
                  ),
                ),
                if (explaining) ...[
                  _Caption(
                    text: syncCopy(context, explainer.caption!),
                    onTap: explainer.next,
                  ),
                  _StepDots(step: explainer.step!, onStep: explainer.goTo),
                ] else ...[
                  _Legend(items: shown.method.legend),
                  const SizedBox(height: 12),
                  Padding(
                    padding: EdgeInsets.only(right: kiri == null ? 0 : 84),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          status,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          explain,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        if (stale &&
                            scene.status == SyncStatusKind.waiting &&
                            lastSuccessAt != null) ...[
                          const SizedBox(height: 10),
                          _StaleBanner(since: lastSuccessAt!),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _PrimaryButton(cta: shown.cta, onPressed: onPrimary),
                ],
              ],
            ),
            if (kiri != null)
              Positioned(
                right: -4,
                bottom: 52,
                child: ExcludeSemantics(
                  child: Image.asset(
                    'assets/kuchie/character/$kiri.webp',
                    width: 84,
                    height: 84,
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class _MethodPill extends StatelessWidget {
  const _MethodPill({required this.icon, required this.label});

  final MethodPillIcon? icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _Pill(
      children: [
        if (icon != null) ...[
          Icon(
            switch (icon!) {
              MethodPillIcon.phone => Icons.smartphone_rounded,
              MethodPillIcon.server => Icons.dns_outlined,
              MethodPillIcon.cloud => Icons.cloud_outlined,
            },
            size: 15,
            color: scheme.primary,
          ),
          const SizedBox(width: 6),
        ],
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: DefaultTextStyle.merge(
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        maxLines: 1,
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}

class _StatusPill extends StatefulWidget {
  const _StatusPill({
    required this.label,
    required this.tone,
    required this.still,
  });

  final String label;
  final PillTone tone;
  final bool still;

  @override
  State<_StatusPill> createState() => _StatusPillState();
}

class _StatusPillState extends State<_StatusPill>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  void _update() {
    if (widget.still || context.reduceMotion) {
      _pulse
        ..stop()
        ..value = 0;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _update();
  }

  @override
  void didUpdateWidget(_StatusPill old) {
    super.didUpdateWidget(old);
    _update();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (widget.tone) {
      PillTone.accent => scheme.primary,
      PillTone.muted => scheme.onSurfaceVariant,
      PillTone.danger => scheme.error,
    };
    return _Pill(
      children: [
        SizedBox.square(
          dimension: 14,
          child: AnimatedBuilder(
            animation: _pulse,
            builder: (context, _) =>
                CustomPaint(painter: _DotPainter(color, _pulse.value)),
          ),
        ),
        const SizedBox(width: 4),
        Text(widget.label),
      ],
    );
  }
}

class _DotPainter extends CustomPainter {
  _DotPainter(this.color, this.phase);

  final Color color;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    canvas.drawCircle(center, 4, Paint()..color = color);
    if (phase > 0) {
      canvas.drawCircle(
        center,
        4 + phase * 3,
        Paint()
          ..color = color.withValues(alpha: (1 - phase) * .8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_DotPainter old) =>
      old.color != color || old.phase != phase;
}

class _Legend extends StatelessWidget {
  const _Legend({required this.items});

  final List<LegendItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      label: localText(context, 'What syncs', 'Yang disinkronkan'),
      container: true,
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final item in items)
            Semantics(
              container: true,
              label: [
                syncCopy(context, item.label),
                if (item.note != null) syncCopy(context, item.note!),
                item.synced
                    ? localText(context, 'synced', 'disinkronkan')
                    : localText(context, 'not synced', 'tidak disinkronkan'),
              ].join(', '),
              child: ExcludeSemantics(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: item.synced ? '✓ ' : '– ',
                          style: TextStyle(
                            color: item.synced
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                        TextSpan(text: syncCopy(context, item.label)),
                        if (item.note != null)
                          TextSpan(
                            text: ' ${syncCopy(context, item.note!)}',
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: item.synced
                          ? scheme.onSurface
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StaleBanner extends StatelessWidget {
  const _StaleBanner({required this.since});

  final DateTime since;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = MaterialLocalizations.of(
      context,
    ).formatMediumDate(since.toLocal());
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        localText(
          context,
          'Not synced since $date. Your changes are safe on this iPhone.',
          'Belum tersinkron sejak $date. Perubahan aman di iPhone.',
        ),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.cta, required this.onPressed});

  final SyncCta cta;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final label = Text(syncCopy(context, cta.label));
    final action = cta.enabled ? onPressed : null;
    const size = Size.fromHeight(48);
    return cta.secondary
        ? OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: size),
            onPressed: action,
            child: label,
          )
        : FilledButton(
            style: FilledButton.styleFrom(minimumSize: size),
            onPressed: action,
            child: label,
          );
  }
}

class _Caption extends StatelessWidget {
  const _Caption({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Material(
        color: theme.colorScheme.surface,
        shape: StadiumBorder(
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StepDots extends StatelessWidget {
  const _StepDots({required this.step, required this.onStep});

  final int step;
  final ValueChanged<int> onStep;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < SyncExplainer.stepCount; i++)
            Semantics(
              button: true,
              selected: i == step,
              label: localText(context, 'Step ${i + 1}', 'Langkah ${i + 1}'),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onStep(i),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: AnimatedContainer(
                    duration: context.reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 200),
                    width: i == step ? 20 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == step ? scheme.primary : scheme.outlineVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
