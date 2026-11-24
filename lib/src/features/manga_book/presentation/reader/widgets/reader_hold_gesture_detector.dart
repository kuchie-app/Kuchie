// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

/// How long a finger must rest on a page before the page menu opens. A bit
/// longer than the platform default, so a thumb resting while reading does
/// not open it.
const kReaderLongPressDelay = Duration(milliseconds: 650);

/// How long after scrolling stops a touch still counts as stopping it.
const _settleWindow = Duration(milliseconds: 300);

/// Tap and long press for a scrolling reader page. A long press only counts
/// when the finger lands on still content and the content stays still: a
/// touch that stops a fling, or a hold during a slow scroll, is ignored.
class ReaderHoldGestureDetector extends StatefulWidget {
  const ReaderHoldGestureDetector({
    super.key,
    this.onTap,
    this.onLongPressStart,
    this.behavior = HitTestBehavior.translucent,
    required this.child,
  });

  final VoidCallback? onTap;
  final GestureLongPressStartCallback? onLongPressStart;
  final HitTestBehavior behavior;
  final Widget child;

  @override
  State<ReaderHoldGestureDetector> createState() =>
      _ReaderHoldGestureDetectorState();
}

class _ReaderHoldGestureDetectorState extends State<ReaderHoldGestureDetector> {
  bool _scrolling = false;
  bool _settling = false;
  Timer? _settleTimer;

  /// Set at touch-down: the content was moving or had only just stopped.
  bool _touchStoppedMotion = false;

  /// The content scrolled while the finger was down.
  bool _scrolledDuringTouch = false;
  int _pointersDown = 0;

  @override
  void dispose() {
    _settleTimer?.cancel();
    super.dispose();
  }

  bool _onScroll(ScrollNotification notification) {
    switch (notification) {
      case ScrollStartNotification():
        _scrolling = true;
        _settleTimer?.cancel();
        _settling = false;
      case ScrollUpdateNotification(:final scrollDelta?) when scrollDelta != 0:
        if (_pointersDown > 0) _scrolledDuringTouch = true;
      case ScrollEndNotification():
        _scrolling = false;
        _settling = true;
        _settleTimer?.cancel();
        _settleTimer = Timer(_settleWindow, () => _settling = false);
      default:
        break;
    }
    return false;
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_pointersDown++ == 0) {
      // Stopping a fling ends the scroll during this same event, so the
      // settle window catches it as well as a scroll still running.
      _touchStoppedMotion = _scrolling || _settling;
      _scrolledDuringTouch = false;
    }
  }

  void _onPointerUp(PointerEvent event) {
    if (_pointersDown > 0) _pointersDown--;
  }

  void _onLongPressStart(LongPressStartDetails details) {
    if (_touchStoppedMotion || _scrolledDuringTouch) return;
    widget.onLongPressStart?.call(details);
  }

  @override
  Widget build(BuildContext context) {
    final onTap = widget.onTap;
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _onPointerDown,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerUp,
        child: RawGestureDetector(
          behavior: widget.behavior,
          gestures: {
            if (onTap != null)
              TapGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                    () => TapGestureRecognizer(debugOwner: this),
                    (recognizer) => recognizer.onTap = onTap,
                  ),
            if (widget.onLongPressStart != null)
              LongPressGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    LongPressGestureRecognizer
                  >(
                    () => LongPressGestureRecognizer(
                      duration: kReaderLongPressDelay,
                      debugOwner: this,
                    ),
                    (recognizer) =>
                        recognizer.onLongPressStart = _onLongPressStart,
                  ),
          },
          child: widget.child,
        ),
      ),
    );
  }
}
