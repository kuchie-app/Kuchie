// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:math' as math;

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// How far the content has to be pulled down before letting go refreshes.
const kPullToRefreshDistance = 72.0;

/// Size of the refresh arrow.
const kPullRefreshIconSize = 26.0;

/// The refresh arrow shown above content that is pulled down: it turns and
/// fades in with the pull, then spins while refreshing.
class PullRefreshIcon extends StatefulWidget {
  const PullRefreshIcon({
    super.key,
    required this.progress,
    required this.refreshing,
  });

  /// How far the pull is towards the threshold; 1 or more refreshes on release.
  final double progress;
  final bool refreshing;

  @override
  State<PullRefreshIcon> createState() => _PullRefreshIconState();
}

class _PullRefreshIconState extends State<PullRefreshIcon>
    with SingleTickerProviderStateMixin {
  late final _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(PullRefreshIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.refreshing && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!widget.refreshing && _spin.isAnimating) {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.progress.clamp(0.0, 1.0);
    final armed = widget.refreshing || widget.progress >= 1;
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: MaterialLocalizations.of(context).refreshIndicatorSemanticLabel,
      child: AnimatedBuilder(
        animation: _spin,
        builder: (context, child) => Opacity(
          opacity: widget.refreshing ? 1 : progress,
          child: Transform.rotate(
            angle: widget.refreshing
                ? _spin.value * 2 * math.pi
                : progress * 1.5 * math.pi,
            child: child,
          ),
        ),
        child: Icon(
          FluentIcons.arrow_clockwise_24_regular,
          size: kPullRefreshIconSize,
          color: armed ? colors.primary : colors.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Pull-to-refresh for a scrolling page: pulling the content down past the
/// top shows the refresh arrow under [top] (the bottom of the bar), and
/// letting go past [kPullToRefreshDistance] calls [onRefresh]. The content
/// bounces back right away; the page shows its own progress.
///
/// [child] must report scrolling through [ScrollNotification]s at depth 0 or
/// 1.
class PullToRefresh extends StatefulWidget {
  const PullToRefresh({
    super.key,
    required this.onRefresh,
    required this.top,
    required this.child,
  });

  final Future<void> Function() onRefresh;
  final double top;
  final Widget child;

  @override
  State<PullToRefresh> createState() => _PullToRefreshState();
}

class _PullToRefreshState extends State<PullToRefresh> {
  final _pull = ValueNotifier<double>(0);
  bool _armed = false;
  bool _refreshing = false;

  @override
  void dispose() {
    _pull.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification notification) {
    // Depth 1 too: an empty or error state wraps itself in its own scroll
    // view, and pulling that should refresh as well.
    if (notification.depth > 1 || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    final pull = math.max(
      0.0,
      notification.metrics.minScrollExtent - notification.metrics.pixels,
    );
    _pull.value = pull;
    if (_refreshing) return false;
    final dragging = switch (notification) {
      ScrollUpdateNotification(:final dragDetails) => dragDetails != null,
      OverscrollNotification(:final dragDetails) => dragDetails != null,
      ScrollEndNotification() => false,
      _ => null,
    };
    if (dragging == true) {
      final armed = pull >= kPullToRefreshDistance;
      if (armed && !_armed) unawaited(HapticFeedback.selectionClick());
      _armed = armed;
    } else if (dragging == false && _armed) {
      // Let go past the threshold.
      _armed = false;
      unawaited(_refresh());
    }
    return false;
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        // Expand: the idle indicator is an unpositioned empty box, which
        // must not decide the size of the page.
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              // Pulling past the top needs the bounce, even on a short page.
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                ),
                child: widget.child,
              ),
            ),
            ValueListenableBuilder<double>(
              valueListenable: _pull,
              builder: (context, pull, _) {
                if (pull <= 0) return const SizedBox.shrink();
                // Centred in the gap the pull opens under the bar.
                return Positioned(
                  top:
                      widget.top +
                      math.max(0.0, (pull - kPullRefreshIconSize) / 2),
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Center(
                      child: PullRefreshIcon(
                        progress: pull / kPullToRefreshDistance,
                        refreshing: _refreshing,
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      );
}
