// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:math' as math;
import 'dart:ui' show SemanticsRole;

import 'package:material_ui/material_ui.dart';

import '../../utils/motion/reduce_motion.dart';
import 'apple_glass_capability.dart';
import 'apple_glass_surface.dart';

/// Presents existing popup entries on a UIKit glass surface when available.
Future<T?> showAppleGlassMenu<T>({
  required BuildContext context,
  required RelativeRect position,
  required List<PopupMenuEntry<T>> items,
  T? initialValue,
  ShapeBorder? shape,
  Color? color,
  Color? shadowColor,
  Color? surfaceTintColor,
  EdgeInsetsGeometry? menuPadding,
  double? elevation,
  BoxConstraints? constraints,
  AnimationStyle? popUpAnimationStyle,
  bool useRootNavigator = false,
  String? semanticLabel,
  Clip clipBehavior = Clip.none,
  RouteSettings? routeSettings,
  bool? requestFocus,
}) {
  if (items.isEmpty) return Future<T?>.value();
  if (!appleGlassEnabled(context)) {
    return showMenu<T>(
      context: context,
      position: position,
      items: items,
      initialValue: initialValue,
      shape: shape,
      color: color,
      shadowColor: shadowColor,
      surfaceTintColor: surfaceTintColor,
      menuPadding: menuPadding,
      elevation: elevation,
      constraints: constraints,
      popUpAnimationStyle: popUpAnimationStyle,
      useRootNavigator: useRootNavigator,
      semanticLabel: semanticLabel,
      clipBehavior: clipBehavior,
      routeSettings: routeSettings,
      requestFocus: requestFocus,
    );
  }

  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  final themes = InheritedTheme.capture(from: context, to: navigator.context);
  final material = MaterialLocalizations.of(context);
  final heading = semanticLabel ?? material.popupMenuLabel;
  final direction = Directionality.of(context);
  final duration = context.reduceMotion
      ? Duration.zero
      : popUpAnimationStyle?.duration ?? const Duration(milliseconds: 155);
  const corners = BorderRadius.all(Radius.circular(AppleGlassSurface.radius));

  return navigator.push<T>(
    RawDialogRoute<T>(
      barrierLabel: material.menuDismissLabel,
      barrierColor: Theme.of(context).colorScheme.scrim.withAlpha(0x42),
      transitionDuration: duration,
      settings: routeSettings,
      requestFocus: requestFocus,
      traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
      transitionBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(opacity: animation, child: child),
      pageBuilder: (context, animation, secondaryAnimation) => themes.wrap(
        Directionality(
          textDirection: direction,
          child: CustomSingleChildLayout(
            delegate: _GlassMenuLayout(
              anchor: position,
              insets: MediaQuery.paddingOf(context),
              keyboardInset: MediaQuery.viewInsetsOf(context).bottom,
              direction: direction,
              width: constraints?.maxWidth.isFinite == true
                  ? constraints!.maxWidth
                  : math.max(constraints?.minWidth ?? 0, 304),
              height: constraints?.maxHeight.isFinite == true
                  ? constraints!.maxHeight
                  : 520,
            ),
            child: Semantics(
              scopesRoute: true,
              namesRoute: true,
              explicitChildNodes: true,
              role: SemanticsRole.menu,
              label: heading,
              child: AppleGlassSurface(
                child: Material(
                  type: MaterialType.transparency,
                  borderRadius: corners,
                  clipBehavior: Clip.antiAlias,
                  child: SingleChildScrollView(
                    primary: false,
                    padding: menuPadding ?? const EdgeInsets.all(8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final item in items)
                          if (initialValue != null &&
                              item.represents(initialValue))
                            DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.08),
                              ),
                              child: item,
                            )
                          else
                            item,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _GlassMenuLayout extends SingleChildLayoutDelegate {
  const _GlassMenuLayout({
    required this.anchor,
    required this.insets,
    required this.keyboardInset,
    required this.direction,
    required this.width,
    required this.height,
  });

  final RelativeRect anchor;
  final EdgeInsets insets;
  final double keyboardInset;
  final TextDirection direction;
  final double width;
  final double height;

  static const double _edgeGap = 8;
  static const double _anchorGap = 4;

  double get _bottomInset => math.max(insets.bottom, keyboardInset);

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final maxWidth = math.max(
      0.0,
      constraints.maxWidth - insets.horizontal - 2 * _edgeGap,
    );
    final maxHeight = math.max(
      0.0,
      constraints.maxHeight - insets.top - _bottomInset - 2 * _edgeGap,
    );
    return BoxConstraints.tightFor(
      width: math.min(width, maxWidth),
    ).copyWith(maxHeight: math.min(height, maxHeight));
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final left = insets.left + _edgeGap;
    final right = math.max(
      left,
      size.width - insets.right - _edgeGap - childSize.width,
    );
    final top = insets.top + _edgeGap;
    final bottom = size.height - _bottomInset - _edgeGap;
    final rightward = anchor.left == anchor.right
        ? direction == TextDirection.ltr
        : anchor.left < anchor.right;
    final x = rightward
        ? anchor.left
        : size.width - anchor.right - childSize.width;
    final below = size.height - anchor.bottom + _anchorGap;
    final above = anchor.top - _anchorGap - childSize.height;
    final y = below + childSize.height <= bottom || above < top ? below : above;
    return Offset(
      x.clamp(left, right),
      y.clamp(top, math.max(top, bottom - childSize.height)),
    );
  }

  @override
  bool shouldRelayout(_GlassMenuLayout oldDelegate) =>
      anchor != oldDelegate.anchor ||
      insets != oldDelegate.insets ||
      keyboardInset != oldDelegate.keyboardInset ||
      direction != oldDelegate.direction ||
      width != oldDelegate.width ||
      height != oldDelegate.height;
}
