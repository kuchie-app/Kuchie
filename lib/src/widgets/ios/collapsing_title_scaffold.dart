import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../../utils/theme/brand.dart';
import '../pull_refresh_indicator.dart';
import '../shell/detail_navigation_shell_screen.dart';
import 'apple_glass_capability.dart';
import 'apple_glass_floating_header.dart';

/// A browse screen with a large title that scrolls up into the navigation
/// bar and a row of filters that stays pinned under it, as in iOS apps.
///
/// [body] scrolls behind the bar and the filters. It reads its top padding
/// from [AppleGlassFloatingHeader.insetOf], and must report scrolling through
/// [ScrollNotification]s at depth 0.
///
/// With [onRefresh], pulling the content down moves the title and filters
/// down with it and shows the refresh arrow above the title; letting go past
/// the threshold refreshes.
class CollapsingTitleScaffold extends StatefulWidget {
  const CollapsingTitleScaffold({
    super.key,
    required this.title,
    this.subtitle,
    this.below,
    required this.pinned,
    required this.actions,
    required this.body,
    this.onRefresh,
  });

  final Future<void> Function()? onRefresh;

  final String title;
  final String? subtitle;

  /// Shown under the subtitle and scrolled away with it, such as a search
  /// field or a status line.
  final Widget? below;

  /// Stays under the navigation bar once the title has scrolled away.
  final PreferredSizeWidget pinned;
  final List<Widget> actions;
  final Widget body;

  @override
  State<CollapsingTitleScaffold> createState() =>
      _CollapsingTitleScaffoldState();
}

class _CollapsingTitleScaffoldState extends State<CollapsingTitleScaffold> {
  /// Scroll position of the body; negative while it is pulled down.
  final _offset = ValueNotifier<double>(0);

  // A first-frame estimate for one title line and one subtitle line, so the
  // filters do not jump when the measured height arrives.
  double _headerHeight = 76;

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    final pixels = notification.metrics.pixels;
    if (notification.depth == 0) {
      // While pulling to refresh, the title and filters follow the content.
      _offset.value = widget.onRefresh == null ? math.max(0, pixels) : pixels;
    } else if (notification.depth == 1 &&
        widget.onRefresh != null &&
        _offset.value <= 0) {
      // An empty or error state scrolls on its own; follow only its pull.
      _offset.value = math.min(
        0,
        pixels - notification.metrics.minScrollExtent,
      );
    }
    return false;
  }

  void _onHeaderSize(Size size) {
    if (mounted && (size.height - _headerHeight).abs() > .5) {
      setState(() => _headerHeight = size.height);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final barBottom = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final pinnedHeight = widget.pinned.preferredSize.height;
    final inset = barBottom + _headerHeight + pinnedHeight + 8;
    final glass = supportsAppleGlass(context);
    final surface = theme.scaffoldBackgroundColor;

    final below = widget.below;
    final header = IgnorePointer(
      ignoring: below == null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
              20,
              4,
              20,
              below == null ? 10 : 0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (widget.subtitle case final subtitle?)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          // Full width, on the same side margins as the pinned segments.
          if (below != null)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 10),
              child: below,
            ),
        ],
      ),
    );

    final appBar = PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: ValueListenableBuilder<double>(
        valueListenable: _offset,
        builder: (context, offset, _) {
          // The bar darkens as content slides under it; the small title
          // appears once most of the large one has gone.
          final covered = (offset / math.max(1, _headerHeight)).clamp(0.0, 1.0);
          final titleOpacity =
              ((offset - _headerHeight * .55) / (_headerHeight * .45)).clamp(
                0.0,
                1.0,
              );
          return detailNavigationBar(
            context,
            (leading) => AppBar(
              leading: leading,
              centerTitle: true,
              elevation: 0,
              scrolledUnderElevation: 0,
              surfaceTintColor: Colors.transparent,
              backgroundColor: glass
                  ? Colors.transparent
                  : Color.lerp(surface.withValues(alpha: 0), surface, covered),
              flexibleSpace: glass
                  ? IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            // Light scrim only, for the status bar and title;
                            // the covers stay visible behind the bar.
                            colors: [
                              OnImage.shadow.withValues(alpha: .35 * covered),
                              OnImage.shadow.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    )
                  : null,
              title: Opacity(
                opacity: titleOpacity,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (widget.subtitle case final subtitle?)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              actions: widget.actions,
            ),
          );
        },
      ),
    );

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: appBar,
      body: _withPullToRefresh(
        barBottom,
        NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: Stack(
            children: [
              Positioned.fill(
                child: AppleGlassFloatingHeader(
                  inset: inset,
                  child: widget.body,
                ),
              ),
              // Covers scrolling under the bar and the filters blur, as on
              // iOS. Built only once content is under the bar, so a resting
              // screen pays nothing for it.
              if (glass)
                ValueListenableBuilder<double>(
                  valueListenable: _offset,
                  builder: (context, offset, _) {
                    final covered = (offset / math.max(1, _headerHeight)).clamp(
                      0.0,
                      1.0,
                    );
                    if (covered < .02) return const SizedBox.shrink();
                    final bottom =
                        math.max(
                          barBottom,
                          barBottom + _headerHeight - offset,
                        ) +
                        widget.pinned.preferredSize.height;
                    return Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: bottom,
                      child: IgnorePointer(
                        child: ClipRect(
                          child: BackdropFilter(
                            filter: ImageFilter.blur(
                              sigmaX: 6 * covered,
                              sigmaY: 6 * covered,
                            ),
                            child: ColoredBox(
                              color: OnImage.shadow.withValues(
                                alpha: .12 * covered,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ValueListenableBuilder<double>(
                valueListenable: _offset,
                builder: (context, offset, child) {
                  final hidden = offset >= _headerHeight;
                  return Positioned(
                    top: barBottom - offset,
                    left: 0,
                    right: 0,
                    child: Visibility(
                      visible: !hidden,
                      maintainState: true,
                      maintainSize: true,
                      maintainAnimation: true,
                      child: Opacity(
                        opacity: (1 - offset / math.max(1, _headerHeight))
                            .clamp(0.0, 1.0),
                        child: child,
                      ),
                    ),
                  );
                },
                child: _SizeReporter(onSize: _onHeaderSize, child: header),
              ),
              ValueListenableBuilder<double>(
                valueListenable: _offset,
                builder: (context, offset, child) => Positioned(
                  top: math.max(barBottom, barBottom + _headerHeight - offset),
                  left: 0,
                  right: 0,
                  child: child!,
                ),
                // Glass chips float over the covers; plain buttons need a
                // backdrop to stay readable.
                child: glass
                    ? widget.pinned
                    : ColoredBox(color: surface, child: widget.pinned),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _withPullToRefresh(double barBottom, Widget child) =>
      switch (widget.onRefresh) {
        final onRefresh? => PullToRefresh(
          onRefresh: onRefresh,
          top: barBottom,
          child: child,
        ),
        null => child,
      };
}

/// Reports its child's size after layout.
class _SizeReporter extends SingleChildRenderObjectWidget {
  const _SizeReporter({required this.onSize, required super.child});

  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSizeReporter(onSize);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSizeReporter renderObject,
  ) => renderObject.onSize = onSize;
}

class _RenderSizeReporter extends RenderProxyBox {
  _RenderSizeReporter(this.onSize);

  ValueChanged<Size> onSize;
  Size? _reported;

  @override
  void performLayout() {
    super.performLayout();
    final measured = size;
    if (measured == _reported) return;
    _reported = measured;
    SchedulerBinding.instance.addPostFrameCallback((_) => onSize(measured));
  }
}
