// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Places the native backdrop behind Flutter content without intercepting input.
class AppleGlassSurface extends StatelessWidget {
  const AppleGlassSurface({super.key, required this.child});

  static const double radius = 32;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: UiKitView(
              key: ValueKey(brightness),
              viewType: 'kuchie/apple_liquid_glass/sheet',
              layoutDirection: Directionality.of(context),
              hitTestBehavior: PlatformViewHitTestBehavior.transparent,
              creationParams: {'dark': brightness == Brightness.dark},
              creationParamsCodec: const StandardMessageCodec(),
            ),
          ),
        ),
        child,
      ],
    );
  }
}
