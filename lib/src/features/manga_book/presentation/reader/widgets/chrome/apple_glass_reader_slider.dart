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

import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../utils/theme/brand.dart';
import '../../../../../../widgets/ios/apple_glass_capability.dart';

const _viewType = 'kuchie/apple_liquid_glass/reader_slider';

class AppleGlassReaderSlider extends StatelessWidget {
  const AppleGlassReaderSlider({
    super.key,
    required this.currentIndex,
    required this.pageCount,
    required this.reversed,
    required this.onChanged,
    required this.fallback,
  });

  final int currentIndex;
  final int pageCount;
  final bool reversed;
  final ValueChanged<int> onChanged;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    if (pageCount < 1) return const SizedBox.shrink();
    if (kIsWeb ||
        defaultTargetPlatform != TargetPlatform.iOS ||
        !supportsAppleGlass(context)) {
      return fallback;
    }
    return _NativeReaderSlider(
      index: currentIndex.clamp(0, pageCount - 1),
      count: pageCount,
      reversed: reversed,
      locale: Localizations.localeOf(context).toLanguageTag(),
      onChanged: onChanged,
    );
  }
}

class _NativeReaderSlider extends StatefulWidget {
  const _NativeReaderSlider({
    required this.index,
    required this.count,
    required this.reversed,
    required this.locale,
    required this.onChanged,
  });

  final int index;
  final int count;
  final bool reversed;
  final String locale;
  final ValueChanged<int> onChanged;

  @override
  State<_NativeReaderSlider> createState() => _NativeReaderSliderState();
}

class _NativeReaderSliderState extends State<_NativeReaderSlider> {
  MethodChannel? _channel;

  Map<String, Object> get _configuration => {
    'index': widget.index,
    'count': widget.count,
    'reversed': widget.reversed,
    'locale': widget.locale,
    'pageLabel': context.l10n.page(0).replaceFirst('0', '%@'),
    'tint': _trackColor(Theme.of(context).colorScheme).toARGB32(),
  };

  // The slider sits on dark glass; lift light-theme accents so the track reads.
  static Color _trackColor(ColorScheme scheme) =>
      scheme.brightness == Brightness.dark
      ? scheme.primary
      : Color.lerp(scheme.primary, OnImage.text, .45)!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _update();
  }

  void _created(int id) {
    if (!mounted) return;
    _channel = MethodChannel('$_viewType/$id')
      ..setMethodCallHandler((call) async {
        if (call.method != 'seek') throw MissingPluginException();
        final index = call.arguments;
        if (mounted && index is int && index >= 0 && index < widget.count) {
          widget.onChanged(index);
        }
      });
    _update();
  }

  void _update() =>
      unawaited(_channel?.invokeMethod<void>('update', _configuration));

  @override
  void didUpdateWidget(_NativeReaderSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index != oldWidget.index ||
        widget.count != oldWidget.count ||
        widget.reversed != oldWidget.reversed ||
        widget.locale != oldWidget.locale) {
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
    height: 46,
    child: UiKitView(
      viewType: _viewType,
      layoutDirection: TextDirection.ltr,
      gestureBlockingPolicy: UiKitViewGestureBlockingPolicy.doNotBlockGesture,
      creationParams: _configuration,
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: _created,
      gestureRecognizers: {
        Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
      },
    ),
  );
}
