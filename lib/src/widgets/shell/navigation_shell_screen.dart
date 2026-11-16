// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pub_semver/pub_semver.dart';

import '../../constants/app_constants.dart';
import '../../constants/app_distribution.dart';
import '../../features/about/data/about_repository.dart';
import '../../features/about/data/web_update_browser.dart';
import '../../features/about/presentation/about/widget/app_update_dialog.dart';
import '../../features/about/presentation/about/widget/update_alert_checker.dart';
import '../../features/account/data/account_providers.dart';
import '../../features/auth/presentation/basic_auth_deprecation.dart';
import '../../features/offline/data/account_storage_recovery_state.dart';
import '../../features/offline/presentation/account_storage_recovery_banner.dart';
import '../../global_providers/package_info.dart';
import '../../graphql/__generated__/schema.graphql.dart';
import '../../utils/extensions/custom_extensions.dart';
import '../../utils/misc/toast/toast.dart';
import '../desktop/desktop_page_frame.dart';
import '../desktop/desktop_top_bar.dart';
import '../ios/apple_glass_capability.dart';
import 'big_screen_navigation_bar.dart';
import 'incognito_banner.dart';
import 'small_screen_navigation_bar.dart';
import 'update_banner_state.dart';
import 'update_progress_banner.dart';

class NavigationShellScreen extends HookConsumerWidget {
  const NavigationShellScreen({super.key, required this.child});
  final StatefulNavigationShell child;

