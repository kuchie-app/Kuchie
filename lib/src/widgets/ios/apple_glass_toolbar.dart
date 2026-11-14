// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter/foundation.dart'
    show Factory, defaultTargetPlatform, kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../utils/extensions/custom_extensions.dart';
import '../../utils/motion/reduce_motion.dart';
import 'apple_glass_capability.dart';

const _viewType = 'kuchie/apple_liquid_glass/toolbar';

class AppleGlassToolbarMenuItem {
  const AppleGlassToolbarMenuItem({
    required this.id,
    required this.title,
    required this.symbol,
    required this.fallbackIcon,
    this.onSelected,
    this.selected = false,
    this.destructive = false,
    this.children = const [],
  }) : assert(onSelected == null || children.length == 0);

  final String id;
  final String title;
  final String symbol;
  final IconData fallbackIcon;
  final VoidCallback? onSelected;
  final bool selected;
  final bool destructive;
  final List<AppleGlassToolbarMenuItem> children;

  bool get enabled => onSelected != null || children.isNotEmpty;

  Map<String, Object> toNative() => {
    'id': id,
    'title': title,
    'symbol': symbol,
    'enabled': enabled,
    'selected': selected,
    'destructive': destructive,
    'children': [for (final item in children) item.toNative()],
  };

  bool _matches(AppleGlassToolbarMenuItem other) =>
      id == other.id &&
      title == other.title &&
      symbol == other.symbol &&
      enabled == other.enabled &&
      selected == other.selected &&
      destructive == other.destructive &&
      _sameMenu(children, other.children);

  static bool _sameMenu(
    List<AppleGlassToolbarMenuItem> first,
    List<AppleGlassToolbarMenuItem> second,
  ) =>
      identical(first, second) ||
      (first.length == second.length &&
          first.asMap().entries.every(
            (entry) => entry.value._matches(second[entry.key]),
          ));

  VoidCallback? _callback(String selectedID) {
    if (id == selectedID) return onSelected;
    for (final item in children) {
      final callback = item._callback(selectedID);
      if (callback != null) return callback;
    }
    return null;
  }

  static List<PopupMenuEntry<AppleGlassToolbarMenuItem>> _fallbackEntries(
    BuildContext context,
    List<AppleGlassToolbarMenuItem> items,
  ) => [
    for (final item in items)
      PopupMenuItem<AppleGlassToolbarMenuItem>(
        value: item,
        enabled: item.enabled,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          textColor: item.destructive ? context.colorScheme.error : null,
          iconColor: item.destructive ? context.colorScheme.error : null,
          leading: Icon(item.selected ? Icons.check : item.fallbackIcon),
          title: Text(item.title),
          trailing: item.children.isEmpty
              ? null
              : const Icon(Icons.chevron_right),
        ),
      ),
  ];
}

class AppleGlassToolbarAction {
  const AppleGlassToolbarAction({
    required this.id,
    required this.symbol,
    required this.label,
    required this.onPressed,
    this.fallbackIcon,
    this.fallback,
    this.color,
    this.title,
    this.alignTitleLeading = false,
    this.accessibilityValue,
    this.width = 48,
    this.menu = const [],
  }) : assert(fallbackIcon != null || fallback != null),
       assert(onPressed == null || menu.length == 0),
       assert(width >= 48);

  final String id;
  final String symbol;
  final String label;
  final VoidCallback? onPressed;
  final IconData? fallbackIcon;
  final Widget? fallback;
  final Color? color;
  final String? title;
  final bool alignTitleLeading;
  final String? accessibilityValue;
  final double width;
  final List<AppleGlassToolbarMenuItem> menu;

  bool get _enabled => onPressed != null || menu.any((item) => item.enabled);

