import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../utils/extensions/custom_extensions.dart';

const _channel = MethodChannel('kuchie/apple_liquid_glass');

Future<bool> appleGlassAvailable() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return false;
  try {
    return await _channel.invokeMethod<bool>('isSupported') == true;
  } on MissingPluginException {
    return false;
  } on PlatformException {
    return false;
  }
}

bool supportsAppleGlass(BuildContext context) =>
    context.windowSizeClass == WindowSizeClass.compact &&
    appleGlassEnabled(context);

bool appleGlassEnabled(BuildContext context) =>
    context.dependOnInheritedWidgetOfExactType<AppleGlassScope>()?.available ??
    false;

class AppleGlassScope extends InheritedWidget {
  const AppleGlassScope({
    super.key,
    required this.available,
    required super.child,
  });

  final bool available;

  @override
  bool updateShouldNotify(AppleGlassScope oldWidget) =>
      available != oldWidget.available;
}

/// Positions a nested page action above the floating shell tab bar.
class AppleGlassDockClearance extends StatelessWidget {
  const AppleGlassDockClearance({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!supportsAppleGlass(context)) return child;
    final dock = context
        .dependOnInheritedWidgetOfExactType<AppleGlassDockScope>();
    if (dock == null || MediaQuery.viewInsetsOf(context).bottom > 0) {
      return child;
    }
    return Padding(
      padding: EdgeInsets.only(bottom: dock.height),
      child: child,
    );
  }
}

class AppleGlassDockScope extends InheritedWidget {
  const AppleGlassDockScope({
    super.key,
    required this.height,
    required super.child,
  });

  final double height;

  @override
  bool updateShouldNotify(AppleGlassDockScope oldWidget) =>
      oldWidget.height != height;
}
