// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:material_ui/material_ui.dart';

import '../utils/motion/reduce_motion.dart';
import 'ios/apple_glass_capability.dart';
import 'ios/apple_glass_surface.dart';

Future<T?> showAppBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool useRootNavigator = true,
  bool isDismissible = true,
  bool enableDrag = true,
  bool showDragHandle = true,
  Color? backgroundColor,
  BoxConstraints? constraints,
  Color? barrierColor,
  RouteSettings? routeSettings,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: isScrollControlled,
  useRootNavigator: useRootNavigator,
  isDismissible: isDismissible,
  enableDrag: enableDrag,
  showDragHandle: false,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  elevation: 0,
  constraints: constraints,
  barrierColor: barrierColor,
  routeSettings: routeSettings,
  sheetAnimationStyle: context.motionStyle,
  builder: (context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: AppSheetSurface(
      backgroundColor: backgroundColor,
      showDragHandle: enableDrag && showDragHandle,
      child: Builder(builder: builder),
    ),
  ),
);

class AppSheetSurface extends StatelessWidget {
  const AppSheetSurface({
    super.key,
    required this.child,
    this.showDragHandle = true,
    this.backgroundColor,
  });

  final Widget child;
  final bool showDragHandle;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final glass = supportsAppleGlass(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final content = Material(
      color: glass ? Colors.transparent : backgroundColor ?? colors.surface,
      borderRadius: glass
          ? const BorderRadius.all(Radius.circular(AppleGlassSurface.radius))
          : const BorderRadius.vertical(top: Radius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        minimum: EdgeInsets.only(bottom: glass ? 8 : 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showDragHandle)
              ExcludeSemantics(
                child: Center(
                  heightFactor: 4,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.onSurfaceVariant.withValues(alpha: 0.55),
                      borderRadius: const BorderRadius.all(Radius.circular(2)),
                    ),
                    child: const SizedBox(width: 34, height: 4),
                  ),
                ),
              )
            else
              const SizedBox(height: 8),
            Flexible(child: child),
          ],
        ),
      ),
    );
    if (!glass) return content;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      child: AppleGlassSurface(child: content),
    );
  }
}

class AppSheetHeader extends StatelessWidget {
  const AppSheetHeader({
    super.key,
    required this.title,
    this.trailing,
    this.showClose = true,
    this.onClose,
  });

  final String title;
  final Widget? trailing;
  final bool showClose;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 2, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          if (showClose) ...[
            const SizedBox(width: 8),
            IconButton(
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              icon: const Icon(Icons.close_rounded, size: 20),
              onPressed: onClose ?? () => Navigator.of(context).maybePop(),
              style: IconButton.styleFrom(
                minimumSize: const Size.square(44),
                backgroundColor: theme.colorScheme.onSurface.withValues(
                  alpha: 0.08,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