  ({
    String id,
    String symbol,
    String label,
    bool enabled,
    int? color,
    String? title,
    bool alignTitleLeading,
    String? accessibilityValue,
    double width,
  })
  get _native => (
    id: id,
    symbol: symbol,
    label: label,
    enabled: _enabled,
    color: color?.toARGB32(),
    title: title,
    alignTitleLeading: alignTitleLeading,
    accessibilityValue: accessibilityValue,
    width: width,
  );

  bool _matches(AppleGlassToolbarAction other) =>
      _native == other._native &&
      AppleGlassToolbarMenuItem._sameMenu(menu, other.menu);

  Widget _fallbackButton() =>
      fallback ??
      (menu.isNotEmpty
          ? _AppleGlassToolbarFallbackMenu(this)
          : IconButton(
              icon: Icon(fallbackIcon),
              tooltip: label,
              color: color,
              onPressed: onPressed,
            ));
}

class _AppleGlassToolbarFallbackMenu extends StatelessWidget {
  const _AppleGlassToolbarFallbackMenu(this.action);

  final AppleGlassToolbarAction action;

  @override
  Widget build(BuildContext context) {
    Future<void> select(AppleGlassToolbarMenuItem item) async {
      if (item.children.isEmpty) {
        item.onSelected?.call();
        return;
      }
      final anchor = context.findRenderObject()! as RenderBox;
      final overlay =
          Navigator.of(context).overlay!.context.findRenderObject()!
              as RenderBox;
      final offset = anchor.localToGlobal(Offset.zero, ancestor: overlay);
      final position = RelativeRect.fromSize(
        offset & anchor.size,
        overlay.size,
      );
      while (item.children.isNotEmpty) {
        if (!context.mounted) return;
        final next = await showMenu<AppleGlassToolbarMenuItem>(
          context: context,
          position: position,
          items: AppleGlassToolbarMenuItem._fallbackEntries(
            context,
            item.children,
          ),
          popUpAnimationStyle: context.motionStyle,
        );
        if (next == null) return;
        item = next;
      }
      if (context.mounted) item.onSelected?.call();
    }

    return PopupMenuButton<AppleGlassToolbarMenuItem>(
      icon: Icon(action.fallbackIcon, color: action.color),
      tooltip: action.label,
      enabled: action._enabled,
      onSelected: select,
      itemBuilder: (context) =>
          AppleGlassToolbarMenuItem._fallbackEntries(context, action.menu),
      popUpAnimationStyle: context.motionStyle,
    );
  }
}

class AppleGlassToolbarButton extends StatelessWidget {
  const AppleGlassToolbarButton({
    super.key,
    required this.id,
    required this.symbol,
    required this.label,
    required this.onPressed,
    this.fallbackIcon,
    this.fallback,
    this.color,
    this.title,
    this.alignTitleLeading = false,
    this.accessibilityValue,
    this.width = 48,
    this.dark,
    this.menu = const [],
    this.allowParentScroll = false,
  }) : assert(fallbackIcon != null || fallback != null);

  final String id;
  final String symbol;
  final String label;
  final VoidCallback? onPressed;
  final IconData? fallbackIcon;
  final Widget? fallback;
  final Color? color;
  final String? title;
  final bool alignTitleLeading;
  final String? accessibilityValue;
  final double width;
  final bool? dark;
  final List<AppleGlassToolbarMenuItem> menu;
  final bool allowParentScroll;

  @override
  Widget build(BuildContext context) => AppleGlassToolbar(
    dark: dark,
    allowParentScroll: allowParentScroll,
    actions: [
      AppleGlassToolbarAction(
        id: id,
        symbol: symbol,
        label: label,
        onPressed: onPressed,
        fallbackIcon: fallbackIcon,
        fallback: fallback,
        color: color,
        title: title,
        alignTitleLeading: alignTitleLeading,
        accessibilityValue: accessibilityValue,
        width: width,
        menu: menu,
      ),
    ],
  );
}

class AppleGlassToolbar extends StatelessWidget {
  const AppleGlassToolbar({
    super.key,
    required this.actions,
    this.fallback,
    this.dark,
    this.joined = false,
    this.allowParentScroll = false,
  });

