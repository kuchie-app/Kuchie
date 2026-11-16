// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/motion/reduce_motion.dart';
import '../../../widgets/kuchie_character_motion.dart';

// Every animation here runs a fixed number of times and then stops, so the
// first-run screens never keep the GPU awake while the user reads or types.

/// Reduce Motion, or a hidden route, shows each animation's final frame.
bool _motionOff(BuildContext context) =>
    (MediaQuery.maybeDisableAnimationsOf(context) ?? false) ||
    !TickerMode.valuesOf(context).enabled;

/// Plays [controller] once when motion is allowed, else jumps to its end.
void _playOnce(BuildContext context, AnimationController controller) {
  if (_motionOff(context)) {
    controller.value = 1;
  } else if (controller.isDismissed) {
    controller.forward();
  }
}

/// Fades and lifts [child] in after [delay], for staggered first-run text.
class OnboardingEntrance extends StatefulWidget {
  const OnboardingEntrance({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = const Offset(0, 0.25),
  });

  final Widget child;
  final Duration delay;

  /// Starting offset as a fraction of the child's size.
  final Offset offset;

  @override
  State<OnboardingEntrance> createState() => _OnboardingEntranceState();
}

class _OnboardingEntranceState extends State<OnboardingEntrance>
    with SingleTickerProviderStateMixin {
  static const _length = Duration(milliseconds: 520);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.delay + _length,
  );
  late final Animation<double> _progress = _controller.drive(
    CurveTween(
      curve: Interval(
        widget.delay.inMicroseconds / (widget.delay + _length).inMicroseconds,
        1,
        curve: Curves.easeOutCubic,
      ),
    ),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _playOnce(context, _controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _progress,
    child: SlideTransition(
      position: _progress.drive(Tween(begin: widget.offset, end: Offset.zero)),
      child: widget.child,
    ),
  );
}

/// The first-run background: a soft accent glow and manga halftone that settle
/// in once behind every step, matching the app's surface underneath.
class OnboardingBackdrop extends StatefulWidget {
  const OnboardingBackdrop({super.key, required this.child});

  final Widget child;

  @override
  State<OnboardingBackdrop> createState() => _OnboardingBackdropState();
}

