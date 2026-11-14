import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../routes/router_config.dart';
import '../../utils/extensions/custom_extensions.dart';
import '../desktop/desktop_page_frame.dart';
import '../desktop/desktop_top_bar.dart';
import '../ios/apple_glass_capability.dart';
import '../ios/apple_glass_toolbar.dart';
import 'big_screen_navigation_bar.dart';

PreferredSizeWidget detailNavigationAppBar(
  BuildContext context, {
  required Widget title,
  List<Widget>? actions,
}) {
  final back = detailNavigationBackButton(context);
  if (back == null || !supportsAppleGlass(context)) {
    return AppBar(leading: back, title: title, actions: actions);
  }

  final theme = AppBarTheme.of(context);
  final toolbarHeight = theme.toolbarHeight ?? kToolbarHeight;
  final leadingWidth = theme.leadingWidth ?? kToolbarHeight;
  return PreferredSize(
    preferredSize: Size.fromHeight(toolbarHeight),
    child: Stack(
      children: [
        AppBar(
          leading: const SizedBox.shrink(),
          leadingWidth: leadingWidth,
          toolbarHeight: toolbarHeight,
          title: title,
          actions: actions,
        ),
        // Keep the title in Flutter's base layer, before the native glass view.
        Positioned.fill(
          child: SafeArea(
            bottom: false,
            child: Align(
              alignment: AlignmentDirectional.topStart,
              child: SizedBox(
                width: leadingWidth,
                height: toolbarHeight,
                child: back,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// Shell ModalRoute.canPop misses outer pages; consult GoRouter for back navigation.
Widget? detailNavigationBackButton(BuildContext context) {
  Widget back(VoidCallback onPressed) => Builder(
    builder: (context) => AppleGlassToolbarButton(
      id: 'back',
      symbol: 'chevron.backward',
      label: MaterialLocalizations.of(context).backButtonTooltip,
      onPressed: onPressed,
      fallback: BackButton(onPressed: onPressed),
    ),
  );
  final router = GoRouter.maybeOf(context);
  if (router == null) {
    final navigator = Navigator.of(context);
    return navigator.canPop() ? back(navigator.maybePop) : null;
  }
  (List<RouteMatch>, ShellRouteBase?) flatten() {
    final goMatches = <RouteMatch>[];
    ShellRouteBase? shell;
    void collect(List<RouteMatchBase> matches) {
      for (final match in matches) {
        if (match is ShellRouteMatch) {
          shell = match.route;
          collect(match.matches);
        } else if (match is RouteMatch) {
          goMatches.add(match);
        }
      }
    }

    collect(router.routerDelegate.currentConfiguration.matches);
    return (goMatches, shell);
  }

  Future<void> press() async {
    // Let the shell PopScope handle selection before falling back to GoRouter at its root.
    if (router.canPop()) {
      if (!await Navigator.of(context).maybePop()) router.pop();
      return;
    }
    final matches = flatten();
    if (matches.$1.length > 1) {
      router.go(matches.$1[matches.$1.length - 2].matchedLocation);
      return;
    }
    const LibraryRoute(categoryId: 0).go(context);
  }

  final current = flatten();
  if (current.$1.length == 1 && current.$2 is StatefulShellRoute) return null;
  return back(press);
}

class DetailNavigationShellScreen extends ConsumerWidget {
  const DetailNavigationShellScreen({
    super.key,
    this.framed = true,
    required this.child,
  });

  /// False when [child] is a navigator whose pages bring their own frames.
  final bool framed;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (context.windowSizeClass == WindowSizeClass.compact) return child;

    final shell = ref.read(navigationShellStateProvider).shell;
    final selectedIndex = shell?.currentIndex ?? 0;
    void goToBranch(int index) {
      if (shell != null) {
        shell.goBranch(index, initialLocation: index == selectedIndex);
        return;
      }
      switch (index) {
        case 0:
          const LibraryRoute(categoryId: 0).go(context);
        case 1:
          const UpdatesRoute().go(context);
        case 2:
          const HistoryTabRoute().go(context);
        case 3:
          const BrowseSourceRoute().go(context);
        case 4:
          const DownloadsRoute().go(context);
        case 5:
          const MoreRoute().go(context);
      }
    }

    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        child: Column(
          children: [
            if (showsMergedTopBar(context)) const DesktopTopBar(),
            // Move the keyed body across breakpoints without remounting scroll, focus or drafts.
            Expanded(
              key: const ValueKey('shellBody'),
              child: Row(
                children: [
                  BigScreenNavigationBar(
                    selectedIndex: selectedIndex,
                    onDestinationSelected: goToBranch,
                  ),
                  Expanded(
                    child: Scaffold(
                      body: framed ? DesktopPageFrame(child: child) : child,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
