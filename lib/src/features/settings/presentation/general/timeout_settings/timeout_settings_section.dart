import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../constants/timeout_constants.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../widgets/compact_switch.dart';
import '../../../../../widgets/input_popup/domain/settings_prop_type.dart';
import '../../../../../widgets/input_popup/settings_prop_tile.dart';
import '../../../data/server_connection/request_timeout.dart';
import '../../../search/settings_search_registry.dart';
import '../../../widgets/settings_group_card/settings_group_card.dart';

class TimeoutSettingsSection extends ConsumerWidget {
  const TimeoutSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timeoutMs = ref
        .watch(serverRequestTimeoutProvider)
        .ifNull(TimeoutConstants.requestTimeoutDefaultMs);
    final autoRefreshEnabled = ref.watch(autoRefreshOnTimeoutProvider).ifNull();
    final retryDelayMs = ref
        .watch(autoRefreshRetryDelayProvider)
        .ifNull(TimeoutConstants.autoRefreshRetryDelayDefaultMs);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsGroupHeading(label: context.l10n.timeouts),
        SettingsGroupCard(
          children: [
            SettingsHighlightTarget(
              id: 'serverRequestTimeout',
              child: SettingsPropTile(
                title: context.l10n.serverRequestTimeout,
                subtitle: context.l10n.nSeconds((timeoutMs / 1000).round()),
                type: SettingsPropType.numberSlider(
                  min: TimeoutConstants.requestTimeoutMinSeconds,
                  max: TimeoutConstants.requestTimeoutMaxSeconds,
                  value: (timeoutMs / 1000).round(),
                  onChanged: (seconds) async {
                    ref
                        .read(serverRequestTimeoutProvider.notifier)
                        .update(seconds * 1000);
                  },
                ),
              ),
            ),
            SettingsHighlightTarget(
              id: 'autoRefreshOnTimeout',
              child: CompactSwitchListTile(
                controlAffinity: ListTileControlAffinity.trailing,
                title: Text(context.l10n.autoRefreshOnTimeout),
                subtitle: Text(context.l10n.autoRefreshOnTimeoutDescription),
                value: autoRefreshEnabled,
                onChanged: ref
                    .read(autoRefreshOnTimeoutProvider.notifier)
                    .update,
              ),
            ),
            if (autoRefreshEnabled)
              SettingsHighlightTarget(
                id: 'autoRefreshRetryDelay',
                child: SettingsPropTile(
                  title: context.l10n.autoRefreshRetryDelay,
                  subtitle: context.l10n.nSeconds(
                    (retryDelayMs / 1000).round(),
                  ),
                  type: SettingsPropType.numberSlider(
                    min: TimeoutConstants.autoRefreshRetryDelayMinSeconds,
                    max: TimeoutConstants.autoRefreshRetryDelayMaxSeconds,
                    value: (retryDelayMs / 1000).round(),
                    onChanged: (seconds) async {
                      ref
                          .read(autoRefreshRetryDelayProvider.notifier)
                          .update(seconds * 1000);
                    },
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
