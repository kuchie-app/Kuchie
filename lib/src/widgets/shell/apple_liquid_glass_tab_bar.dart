// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter/foundation.dart' show Factory, listEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../constants/navigation_bar_data.dart';

const _viewType = 'kuchie/apple_liquid_glass/tab_bar';

typedef _Tab = ({String title, String symbol, String? badge});

class AppleLiquidGlassTabBar extends StatelessWidget {
  const AppleLiquidGlassTabBar({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.downloadsPaused,
    required this.extensionUpdates,
    required this.onDestinationSelected,
  });

  final List<NavigationBarData> tabs;
  final int selectedIndex;
  final bool downloadsPaused;
  final int extensionUpdates;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) => _NativeTabBar(
    tabs: [
      for (final tab in tabs)
        (
          title: tab.label(context),
          symbol: switch (tab.motion) {
            NavMotion.library => 'books.vertical.fill',
            NavMotion.updates => 'bolt.fill',
            NavMotion.history => 'clock.fill',
            NavMotion.browse => 'safari',
            NavMotion.downloads => 'arrow.down.circle',
            NavMotion.more => 'gearshape.fill',
          },
          badge: switch (tab.motion) {
            NavMotion.browse when extensionUpdates > 0 => '$extensionUpdates',
            NavMotion.downloads || NavMotion.more when downloadsPaused => '',
            _ => null,
          },
        ),
    ],
    selectedIndex: selectedIndex,
    dark: Theme.of(context).brightness == Brightness.dark,
    tint: Theme.of(context).colorScheme.primary,
    direction: Directionality.of(context),
    reduceMotion: MediaQuery.disableAnimationsOf(context),
    onDestinationSelected: onDestinationSelected,
  );
}

class _NativeTabBar extends StatefulWidget {
  const _NativeTabBar({
    required this.tabs,
    required this.selectedIndex,
    required this.dark,
    required this.tint,
    required this.direction,
    required this.reduceMotion,
    required this.onDestinationSelected,
  });

  final List<_Tab> tabs;
  final int selectedIndex;
  final bool dark;
  final Color tint;
  final TextDirection direction;
  final bool reduceMotion;
  final ValueChanged<int> onDestinationSelected;

  Map<String, Object?> get configuration => {
    'tabs': [
      for (final tab in tabs)
        {
          'title': tab.title,
          'symbol': tab.symbol,
          if (tab.badge != null) 'badge': tab.badge,
        },
    ],
    'selectedIndex': selectedIndex,
    'dark': dark,
    'tint': tint.toARGB32(),
    'rtl': direction == TextDirection.rtl,
    'reduceMotion': reduceMotion,
  };

  @override
  State<_NativeTabBar> createState() => _NativeTabBarState();
}

class _NativeTabBarState extends State<_NativeTabBar> {
  MethodChannel? _channel;

  void _onCreated(int id) {
    _channel = MethodChannel('$_viewType/$id')
      ..setMethodCallHandler((call) async {
        if (call.method != 'select') throw MissingPluginException();
        final index = call.arguments;
        if (mounted &&
            index is int &&
            index >= 0 &&
            index < widget.tabs.length) {
          widget.onDestinationSelected(index);
        }
      });
    // Creation is asynchronous; the route or badges may already have changed.
    _updateNative();
  }

  void _updateNative() =>
      unawaited(_channel?.invokeMethod<void>('update', widget.configuration));

  @override
  void didUpdateWidget(_NativeTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex ||
        oldWidget.dark != widget.dark ||
        oldWidget.tint != widget.tint ||
        oldWidget.direction != widget.direction ||
        oldWidget.reduceMotion != widget.reduceMotion ||
        !listEquals(oldWidget.tabs, widget.tabs)) {
      _updateNative();
    }
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height:
        (NavigationBarTheme.of(context).height ?? 80) +
        MediaQuery.viewPaddingOf(context).bottom,
    child: UiKitView(
      viewType: _viewType,
      layoutDirection: widget.direction,
      creationParams: widget.configuration,
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: _onCreated,
      gestureRecognizers: {
        Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
      },
    ),
  );
}
