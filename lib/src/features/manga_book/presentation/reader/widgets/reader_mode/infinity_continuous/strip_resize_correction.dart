import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

/// Keeps a long strip still when a page above the visible ones changes
/// extent (placeholder to decoded image, a retry, a crop), without stopping
/// the user's drag or fling.
///
/// ScrollablePositionedList anchors on one item: pages before it grow away
/// from the viewport and never move it, so only pages from the anchor up to
/// the first visible page need a correction. The correction shifts the scroll
/// offset by the size change and, during a fling, restarts the fling at the
/// same speed. An indexed jump would instead rebuild every page (a flash of
/// loading placeholders) and drop the momentum.
///
/// Wrap the strip with [wrap] so the helper sees its pointers and scrolls.
class StripResizeCorrection {
  StripResizeCorrection({
    required this.itemScrollController,
    required this.scrollOffsetController,
    required this.positionsListener,
    this.onAdjusting,
  });

  final ItemScrollController itemScrollController;
  final ScrollOffsetController scrollOffsetController;
  final ItemPositionsListener positionsListener;

  /// Called with true before and false after the correction moves the strip,
  /// so listeners can tell it from a user scroll.
  final void Function(bool adjusting)? onAdjusting;

  double _pending = 0;
  bool _scheduled = false;
  bool _disposed = false;
  bool _applying = false;

  // Fingers on the strip: with none, a moving strip is a fling.
  int _pointers = 0;

  // Strip speed from its scroll updates, sampled once per frame (the
  // position's activity and its velocity are not public API).
  double _velocity = 0;
  double _frameDelta = 0;
  Duration? _frameTime;

  void dispose() => _disposed = true;

  /// Puts the pointer and scroll listeners this helper needs around [strip].
  Widget wrap(Widget strip) => Listener(
    onPointerDown: (_) => _pointers++,
    onPointerUp: (_) => _pointers = _pointers > 0 ? _pointers - 1 : 0,
    onPointerCancel: (_) => _pointers = _pointers > 0 ? _pointers - 1 : 0,
    child: NotificationListener<ScrollNotification>(
      onNotification: handleNotification,
      child: strip,
    ),
  );

  /// Feeds the strip's own (depth 0) scroll notifications; [wrap] calls it.
  bool handleNotification(ScrollNotification notification) {
    if (_applying || notification.depth != 0) return false;
    switch (notification) {
      case ScrollStartNotification():
      case ScrollEndNotification():
        _velocity = 0;
        _frameDelta = 0;
        _frameTime = null;
      case ScrollUpdateNotification(:final scrollDelta?):
        final now = SchedulerBinding.instance.currentSystemFrameTimeStamp;
        final last = _frameTime;
        if (last == null || now <= last) {
          // Several updates can land in one frame (touch events); add them.
          _frameDelta += scrollDelta;
          _frameTime ??= now;
        } else {
          final seconds =
              (now - last).inMicroseconds / Duration.microsecondsPerSecond;
          final sample = (_frameDelta + scrollDelta) / seconds;
          _velocity = _velocity == 0 ? sample : _velocity * .4 + sample * .6;
          _frameDelta = 0;
          _frameTime = now;
        }
      default:
        break;
    }
    return false;
  }

  /// Whether a size change of the item at [index] moves the visible items.
  bool shifts(int index) {
    if (!itemScrollController.isAttached) return false;
    final anchor = itemScrollController.anchorIndex;
    if (anchor == null || index < anchor) return false;
    ItemPosition? first;
    for (final position in positionsListener.itemPositions.value) {
      if (position.itemTrailingEdge <= 0 || position.itemLeadingEdge >= 1) {
        continue;
      }
      if (first == null || position.index < first.index) first = position;
    }
    if (first == null || index > first.index) return false;
    // The first visible page grows past the bottom edge unless its top is
    // already off screen.
    return index < first.index || first.itemLeadingEdge < 0;
  }

  /// Call when the item at [index] changed its main-axis extent by [delta].
  void onResize(int index, double delta) {
    if (_disposed || delta.abs() < 0.5 || !shifts(index)) return;
    _pending += delta;
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      final correction = _pending;
      _pending = 0;
      if (_disposed || correction == 0 || !itemScrollController.isAttached) {
        return;
      }
      _apply(correction);
    });
  }

  void _apply(double correction) {
    final ScrollPosition position;
    try {
      position = scrollOffsetController.position;
    } catch (_) {
      return;
    }
    if (!position.hasPixels) return;
    onAdjusting?.call(true);
    _applying = true;
    try {
      if (position is ScrollPositionWithSingleContext &&
          position.isScrollingNotifier.value) {
        // Moves the strip without replacing the drag or fling activity.
        position.applyUserOffset(-correction);
        if (_pointers == 0) {
          // A fling simulates absolute offsets and would undo the shift on
          // its next tick; restart it from here at the same speed.
          position.goBallistic(_velocity);
        }
      } else {
        position.jumpTo(position.pixels + correction);
      }
    } finally {
      _applying = false;
      onAdjusting?.call(false);
    }
  }
}
