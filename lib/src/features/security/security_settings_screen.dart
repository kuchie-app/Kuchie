import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../utils/extensions/custom_extensions.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/compact_switch.dart';
import '../../widgets/desktop/desktop_top_bar.dart';
import '../../widgets/shell/detail_navigation_shell_screen.dart';
import '../settings/presentation/incognito/incognito_mode.dart';
import '../settings/widgets/settings_group_card/settings_group_card.dart';
import 'app_security.dart';

const _chevron = Icon(FluentIcons.chevron_right_24_regular);

void openSecuritySettings(BuildContext context) => unawaited(
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const SecuritySettingsScreen()),
  ),
);

/// A settings page with Kuchie's grouped rows.
class SettingsListPage extends StatelessWidget {
  const SettingsListPage({
    super.key,
    required this.title,
    required this.children,
    this.actions,
  });

  final String title;
  final List<Widget> children;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: detailNavigationAppBar(
      context,
      title: Text(title),
      actions: actions,
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: settingsPageConstraints(context),
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            0,
            8,
            0,
            MediaQuery.paddingOf(context).bottom + 16,
          ),
          children: children,
        ),
      ),
    ),
  );
}

/// App lock, lock delay and the app switcher cover. Shared by both
/// collections, since it guards the whole app.
class SecuritySettingsScreen extends ConsumerWidget {
  const SecuritySettingsScreen({super.key, this.showIncognito = true});

  final bool showIncognito;

  Future<void> _toggleLock(BuildContext context, bool value) async {
    final security = AppSecurityPreferences.instance;
    final l10n = context.l10n;
    final result = await security.setAppLock(value, reason: l10n.appLockReason);
    if (!context.mounted || result == AppAuthResult.success) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            result == AppAuthResult.unavailable
                ? l10n.appLockUnavailable
                : l10n.appLockNotVerified,
          ),
        ),
      );
  }

  String _delayLabel(BuildContext context, AppLockDelay delay) =>
      switch (delay) {
        AppLockDelay.immediately => context.l10n.appLockDelayImmediately,
        AppLockDelay.oneMinute => context.l10n.appLockDelayMinutes(1),
        AppLockDelay.fiveMinutes => context.l10n.appLockDelayMinutes(5),
        AppLockDelay.fifteenMinutes => context.l10n.appLockDelayMinutes(15),
        AppLockDelay.oneHour => context.l10n.appLockDelayHour,
      };

  Future<void> _chooseDelay(BuildContext context) async {
    final security = AppSecurityPreferences.instance;
    final chosen = await showAppBottomSheet<AppLockDelay>(
      context: context,
      builder: (sheet) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppSheetHeader(title: sheet.l10n.appLockDelay),
          for (final delay in AppLockDelay.values)
            ListTile(
              title: Text(_delayLabel(sheet, delay)),
              trailing: security.lockDelay.value == delay
                  ? const Icon(FluentIcons.checkmark_24_regular)
                  : null,
              onTap: () => Navigator.pop(sheet, delay),
            ),
        ],
      ),
    );
    if (chosen != null) await security.setLockDelay(chosen);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final security = AppSecurityPreferences.instance;
    unawaited(security.load());
    final incognito = ref.watch(incognitoModeProvider);
    return SettingsListPage(
      title: context.l10n.securityAndPrivacy,
      children: [
        ListenableBuilder(
          listenable: Listenable.merge([
            security.appLock,
            security.lockDelay,
            security.secureScreen,
            security.disableSharing,
          ]),
          builder: (context, _) => SettingsGroupCard(
            children: [
              SettingsGroupRow(
                icon: FluentIcons.lock_closed_24_regular,
                title: context.l10n.appLock,
                subtitle: context.l10n.appLockSubtitle,
                trailing: CompactSwitch(
                  value: security.appLock.value,
                  onChanged: (value) => _toggleLock(context, value),
                ),
                onTap: () => _toggleLock(context, !security.appLock.value),
              ),
              if (security.appLock.value)
                SettingsGroupRow(
                  icon: FluentIcons.timer_24_regular,
                  title: context.l10n.appLockDelay,
                  subtitle: _delayLabel(context, security.lockDelay.value),
                  trailing: _chevron,
                  onTap: () => _chooseDelay(context),
                ),
              SettingsGroupRow(
                icon: FluentIcons.eye_off_24_regular,
                title: context.l10n.secureScreen,
                subtitle: context.l10n.secureScreenSubtitle,
                trailing: CompactSwitch(
                  value: security.secureScreen.value,
                  onChanged: security.setSecureScreen,
                ),
                onTap: () =>
                    security.setSecureScreen(!security.secureScreen.value),
              ),
              SettingsGroupRow(
                icon: FluentIcons.share_ios_24_regular,
                title: context.l10n.disableContentSharing,
                subtitle: context.l10n.disableContentSharingSubtitle,
                trailing: CompactSwitch(
                  value: security.disableSharing.value,
                  onChanged: security.setDisableSharing,
                ),
                onTap: () =>
                    security.setDisableSharing(!security.disableSharing.value),
              ),
              if (showIncognito)
                SettingsGroupRow(
                  icon: FluentIcons.incognito_24_regular,
                  title: context.l10n.incognitoMode,
                  subtitle: context.l10n.incognitoModeDescription,
                  trailing: CompactSwitch(
                    value: incognito,
                    onChanged: (value) =>
                        ref.read(incognitoModeProvider.notifier).set(value),
                  ),
                  onTap: () =>
                      ref.read(incognitoModeProvider.notifier).set(!incognito),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
