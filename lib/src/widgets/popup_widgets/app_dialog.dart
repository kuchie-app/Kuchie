// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:material_ui/material_ui.dart';

import '../../utils/motion/reduce_motion.dart';
import '../ios/apple_glass_capability.dart';
import '../ios/apple_glass_surface.dart';

Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  bool useRootNavigator = true,
}) => showDialog<T>(
  context: context,
  builder: builder,
  barrierDismissible: barrierDismissible,
  useRootNavigator: useRootNavigator,
  animationStyle: context.motionStyle,
);

class AppDialogPanel extends StatelessWidget {
  const AppDialogPanel({
    super.key,
    required this.title,
    this.subtitle,
    this.content,
    this.actions = const [],
    this.showClose = false,
    this.scrollContent = true,
    this.constraints,
  });

  final String title;
  final String? subtitle;
  final Widget? content;
  final List<Widget> actions;
  final bool showClose;
  final bool scrollContent;
  final BoxConstraints? constraints;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = appleGlassEnabled(context);
    final heading = Semantics(
      header: true,
      child: Text(
        title,
        style: glass
            ? theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)
            : null,
      ),
    );
    final titleWidget = subtitle == null
        ? heading
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              heading,
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          );
    final close = IconButton(
      tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
      icon: const Icon(Icons.close_rounded, size: 20),
      style: IconButton.styleFrom(
        minimumSize: const Size.square(44),
        backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.08),
      ),
      onPressed: () => Navigator.maybePop(context),
    );
    final header = showClose
        ? Row(
            children: [
              Expanded(child: titleWidget),
              const SizedBox(width: 8),
              close,
            ],
          )
        : titleWidget;
    if (!glass) {
      return AlertDialog(
        title: header,
        content: content,
        actions: actions,
        constraints: constraints,
        scrollable: scrollContent,
      );
    }

    return _GlassDialog(
      title: header,
      content: content,
      actions: actions,
      constraints: constraints,
      scrollContent: scrollContent,
    );
  }
}

/// Keeps the Material alert contract for forms and rich content on other platforms.
class AdaptiveAppAlert extends StatelessWidget {
  const AdaptiveAppAlert({
    super.key,
    this.title,
    this.content,
    this.icon,
    this.actions,
    this.actionsAlignment,
    this.constraints,
    this.contentPadding,
    this.scrollable = false,
  });

  final Widget? title;
  final Widget? content;
  final Widget? icon;
  final List<Widget>? actions;
  final MainAxisAlignment? actionsAlignment;
  final BoxConstraints? constraints;
  final EdgeInsetsGeometry? contentPadding;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    if (!appleGlassEnabled(context)) {
      return AlertDialog(
        title: title,
        content: content,
        icon: icon,
        actions: actions,
        actionsAlignment: actionsAlignment,
        constraints: constraints,
        contentPadding: contentPadding,
        scrollable: scrollable,
      );
    }
    return _GlassDialog(
      title: title,
      content: content,
      icon: icon,
      actions: actions ?? const [],
      actionsAlignment: actionsAlignment,
      constraints: constraints,
      scrollContent: scrollable,
    );
  }
}

class _GlassDialog extends StatelessWidget {
  const _GlassDialog({
    required this.title,
    required this.content,
    required this.actions,
    required this.constraints,
    required this.scrollContent,
    this.icon,
    this.actionsAlignment,
  });

  final Widget? title;
  final Widget? content;
  final Widget? icon;
  final List<Widget> actions;
  final BoxConstraints? constraints;
  final bool scrollContent;
  final MainAxisAlignment? actionsAlignment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const corners = BorderRadius.all(Radius.circular(AppleGlassSurface.radius));
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      shape: const RoundedRectangleBorder(borderRadius: corners),
      constraints:
          constraints ?? const BoxConstraints(minWidth: 280, maxWidth: 360),
      child: AppleGlassSurface(
        child: Material(
          type: MaterialType.transparency,
          clipBehavior: Clip.antiAlias,
          shape: const RoundedRectangleBorder(borderRadius: corners),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (icon != null) ...[
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: icon!,
                  ),
                  const SizedBox(height: 8),
                ],
                if (title != null)
                  DefaultTextStyle.merge(
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    child: title!,
                  ),
                if (content != null) ...[
                  if (title != null) const SizedBox(height: 12),
                  Flexible(
                    child: DefaultTextStyle.merge(
                      style: theme.textTheme.bodyMedium,
                      child: scrollContent
                          ? SingleChildScrollView(child: content!)
                          : content!,
                    ),
                  ),
                ],
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  OverflowBar(
                    alignment: actionsAlignment ?? MainAxisAlignment.end,
                    overflowAlignment: OverflowBarAlignment.end,
                    spacing: 8,
                    overflowSpacing: 6,
                    children: actions,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