class _OnboardingBackdropState extends State<OnboardingBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _playOnce(context, _controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: colors.surface),
        RepaintBoundary(
          child: CustomPaint(
            painter: _BackdropPainter(
              progress: _controller.drive(
                CurveTween(curve: Curves.easeOutCubic),
              ),
              glow: colors.primary,
              tone: colors.secondary,
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _BackdropPainter extends CustomPainter {
  _BackdropPainter({
    required this.progress,
    required this.glow,
    required this.tone,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final Color glow;
  final Color tone;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.center,
          colors: [
            glow.withValues(alpha: 0.16 * t),
            glow.withValues(alpha: 0),
          ],
        ).createShader(rect),
    );
    // Halftone fans out from two corners like screentone on a manga page.
    _halftone(canvas, size, Offset(size.width, 0), glow, 0.20 * t, t);
    _halftone(canvas, size, Offset(0, size.height), tone, 0.10 * t, t);
  }

  void _halftone(
    Canvas canvas,
    Size size,
    Offset corner,
    Color color,
    double alpha,
    double t,
  ) {
    if (alpha <= 0) return;
    const step = 16.0;
    final reach = size.shortestSide * (0.45 + 0.25 * t);
    final paint = Paint()..color = color.withValues(alpha: alpha);
    for (var x = 0.0; x <= size.width; x += step) {
      for (var y = 0.0; y <= size.height; y += step) {
        final offset = Offset(
          x + (y / step).floor().isOdd.toInt() * step / 2,
          y,
        );
        final distance = (offset - corner).distance;
        if (distance > reach) continue;
        final radius = 3.2 * (1 - distance / reach);
        if (radius > 0.4) canvas.drawCircle(offset, radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_BackdropPainter old) =>
      old.glow != glow || old.tone != tone || old.progress != progress;
}

extension on bool {
  int toInt() => this ? 1 : 0;
}

/// One choice on the first-run manga page.
class MangaChoice {
  const MangaChoice({
    required this.label,
    required this.caption,
    required this.icon,
    required this.art,
  });

  final String label;
  final String caption;
  final IconData icon;

  /// Kiri's pose for this panel, from the app's own artwork.
  final String art;
}

/// Two manga panels split by a slanted gutter. The chosen panel pops forward
/// with action lines; the other recedes. Panels slide in from either side.
class MangaModeChooser extends StatefulWidget {
  const MangaModeChooser({
    super.key,
    required this.first,
    required this.second,
    required this.selected,
    required this.onSelected,
  });

  final MangaChoice first;
  final MangaChoice second;

  /// 0 for [first], 1 for [second], null before a choice.
  final int? selected;
  final ValueChanged<int> onSelected;

  @override
  State<MangaModeChooser> createState() => _MangaModeChooserState();
}

class _MangaModeChooserState extends State<MangaModeChooser>
    with TickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  late final List<AnimationController> _pops = [
    for (var i = 0; i < 2; i++)
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 560),
      ),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _playOnce(context, _entrance);
    if (_motionOff(context)) {
      for (final pop in _pops) {
        pop.value = 1;
      }
    }
  }

  @override
  void didUpdateWidget(MangaModeChooser oldWidget) {
    super.didUpdateWidget(oldWidget);
    final chosen = widget.selected;
    if (chosen != null && chosen != oldWidget.selected) {
      if (_motionOff(context)) {
        _pops[chosen].value = 1;
      } else {
        _pops[chosen].forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    for (final pop in _pops) {
      pop.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final height = math.min(width * 1.08, 420.0);
      final size = Size(width, height);
      return SizedBox(
        width: width,
        height: height,
        child: Stack(
          children: [
            for (final index in [0, 1])
              _AnimatedPanel(
                index: index,
                size: size,
                choice: index == 0 ? widget.first : widget.second,
                entrance: _entrance,
                pop: _pops[index],
                selected: widget.selected == index,
                dimmed: widget.selected != null && widget.selected != index,
                onTap: () => widget.onSelected(index),
              ),
          ],
        ),
      );
    },
  );
}

/// Panel outlines: the top panel's lower edge falls to the left, and the bottom
/// panel mirrors it across a 12pt gutter.
Path _panelPath(int index, Size size) {
  const gutter = 12.0;
  final w = size.width;
  final h = size.height;
  final left = h * 0.56;
  final right = h * 0.42;
  return index == 0
      ? (Path()
          ..moveTo(0, 0)
          ..lineTo(w, 0)
          ..lineTo(w, right - gutter / 2)
          ..lineTo(0, left - gutter / 2)
          ..close())
      : (Path()
          ..moveTo(0, left + gutter / 2)
          ..lineTo(w, right + gutter / 2)
          ..lineTo(w, h)
          ..lineTo(0, h)
          ..close());
}

class _AnimatedPanel extends StatelessWidget {
  const _AnimatedPanel({
    required this.index,
    required this.size,
    required this.choice,
    required this.entrance,
    required this.pop,
    required this.selected,
    required this.dimmed,
    required this.onTap,
  });

  final int index;
  final Size size;
  final MangaChoice choice;
  final AnimationController entrance;
  final AnimationController pop;
  final bool selected;
  final bool dimmed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final start = index * 0.14;
    final slide = entrance.drive(
      CurveTween(
        curve: Interval(start, start + 0.62, curve: Curves.easeOutBack),
      ),
    );
    final fade = entrance.drive(
      CurveTween(curve: Interval(start, start + 0.4, curve: Curves.easeOut)),
    );
    final reduce = context.reduceMotion;
    return AnimatedBuilder(
      animation: Listenable.merge([entrance, pop]),
      builder: (context, child) {
        final from = index == 0 ? -1.0 : 1.0;
        final popCurve = Curves.easeOutBack.transform(pop.value);
        final scale = selected ? 1 + 0.035 * popCurve : 1.0;
        return Opacity(
          opacity: fade.value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(from * size.width * 0.35 * (1 - slide.value), 0),
            child: Transform.rotate(
              angle: from * 0.06 * (1 - slide.value),
              child: Transform.scale(scale: scale, child: child),
            ),
          ),
        );
      },
      child: AnimatedOpacity(
        opacity: dimmed ? 0.5 : 1,
        duration: reduce ? Duration.zero : const Duration(milliseconds: 220),
        child: _Panel(
          index: index,
          size: size,
          choice: choice,
          entrance: entrance,
          pop: pop,
          selected: selected,
          onTap: onTap,
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.index,
    required this.size,
    required this.choice,
    required this.entrance,
    required this.pop,
    required this.selected,
    required this.onTap,
  });

  final int index;
  final Size size;
  final MangaChoice choice;
  final AnimationController entrance;
  final AnimationController pop;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colorScheme;
    final text = context.textTheme;
    final path = _panelPath(index, size);
    final top = index == 0;
    final w = size.width;
    final h = size.height;
    final artWidth = math.min(w * 0.46, 176.0);
    // The art sits where the panel is tallest, the words where it is wide.
    final artCenter = top
        ? Offset(w - artWidth / 2 - 6, h * 0.23)
        : Offset(artWidth / 2 + 6, h * 0.79);
    final bubbleStart = 0.30 + index * 0.14;
    final bubble = entrance.drive(
      CurveTween(
        curve: Interval(
          bubbleStart,
          bubbleStart + 0.4,
          curve: Curves.easeOutBack,
        ),
      ),
    );
    final caption = entrance.drive(
      CurveTween(
        curve: Interval(bubbleStart + 0.18, 1, curve: Curves.easeOutCubic),
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      label: '${choice.label}. ${choice.caption}',
      excludeSemantics: true,
      child: ClipPath(
        clipper: _PathClipper(path),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Stack(
            children: [
              Positioned.fill(
                child: ColoredBox(color: colors.surfaceContainerHigh),
              ),
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _PanelArtPainter(
                      pop: pop,
                      selected: selected,
                      tone: colors.primary,
                      focus: artCenter,
                      corner: top ? Offset(w, 0) : Offset(0, h),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: artCenter.dx - artWidth / 2,
                top: artCenter.dy - artWidth * 0.375,
                child: _PoppingArt(
                  pop: pop,
                  selected: selected,
                  child: Image.asset(
                    choice.art,
                    width: artWidth,
                    height: artWidth * 0.75,
                    fit: BoxFit.contain,
                    cacheWidth:
                        (artWidth * MediaQuery.devicePixelRatioOf(context))
                            .round(),
                    excludeFromSemantics: true,
                  ),
                ),
              ),
              Positioned(
                left: top ? 16 : null,
                right: top ? null : 16,
                // Each caption hangs under its bubble, so the two never meet.
                top: (top ? 18 : h * 0.42 + 26) + 66,
                width: w - artWidth - 36,
                child: FadeTransition(
                  opacity: caption,
                  child: _NarrationBox(text: choice.caption),
                ),
              ),
              Positioned(
                left: top ? 16 : null,
                right: top ? null : 16,
                top: top ? 18 : h * 0.42 + 26,
                child: ScaleTransition(
                  scale: bubble,
                  alignment: top ? Alignment.bottomRight : Alignment.bottomLeft,
                  child: _SpeechBubble(
                    tailRight: top,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          choice.icon,
                          size: 20,
                          color: colors.onInverseSurface,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          choice.label,
                          style: text.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: colors.onInverseSurface,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _InkBorderPainter(
                      path: path,
                      pop: pop,
                      selected: selected,
                      ink: colors.onSurface,
                      accent: colors.primary,
                    ),
                  ),
                ),
              ),
              if (selected)
                Positioned(
                  right: top ? 14 : null,
                  left: top ? null : 14,
                  // Tucked against each panel's slanted edge.
                  top: top ? null : h * 0.56 + 18,
                  bottom: top ? h * 0.58 + 16 : null,
                  child: ScaleTransition(
                    scale: pop.drive(CurveTween(curve: Curves.elasticOut)),
                    child: Icon(
                      Icons.check_circle_rounded,
                      size: 28,
                      color: colors.primary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PathClipper extends CustomClipper<Path> {
  const _PathClipper(this.path);
  final Path path;

  @override
  Path getClip(Size size) => path;

  @override
  bool shouldReclip(_PathClipper old) => old.path != path;
}

/// Kiri hops and tilts once when its panel is chosen.
class _PoppingArt extends StatelessWidget {
  const _PoppingArt({
    required this.pop,
    required this.selected,
    required this.child,
  });

  final Animation<double> pop;
  final bool selected;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: pop,
    builder: (context, child) {
      final t = selected ? pop.value : 1.0;
      final hop = math.sin(math.pi * t);
      return Transform.translate(
        offset: Offset(0, -14 * hop),
        child: Transform.rotate(
          angle: 0.10 * math.sin(2 * math.pi * t) * (1 - t),
          child: Transform.scale(scale: 1 + 0.08 * hop, child: child),
        ),
      );
    },
    child: child,
  );
}

/// Screentone from the panel's corner, plus action lines when chosen.
class _PanelArtPainter extends CustomPainter {
  _PanelArtPainter({
    required this.pop,
    required this.selected,
    required this.tone,
    required this.focus,
    required this.corner,
  }) : super(repaint: pop);

  final Animation<double> pop;
  final bool selected;
  final Color tone;
  final Offset focus;
  final Offset corner;

  @override
  void paint(Canvas canvas, Size size) {
    final dots = Paint()
      ..color = tone.withValues(alpha: selected ? 0.30 : 0.16);
    const step = 11.0;
    final reach = size.longestSide * 0.75;
    for (var x = 0.0; x <= size.width; x += step) {
      for (var y = 0.0; y <= size.height; y += step) {
        final offset = Offset(x + ((y / step).floor().isOdd ? step / 2 : 0), y);
        final radius = 2.6 * (1 - (offset - corner).distance / reach);
        if (radius > 0.35) canvas.drawCircle(offset, radius, dots);
      }
    }
    if (!selected) return;
    // Speed lines burst out from Kiri, then thin to a steady frame.
    final t = Curves.easeOutCubic.transform(pop.value);
    final lines = Paint()
      ..color = tone.withValues(alpha: 0.55 - 0.25 * t)
      ..strokeCap = StrokeCap.round;
    final random = math.Random(7);
    for (var i = 0; i < 28; i++) {
      final angle = i / 28 * 2 * math.pi + random.nextDouble() * 0.12;
      final direction = Offset(math.cos(angle), math.sin(angle));
      final inner = 70 + 40 * random.nextDouble() + 30 * (1 - t);
      final outer = inner + (60 + 90 * random.nextDouble()) * t;
      lines.strokeWidth = 1.2 + 2.2 * random.nextDouble();
      canvas.drawLine(
        focus + direction * inner,
        focus + direction * outer,
        lines,
      );
    }
  }

  @override
  bool shouldRepaint(_PanelArtPainter old) =>
      old.selected != selected ||
      old.tone != tone ||
      old.focus != focus ||
      old.corner != corner;
}

class _InkBorderPainter extends CustomPainter {
  _InkBorderPainter({
    required this.path,
    required this.pop,
    required this.selected,
    required this.ink,
    required this.accent,
  }) : super(repaint: pop);

  final Path path;
  final Animation<double> pop;
  final bool selected;
  final Color ink;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final t = selected ? Curves.easeOutCubic.transform(pop.value) : 0.0;
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 5 + 3 * t
        ..color = Color.lerp(ink.withValues(alpha: 0.85), accent, t)!,
    );
  }

  @override
  bool shouldRepaint(_InkBorderPainter old) =>
      old.path != path ||
      old.selected != selected ||
      old.ink != ink ||
      old.accent != accent;
}

/// A manga speech balloon, inverse-coloured so it reads in both themes.
class _SpeechBubble extends StatelessWidget {
  const _SpeechBubble({required this.child, required this.tailRight});

  final Widget child;
  final bool tailRight;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colorScheme;
    return CustomPaint(
      painter: _BubblePainter(
        fill: colors.inverseSurface,
        tailRight: tailRight,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
        child: child,
      ),
    );
  }
}

class _BubblePainter extends CustomPainter {
  const _BubblePainter({required this.fill, required this.tailRight});

  final Color fill;
  final bool tailRight;

  @override
  void paint(Canvas canvas, Size size) {
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height - 10),
      const Radius.circular(22),
    );
    final tipX = tailRight ? size.width - 18 : 18.0;
    final baseX = tailRight ? size.width - 40 : 40.0;
    final tail = Path()
      ..moveTo(baseX, size.height - 12)
      ..lineTo(tipX + (tailRight ? 10 : -10), size.height)
      ..lineTo(tipX, size.height - 12)
      ..close();
    final paint = Paint()..color = fill;
    canvas
      ..drawRRect(body, paint)
      ..drawPath(tail, paint);
  }

  @override
  bool shouldRepaint(_BubblePainter old) =>
      old.fill != fill || old.tailRight != tailRight;
}

/// A rectangular narration caption, as manga uses for scene text.
class _NarrationBox extends StatelessWidget {
  const _NarrationBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.88),
        border: Border.all(
          color: colors.onSurface.withValues(alpha: 0.7),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Text(
          text,
          style: context.textTheme.bodyMedium?.copyWith(
            color: colors.onSurface,
            height: 1.3,
          ),
        ),
      ),
    );
  }
}

/// "You're all set": Kiri swoops in on a curved flight path trailing speed
/// lines and sparkles, lands with a burst, then hovers a few times and rests.
class FlyingKuchie extends StatefulWidget {
  const FlyingKuchie({super.key, required this.title, required this.subtitle});

  final Widget title;
  final Widget subtitle;

  @override
  State<FlyingKuchie> createState() => _FlyingKuchieState();
}

class _FlyingKuchieState extends State<FlyingKuchie>
    with TickerProviderStateMixin {
  late final AnimationController _flight = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1900),
  );
  late final AnimationController _hover = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );

  @override
  void initState() {
    super.initState();
    _flight.addStatusListener((status) {
      // A few gentle bobs, then still, so the screen can go idle.
      if (status == AnimationStatus.completed &&
          mounted &&
          !_motionOff(context)) {
        _hover.repeat(count: 3);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _playOnce(context, _flight);
  }

  @override
  void dispose() {
    _flight.dispose();
    _hover.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colorScheme;
    final artWidth = math.min(MediaQuery.sizeOf(context).width * 0.56, 230.0);
    final words = _flight.drive(
      CurveTween(curve: const Interval(0.62, 1, curve: Curves.easeOutBack)),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: artWidth * 1.25,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final area = Size(constraints.maxWidth, artWidth * 1.25);
              return AnimatedBuilder(
                animation: Listenable.merge([_flight, _hover]),
                builder: (context, child) {
                  final pose = _FlightPose.at(
                    _flight.value,
                    _hover.isAnimating ? _hover.value : 0,
                    area,
                  );
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _FlightTrailPainter(
                            progress: _flight.value,
                            area: area,
                            streak: colors.primary,
                            sparkle: colors.secondary,
                          ),
                        ),
                      ),
                      Positioned(
                        left: pose.center.dx - artWidth / 2,
                        top: pose.center.dy - artWidth * 0.375,
                        child: Transform.rotate(
                          angle: pose.angle,
                          child: Transform.scale(
                            scale: pose.scale,
                            child: child,
                          ),
                        ),
                      ),
                    ],
                  );
                },
                child: KuchieCharacterMotion(
                  phase: KuchieCharacterPhase.complete,
                  width: artWidth,
                  play: false,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        FadeTransition(
          opacity: words.drive(Tween(begin: 0, end: 1)),
          child: ScaleTransition(
            scale: words.drive(Tween(begin: 0.85, end: 1)),
            child: Column(
              children: [
                widget.title,
                const SizedBox(height: 8),
                widget.subtitle,
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Where Kiri is along the flight, as a function of time only so the trail
/// painter can sample earlier points of the same path.
class _FlightPose {
  const _FlightPose(this.center, this.angle, this.scale);

  final Offset center;
  final double angle;
  final double scale;

  static Offset _path(double t, Size area) {
    final start = Offset(-area.width * 0.25, area.height * 1.05);
    final control = Offset(area.width * 0.12, -area.height * 0.25);
    final end = Offset(area.width / 2, area.height * 0.48);
    final u = 1 - t;
    return start * (u * u) + control * (2 * u * t) + end * (t * t);
  }

  static Offset pathAt(double progress, Size area) => _path(
    Curves.easeOutCubic.transform(progress.clamp(0, 0.75) / 0.75),
    area,
  );

  static _FlightPose at(double progress, double hover, Size area) {
    final t = Curves.easeOutCubic.transform(progress.clamp(0, 0.75) / 0.75);
    final bob = math.sin(2 * math.pi * hover);
    final center = _path(t, area) + Offset(0, -7 * bob);
    // Lean into the climb, then settle to a slight forward tilt.
    final lean = 0.45 * (1 - t) - 0.06 * t + 0.03 * bob;
    final landing = math.sin(math.pi * ((progress - 0.7) / 0.3).clamp(0, 1));
    return _FlightPose(center, lean, 0.55 + 0.45 * t + 0.06 * landing);
  }
}

class _FlightTrailPainter extends CustomPainter {
  const _FlightTrailPainter({
    required this.progress,
    required this.area,
    required this.streak,
    required this.sparkle,
  });

  final double progress;
  final Size area;
  final Color streak;
  final Color sparkle;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final flying = (1 - progress / 0.8).clamp(0.0, 1.0);
    // Speed lines trail behind Kiri along the path she just flew.
    final lines = Paint()..strokeCap = StrokeCap.round;
    for (var i = 1; i <= 6; i++) {
      final head = _FlightPose.pathAt(progress - 0.015 * i, area);
      final tail = _FlightPose.pathAt(progress - 0.015 * i - 0.06, area);
      final side = Offset(0, (i.isEven ? 1 : -1) * (8.0 + 6 * i));
      lines
        ..strokeWidth = 3.0 - i * 0.3
        ..color = streak.withValues(alpha: 0.6 * flying * (1 - i / 7));
      canvas.drawLine(head + side, tail + side, lines);
    }
    // Sparkles left behind along the path fade as she passes.
    final star = Paint();
    for (var i = 1; i <= 9; i++) {
      final at = progress - 0.05 * i;
      if (at <= 0) break;
      final point =
          _FlightPose.pathAt(at, area) +
          Offset(14.0 * (i % 3 - 1), 10.0 * ((i + 1) % 3 - 1));
      final fade = (1 - i / 10) * flying;
      star.color = (i.isEven ? sparkle : streak).withValues(alpha: 0.85 * fade);
      _drawSparkle(canvas, point, 3.0 + 3.5 * (i % 3), star);
    }
    // A ring and short rays mark the landing.
    final land = ((progress - 0.7) / 0.3).clamp(0.0, 1.0);
    if (land > 0) {
      final center = _FlightPose.pathAt(1, area);
      final fade = 1 - land;
      canvas.drawCircle(
        center,
        40 + 90 * land,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 * fade
          ..color = streak.withValues(alpha: 0.5 * fade),
      );
      final rays = Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 3
        ..color = sparkle.withValues(alpha: 0.7 * fade);
      for (var i = 0; i < 10; i++) {
        final angle = i / 10 * 2 * math.pi;
        final direction = Offset(math.cos(angle), math.sin(angle));
        canvas.drawLine(
          center + direction * (70 + 50 * land),
          center + direction * (86 + 70 * land),
          rays,
        );
      }
    }
  }

  void _drawSparkle(Canvas canvas, Offset c, double r, Paint paint) {
    final path = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_FlightTrailPainter old) =>
      old.progress != progress ||
      old.area != area ||
      old.streak != streak ||
      old.sparkle != sparkle;
}
