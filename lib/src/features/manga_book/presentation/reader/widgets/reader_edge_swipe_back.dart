import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// "Swipe right to go back" for the reader, in every collection: a drag that
/// starts at the left edge and moves right closes the reader, like the iOS
/// back swipe. Only the thin edge strip listens, so page swipes and the
/// strip's own scrolling are untouched everywhere else.
class ReaderEdgeSwipeBack extends StatefulWidget {
  const ReaderEdgeSwipeBack({super.key, required this.child, this.onBack});

  final Widget child;

  /// Defaults to popping the reader's route.
  final VoidCallback? onBack;

  @override
  State<ReaderEdgeSwipeBack> createState() => _ReaderEdgeSwipeBackState();
}

class _ReaderEdgeSwipeBackState extends State<ReaderEdgeSwipeBack> {
  static const _edgeWidth = 22.0;
  static const _distance = 72.0;
  static const _flingVelocity = 650.0;

  double _dx = 0;
  bool _done = false;

  void _back() {
    if (_done) return;
    _done = true;
    HapticFeedback.lightImpact().ignore();
    final onBack = widget.onBack;
    if (onBack != null) {
      onBack();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        Positioned(
          top: 0,
          bottom: 0,
          left: rtl ? null : 0,
          right: rtl ? 0 : null,
          width: _edgeWidth + MediaQuery.paddingOf(context).left,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: (_) {
              _dx = 0;
              _done = false;
            },
            onHorizontalDragUpdate: (details) {
              _dx += rtl ? -details.delta.dx : details.delta.dx;
              if (_dx > _distance) _back();
            },
            onHorizontalDragEnd: (details) {
              final v = details.primaryVelocity ?? 0;
              if ((rtl ? -v : v) > _flingVelocity && _dx > 16) _back();
            },
          ),
        ),
      ],
    );
  }
}
