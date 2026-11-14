import 'package:material_ui/material_ui.dart';

import 'apple_glass_capability.dart';

class AppleGlassFloatingHeader extends InheritedWidget {
  const AppleGlassFloatingHeader({
    super.key,
    required this.inset,
    required super.child,
  });

  final double inset;

  static bool enabled(BuildContext context) =>
      supportsAppleGlass(context) &&
      MediaQuery.textScalerOf(context).scale(14) <= 18;

  static double insetOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<AppleGlassFloatingHeader>()
          ?.inset ??
      0;

  static Widget overlay({
    required PreferredSizeWidget header,
    required Widget child,
  }) => Stack(
    fit: StackFit.expand,
    children: [
      AppleGlassFloatingHeader(
        inset: header.preferredSize.height + 8,
        child: child,
      ),
      Positioned(top: 0, left: 0, right: 0, child: header),
    ],
  );

  @override
  bool updateShouldNotify(AppleGlassFloatingHeader oldWidget) =>
      oldWidget.inset != inset;
}
