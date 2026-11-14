// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:material_ui/material_ui.dart';

import 'apple_glass_capability.dart';
import 'apple_glass_popover.dart';

/// Retains Flutter's popup trigger and keyboard behavior; adapts its surface on iOS.
class AppleGlassPopupButton<T> extends PopupMenuButton<T> {
  const AppleGlassPopupButton({
    super.key,
    required super.itemBuilder,
    super.initialValue,
    super.onOpened,
    super.onSelected,
    super.onCanceled,
    super.tooltip,
    super.padding,
    super.child,
    super.borderRadius,
    super.icon,
    super.iconSize,
    super.offset,
    super.enabled,
    super.shape,
    super.constraints,
    super.position,
    super.useRootNavigator,
    super.popUpAnimationStyle,
    super.style,
  });

  @override
  PopupMenuButtonState<T> createState() => _AppleGlassPopupButtonState<T>();
}

class _AppleGlassPopupButtonState<T> extends PopupMenuButtonState<T> {
  bool _open = false;

  @override
  Widget build(BuildContext context) => Semantics(
    expanded: appleGlassEnabled(context) ? _open : null,
    child: super.build(context),
  );

  @override
  void showButtonMenu() async {
    if (!appleGlassEnabled(context)) {
      super.showButtonMenu();
      return;
    }
    if (_open) return;
    final overlay = Navigator.of(
      context,
      rootNavigator: widget.useRootNavigator,
    ).overlay?.context.findRenderObject();
    final anchor = context.findRenderObject();
    if (anchor is! RenderBox || overlay is! RenderBox) return;
    final items = widget.itemBuilder(context);
    if (items.isEmpty) return;
    final topLeft = overlay.globalToLocal(anchor.localToGlobal(widget.offset));
    final position = RelativeRect.fromRect(
      topLeft & anchor.size,
      Offset.zero & overlay.size,
    );
    widget.onOpened?.call();
    if (!mounted) return;
    setState(() => _open = true);
    final T? selected;
    try {
      selected = await showAppleGlassMenu<T>(
        context: context,
        position: position,
        items: items,
        initialValue: widget.initialValue,
        constraints: widget.constraints,
        useRootNavigator: widget.useRootNavigator,
        popUpAnimationStyle: widget.popUpAnimationStyle,
      );
    } finally {
      if (mounted) setState(() => _open = false);
    }
    if (!mounted) return;
    if (selected == null) {
      widget.onCanceled?.call();
    } else {
      widget.onSelected?.call(selected);
    }
  }
}