  Future<void> checkForUpdate({
    required String? title,
    required BuildContext context,
    required WidgetRef ref,
    required Future<AsyncValue<Version?>> Function() updateCallback,
    required Toast? toast,
  }) async {
    final AsyncValue<Version?> versionResult = await updateCallback();
    toast?.close();
    if (!context.mounted) return;
    versionResult.whenOrNull(
      data: (version) {
        if (version == null) return;
        final dismissed = ref.read(dismissedUpdateVersionProvider);
        if (dismissed != null && dismissed.isNotEmpty) {
          Version? skipped;
          try {
            skipped = Version.parse(dismissed);
          } catch (_) {
            skipped = null;
          }
          if (skipped != null && version.compareTo(skipped) <= 0) return;
        }
        appUpdateDialog(
          title: title ?? kAppName,
          newRelease: "v${version.canonicalizedVersion}",
          context: context,
          toast: toast,
          onSkipChanged: (skip) => ref
              .read(dismissedUpdateVersionProvider.notifier)
              .update(skip ? version.canonicalizedVersion : ''),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serverHosted = ref.watch(serverHostedWebProvider);
    final canManage = ref
        .watch(settledAccountAccessProvider)
        .allows(Enum$UserPermission.MANAGE_SETTINGS);
    useEffect(() {
      final checker = UpdateAlertChecker(
        context,
        ProviderScope.containerOf(context, listen: false),
      );
      Future.microtask(checker.start);
      return checker.dispose;
    }, [serverHosted, canManage]);
    useEffect(() {
      if (!serverHosted) {
        if (!supportsClientReleaseChecks) return null;
        Future.microtask(() async {
          if (!context.mounted) return;
          await ref.read(startupWebRevisionProvider.future);
          if (!context.mounted || ref.read(serverHostedWebProvider)) return;
          await checkForUpdate(
            title: ref.read(packageInfoProvider).appName,
            context: context,
            ref: ref,
            updateCallback: ref.read(aboutRepositoryProvider).checkUpdate,
            toast: ref.read(toastProvider),
          );
        });
        return null;
      }

      // Widget subscriptions pause when About or Settings covers this shell.
      final container = ProviderScope.containerOf(context, listen: false);
      final messenger = ScaffoldMessenger.of(context);
      ScaffoldFeatureController<MaterialBanner, MaterialBannerClosedReason>?
      banner;
      bool active = true;
      final reloadSubscription = container.listen(
        webBuildReloadRequiredProvider,
        (previous, required) {
          if (!required || banner != null) return;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (active && context.mounted && banner == null) {
              banner = messenger.showMaterialBanner(
                webBuildReloadBanner(context),
              );
            }
          });
          WidgetsBinding.instance.ensureVisualUpdate();
        },
        fireImmediately: true,
      );
      void checkInstalledBuild() {
        container.read(webBuildReloadRequiredProvider.notifier).check();
      }

      checkInstalledBuild();
      final removeListeners = listenForWebUpdate(checkInstalledBuild);
      return () {
        active = false;
        removeListeners();
        reloadSubscription.close();
        if (messenger.mounted) banner?.close();
      };
    }, [serverHosted]);
    useEffect(() {
      Future.microtask(() {
        if (context.mounted) {
          maybeShowBasicAuthDeprecation(context: context, ref: ref);
        }
      });
      return null;
    }, const []);

    final compact = context.windowSizeClass < WindowSizeClass.medium;
    final glass = supportsAppleGlass(context);
    final branchOrder = switch ((compact, glass)) {
      (true, true) => const [0, 1, 3, 2, 5],
      (true, false) => const [0, 1, 3, 4, 5],
      (false, _) => const [0, 1, 2, 3, 4, 5],
    };
    // Downloads opens from More on the Liquid Glass tab bar.
    final branchSelection = branchOrder.indexOf(child.currentIndex);
    final tabSelection = branchSelection < 0
        ? branchOrder.length - 1
        : branchSelection;

    // goBranch builds no back stack; Back from a non-home root must select Library.
    const homeBranch = 0;
    void switchTo(int navBarIndex) {
      final target = branchOrder[navBarIndex];
      child.goBranch(target, initialLocation: target == child.currentIndex);
    }

    // Use body context after Scaffold consumes keyboard insets; the banner already reserves the status bar.
    final updateBannerVisible = ref.watch(updateBannerVisibleProvider);
    final bannerVisible =
        updateBannerVisible ||
        ref.watch(accountStorageRecoveryProvider) != null;
    final content = bannerVisible
        ? Builder(
            builder: (context) => MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: child,
            ),
          )
        : child;

    final Widget scaffold;
    if (context.windowSizeClass >= WindowSizeClass.medium) {
      scaffold = Material(
        color: Theme.of(context).scaffoldBackgroundColor,
        // Without a bottom bar, protect rail/content from system navigation controls and cutouts.
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
                      selectedIndex: child.currentIndex,
                      onDestinationSelected: switchTo,
                    ),
                    // Root Scaffold for banners and snackbars: right of the rail, below the top bar.
                    Expanded(
                      child: Scaffold(
                        body: Column(
                          children: [
                            const UpdateProgressBanner(),
                            AccountStorageRecoveryBanner(
                              insetTop: !updateBannerVisible,
                            ),
                            Expanded(
                              child: DesktopPageFrame(
                                wrapsNavigator: true,
                                child: content,
                              ),
                            ),
                            const IncognitoBanner(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      scaffold = Scaffold(
        extendBody: glass,
        body: Column(
          children: [
            const UpdateProgressBanner(),
            AccountStorageRecoveryBanner(insetTop: !updateBannerVisible),
            if (glass) const IncognitoBanner(),
            Expanded(
              child: glass
                  ? AppleGlassDockScope(
                      height: NavigationBarTheme.of(context).height ?? 80,
                      child: content,
                    )
                  : content,
            ),
            if (!glass) const IncognitoBanner(),
          ],
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        bottomNavigationBar: SmallScreenNavigationBar(
          selectedIndex: tabSelection,
          glassLayout: glass,
          onDestinationSelected: switchTo,
        ),
      );
    }

    // go_router 14.x skips shell PopScope at branch roots; intercept the manifest-enabled legacy Back path.
    return BackButtonListener(
      onBackButtonPressed: () async {
        if (child.currentIndex != homeBranch &&
            !GoRouter.of(context).canPop()) {
          child.goBranch(homeBranch);
          return true; // handled — do not exit
        }
        return false;
      },
      child: scaffold,
    );
  }
}
