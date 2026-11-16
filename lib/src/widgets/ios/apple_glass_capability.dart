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

/// Whether this device can show Liquid Glass, and whether it should.
enum AppleGlassCapability {
  /// Before iOS 26, or not an iPhone/iPad.
  unsupported,

  /// iOS 26 on a device with too little memory to keep the effects smooth.
  limited,

  /// iOS 26 on a device that renders the effects smoothly.
  capable,
}

/// 6 GB devices report about 5.6 GiB and 4 GB devices under 4 GiB, so this
/// separates iPhone 11–13 from iPhone 13 Pro, 14 and newer.
const kAppleGlassMinMemoryBytes = 5 * 1000 * 1000 * 1000;

AppleGlassCapability classifyAppleGlass({
  required bool osSupported,
  required int? memoryBytes,
}) {
  if (!osSupported) return AppleGlassCapability.unsupported;
  // An unknown size keeps the glass the app has always shown on iOS 26.
  if (memoryBytes != null && memoryBytes < kAppleGlassMinMemoryBytes) {
    return AppleGlassCapability.limited;
  }
  return AppleGlassCapability.capable;
}

Future<AppleGlassCapability> appleGlassCapability() async {
  final supported = await appleGlassAvailable();
  if (!supported) return AppleGlassCapability.unsupported;
  int? memory;
  try {
    memory = await _channel.invokeMethod<int>('physicalMemory');
  } on MissingPluginException {
    memory = null;
  } on PlatformException {
    memory = null;
  }
  return classifyAppleGlass(osSupported: true, memoryBytes: memory);
}

bool supportsAppleGlass(BuildContext context) =>
    context.windowSizeClass == WindowSizeClass.compact &&
    appleGlassEnabled(context);

bool appleGlassEnabled(BuildContext context) =>
    context.dependOnInheritedWidgetOfExactType<AppleGlassScope>()?.available ??
    false;

/// What the device can do and whether glass is on for it.
AppleGlassCapability appleGlassCapabilityOf(BuildContext context) =>
    context.dependOnInheritedWidgetOfExactType<AppleGlassScope>()?.capability ??
    AppleGlassCapability.unsupported;

class AppleGlassScope extends InheritedWidget {
  const AppleGlassScope({
    super.key,
    required this.available,
    AppleGlassCapability? capability,
    required super.child,
  }) : capability =
           capability ??
           (available
               ? AppleGlassCapability.capable
               : AppleGlassCapability.unsupported);

  /// Glass is on: the device is capable and the user has not turned it off.
  final bool available;
  final AppleGlassCapability capability;

  @override
  bool updateShouldNotify(AppleGlassScope oldWidget) =>
      available != oldWidget.available || capability != oldWidget.capability;
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
