// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter/foundation.dart'
    show Factory, defaultTargetPlatform, kIsWeb, listEquals, setEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'apple_glass_capability.dart';

const _viewType = 'kuchie/apple_glass_segments/control';

class AppleGlassSegments extends StatelessWidget
    implements PreferredSizeWidget {
  const AppleGlassSegments({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
    required this.fallback,
    this.symbols = const [],
    this.actionIndices = const {},
    this.scrollable = false,
    this.position,
  });

  final List<String> labels;
  final List<String> symbols;
  final Set<int> actionIndices;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final PreferredSizeWidget fallback;
  final bool scrollable;

  /// Where the selection sits while the pages are swiped, in segments: 1.4
  /// is 40% of the way from the second segment to the third. Pass the
  /// [TabController.animation] of a swipeable pager, so the selection
  /// follows the finger instead of jumping once the swipe ends.
  final Animation<double>? position;

  @override
  Size get preferredSize => fallback.preferredSize;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb ||
        defaultTargetPlatform != TargetPlatform.iOS ||
        !appleGlassEnabled(context) ||
        MediaQuery.textScalerOf(context).scale(14) > 18) {
      return fallback;
    }
    return SizedBox(
      height: preferredSize.height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        child: _NativeSegments(
          key: ValueKey(scrollable),
          labels: labels,
          symbols: symbols,
          actionIndices: actionIndices,
          selectedIndex: selectedIndex,
          onSelected: onSelected,
          scrollable: scrollable,
          position: position,
          dark: Theme.of(context).brightness == Brightness.dark,
          direction: Directionality.of(context),
          reduceMotion: MediaQuery.disableAnimationsOf(context),
        ),
      ),
    );
  }
}

class _NativeSegments extends StatefulWidget {
  const _NativeSegments({
    super.key,
    required this.labels,
    required this.symbols,
    required this.actionIndices,
    required this.selectedIndex,
    required this.onSelected,
    required this.scrollable,
    required this.position,
    required this.dark,
    required this.direction,
    required this.reduceMotion,
  });

  final Animation<double>? position;

  final List<String> labels;
  final List<String> symbols;
  final Set<int> actionIndices;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool scrollable;
  final bool dark;
  final TextDirection direction;
  final bool reduceMotion;

  Map<String, Object> get configuration => {
    'labels': labels,
    'symbols': symbols,
    'actionIndices': actionIndices.toList(),
    'selectedIndex': selectedIndex,
    'scrollable': scrollable,
    'dark': dark,
    'rtl': direction == TextDirection.rtl,
    'reduceMotion': reduceMotion,
  };

  @override
  State<_NativeSegments> createState() => _NativeSegmentsState();
}

class _NativeSegmentsState extends State<_NativeSegments> {
  MethodChannel? _channel;
  double? _sentPosition;

  @override
  void initState() {
    super.initState();
    widget.position?.addListener(_onPosition);
  }

  /// Moves the native selection with the swipe, one message per change.
  void _onPosition() {
    final position = widget.position?.value;
    if (position == null || _channel == null) return;
    if (_sentPosition case final sent? when (position - sent).abs() < .002) {
      return;
    }
    _sentPosition = position;
    unawaited(_invoke('position', position));
  }

  Future<void> _invoke(String method, Object? arguments) async {
    try {
      await _channel?.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // The native view can be released while a message is in flight.
    }
  }

  void _onCreated(int id) {
    _channel = MethodChannel('$_viewType/$id')
      ..setMethodCallHandler((call) async {
        if (call.method != 'select') throw MissingPluginException();
        final index = call.arguments;
        if (mounted &&
            index is int &&
            index >= 0 &&
            index < widget.labels.length) {
          widget.onSelected(index);
        }
      });
    unawaited(_updateNative());
  }

  Future<void> _updateNative() => _invoke('update', widget.configuration);

  @override
  void didUpdateWidget(_NativeSegments oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.position != widget.position) {
      oldWidget.position?.removeListener(_onPosition);
      widget.position?.addListener(_onPosition);
    }
    if (oldWidget.selectedIndex != widget.selectedIndex ||
        oldWidget.dark != widget.dark ||
        oldWidget.direction != widget.direction ||
        oldWidget.reduceMotion != widget.reduceMotion ||
        !listEquals(oldWidget.labels, widget.labels) ||
        !setEquals(oldWidget.actionIndices, widget.actionIndices) ||
        !listEquals(oldWidget.symbols, widget.symbols)) {
      unawaited(_updateNative());
    }
  }

  @override
  void dispose() {
    widget.position?.removeListener(_onPosition);
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => UiKitView(
    viewType: _viewType,
    layoutDirection: widget.direction,
    creationParams: widget.configuration,
    creationParamsCodec: const StandardMessageCodec(),
    onPlatformViewCreated: _onCreated,
    gestureRecognizers: {
      Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
    },
  );
}
