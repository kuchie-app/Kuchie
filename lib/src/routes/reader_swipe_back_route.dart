// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

/// Width of the strip along the left edge that starts a swipe back.
const kReaderSwipeBackEdge = 20.0;

/// A reader route that closes by dragging from the left edge, as iOS pages
/// do: the reader follows the finger and the page under it shows through.
/// Letting go past halfway, or with a flick, closes it.
///
/// The edge strip keeps the touch to itself, so the reader under it does
/// not also turn a page.
class ReaderSwipeBackRoute<T> extends PageRoute<T> {
  ReaderSwipeBackRoute({
    required this.builder,
    RouteTransitionsBuilder? transitionsBuilder,
    super.settings,
  }) : transitionsBuilder = transitionsBuilder ?? _slideFromRight;

  final WidgetBuilder builder;

  /// The transition used when the reader opens or closes without a swipe.
  final RouteTransitionsBuilder transitionsBuilder;

  final _swiping = ValueNotifier<bool>(false);

  static Widget _slideFromRight(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => SlideTransition(
    position: Tween<Offset>(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
    child: child,
  );

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => builder(context);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => _SwipeBackEdge(
    route: this,
    // One widget tree either way, so the reader keeps its state when a
    // swipe starts: the swipe slides the whole page sideways while the
    // regular transition holds still.
    child: ValueListenableBuilder<bool>(
      valueListenable: _swiping,
      child: child,
      builder: (context, swiping, child) => SlideTransition(
        position: swiping
            ? Tween<Offset>(
                begin: const Offset(1, 0),
                end: Offset.zero,
              ).animate(animation)
            : const AlwaysStoppedAnimation(Offset.zero),
        child: transitionsBuilder(
          context,
          swiping ? kAlwaysCompleteAnimation : animation,
          secondaryAnimation,
          child!,
        ),
      ),
    ),
  );

  bool get _canSwipeBack =>
      isCurrent &&
      !isFirst &&
      !(navigator?.userGestureInProgress ?? true) &&
      !(controller?.isAnimating ?? true) &&
      popDisposition != RoutePopDisposition.doNotPop;

  void _startSwipe() {
    navigator!.didStartUserGesture();
    _swiping.value = true;
  }

  void _updateSwipe(double fraction) {
    final controller = this.controller!;
    controller.value = (controller.value - fraction).clamp(0.0, 1.0);
  }

  /// [velocity] is in screen widths per second, positive towards the right.
  void _endSwipe(double velocity) {
    final controller = this.controller!;
    final close = velocity > 1 || (velocity >= -1 && controller.value < .5);
    if (close) {
      navigator!.pop();
    } else {
      controller.animateTo(
        1,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
    void finish() {
      navigator?.didStopUserGesture();
      _swiping.value = false;
    }

    if (!controller.isAnimating) {
      finish();
      return;
    }
    late final AnimationStatusListener listener;
    listener = (status) {
      if (status.isAnimating) return;
      controller.removeStatusListener(listener);
      finish();
    };
    controller.addStatusListener(listener);
  }

  @override
  void dispose() {
    _swiping.dispose();
    super.dispose();
  }
}

/// A [Page] for [ReaderSwipeBackRoute], for routes built by the router.
class ReaderSwipeBackPage<T> extends Page<T> {
  const ReaderSwipeBackPage({
    super.key,
    required this.child,
    this.transitionsBuilder,
  });

  final Widget child;
  final RouteTransitionsBuilder? transitionsBuilder;

  @override
  Route<T> createRoute(BuildContext context) => ReaderSwipeBackRoute<T>(
    settings: this,
    builder: (_) => child,
    transitionsBuilder: transitionsBuilder,
  );
}

class _SwipeBackEdge extends StatefulWidget {
  const _SwipeBackEdge({required this.route, required this.child});

  final ReaderSwipeBackRoute<dynamic> route;
  final Widget child;

  @override
  State<_SwipeBackEdge> createState() => _SwipeBackEdgeState();
}

class _SwipeBackEdgeState extends State<_SwipeBackEdge> {
  bool _active = false;

  double get _width => context.size?.width ?? 1;

  void _onStart(DragStartDetails details) {
    if (!widget.route._canSwipeBack) return;
    _active = true;
    widget.route._startSwipe();
  }

  void _onUpdate(DragUpdateDetails details) {
    if (!_active) return;
    widget.route._updateSwipe(details.primaryDelta! / _width);
  }

  void _onEnd(DragEndDetails details) {
    if (!_active) return;
    _active = false;
    widget.route._endSwipe(details.velocity.pixelsPerSecond.dx / _width);
  }

  void _onCancel() {
    if (!_active) return;
    _active = false;
    widget.route._endSwipe(0);
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        Positioned(
          left: 0,
          // Below the top bar, so its back button stays fully tappable.
          top: padding.top + kToolbarHeight,
          bottom: 0,
          width: kReaderSwipeBackEdge + padding.left,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            dragStartBehavior: DragStartBehavior.down,
            onHorizontalDragStart: _onStart,
            onHorizontalDragUpdate: _onUpdate,
            onHorizontalDragEnd: _onEnd,
            onHorizontalDragCancel: _onCancel,
          ),
        ),
      ],
    );
  }
}
