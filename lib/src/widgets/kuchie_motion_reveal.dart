import 'package:flutter/widgets.dart';

/// A brief, one-shot reveal for a newly visible screen state.
///
/// Keep the same key for rebuilds of the same state. Change the key when a
/// different result arrives. The caller remains responsible for the state.
class KuchieMotionReveal extends StatefulWidget {
  const KuchieMotionReveal({super.key, required this.child});

  final Widget child;

  @override
  State<KuchieMotionReveal> createState() => _KuchieMotionRevealState();
}

class _KuchieMotionRevealState extends State<KuchieMotionReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  );
  late final Animation<double> _progress = _controller.drive(
    CurveTween(curve: Curves.easeOutCubic),
  );
  late final Animation<Offset> _offset = _progress.drive(
    Tween(begin: const Offset(0, 0.035), end: Offset.zero),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduced || !TickerMode.valuesOf(context).enabled) {
      _controller.value = 1;
    } else if (_controller.isDismissed && !_controller.isAnimating) {
      _controller.forward();
    }
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _progress,
    child: SlideTransition(position: _offset, child: widget.child),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