  final List<AppleGlassToolbarAction> actions;
  final Widget? fallback;
  final bool? dark;
  final bool joined;
  final bool allowParentScroll;

  Widget _fallback() =>
      fallback ??
      (actions.length == 1
          ? actions.single._fallbackButton()
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final action in actions) action._fallbackButton(),
              ],
            ));

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();
    if (kIsWeb ||
        defaultTargetPlatform != TargetPlatform.iOS ||
        !supportsAppleGlass(context)) {
      return _fallback();
    }
    return Center(
      widthFactor: 1,
      heightFactor: 1,
      child: _NativeGlassToolbar(
        actions: actions,
        dark: dark ?? (Theme.of(context).brightness == Brightness.dark),
        joined: joined,
        allowParentScroll: allowParentScroll,
        direction: Directionality.of(context),
      ),
    );
  }
}

class _NativeGlassToolbar extends StatefulWidget {
  const _NativeGlassToolbar({
    required this.actions,
    required this.dark,
    required this.joined,
    required this.allowParentScroll,
    required this.direction,
  });

  final List<AppleGlassToolbarAction> actions;
  final bool dark;
  final bool joined;
  final bool allowParentScroll;
  final TextDirection direction;

  Map<String, Object?> get configuration => {
    'dark': dark,
    'joined': joined,
    'rtl': direction == TextDirection.rtl,
    'actions': [
      for (final action in actions)
        {
          'id': action.id,
          'symbol': action.symbol,
          'label': action.label,
          'enabled': action._enabled,
          'width': action.width,
          if (action.menu.isNotEmpty)
            'menu': [for (final item in action.menu) item.toNative()],
          if (action.title != null) 'title': action.title,
          if (action.alignTitleLeading) 'alignTitleLeading': true,
          if (action.accessibilityValue != null)
            'accessibilityValue': action.accessibilityValue,
          if (action.color != null) 'color': action.color!.toARGB32(),
        },
    ],
  };

  @override
  State<_NativeGlassToolbar> createState() => _NativeGlassToolbarState();
}

class _NativeGlassToolbarState extends State<_NativeGlassToolbar> {
  MethodChannel? _channel;

  void _created(int viewId) {
    if (!mounted) return;
    _channel = MethodChannel('$_viewType/$viewId')
      ..setMethodCallHandler((call) async {
        if (!mounted) return;
        if (call.method == 'menuSelect') {
          final selection = call.arguments;
          if (selection is! Map || selection['item'] is! String) return;
          for (final action in widget.actions) {
            if (action.id != selection['action']) continue;
            for (final item in action.menu) {
              final callback = item._callback(selection['item'] as String);
              if (callback == null) continue;
              callback();
              return;
            }
          }
          return;
        }
        if (call.method != 'press') throw MissingPluginException();
        for (final action in widget.actions) {
          if (action.id == call.arguments) {
            action.onPressed?.call();
            return;
          }
        }
      });
    _update();
  }

  void _update() =>
      unawaited(_channel?.invokeMethod<void>('update', widget.configuration));

  @override
  void didUpdateWidget(_NativeGlassToolbar previous) {
    super.didUpdateWidget(previous);
    if (previous.dark != widget.dark ||
        previous.joined != widget.joined ||
        previous.direction != widget.direction ||
        previous.actions.length != widget.actions.length ||
        widget.actions.asMap().entries.any(
          (entry) => !entry.value._matches(previous.actions[entry.key]),
        )) {
      _update();
    }
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: widget.actions.fold<double>(
      0,
      (width, action) => width + action.width,
    ),
    height: 48,
    child: UiKitView(
      viewType: _viewType,
      layoutDirection: widget.direction,
      creationParams: widget.configuration,
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: _created,
      gestureRecognizers: widget.allowParentScroll
          ? const {}
          : {Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new)},
    ),
  );
}
