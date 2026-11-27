import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../../widgets/app_bottom_sheet.dart';
import '../../local_collection/presentation/local_ui.dart';
import '../../settings/widgets/settings_group_card/settings_group_card.dart';
import '../domain/diagram/sync_methods.dart';
import '../domain/diagram/sync_scene.dart';
import 'diagram/sync_diagram.dart';
import 'sync_hero_card.dart';

/// Every method, with "Coming soon" ones that open a preview (design 3.2).
class SyncMethodList extends StatelessWidget {
  const SyncMethodList({
    super.key,
    required this.selected,
    this.serverAddress,
    this.onSelect,
  });

  final SyncMethodKind selected;
  final String? serverAddress;

  /// Called for methods this version supports; null makes them read-only.
  final ValueChanged<SyncMethodKind>? onSelect;

  @override
  Widget build(BuildContext context) => SettingsGroupCard(
    children: [
      for (final method in syncMethods.values)
        _MethodRow(
          method: method,
          selected: method.kind == selected,
          subtitle:
              method.kind == SyncMethodKind.suwayomi && serverAddress != null
              ? serverAddress!
              : syncCopy(context, method.description),
          onTap: method.available
              ? onSelect == null
                    ? null
                    : () => onSelect!(method.kind)
              : () => showSyncMethodPreview(context, method),
        ),
    ],
  );
}

class _MethodRow extends StatelessWidget {
  const _MethodRow({
    required this.method,
    required this.selected,
    required this.subtitle,
    required this.onTap,
  });

  final SyncMethodSpec method;
  final bool selected;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = method.kind == SyncMethodKind.local
        ? localText(context, 'Off', 'Mati')
        : syncCopy(context, method.name);
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      child: ListTile(
        leading: Icon(
          selected
              ? Icons.radio_button_checked_rounded
              : Icons.radio_button_unchecked_rounded,
          color: selected ? scheme.primary : scheme.onSurfaceVariant,
        ),
        title: Text(name),
        subtitle: Text(subtitle),
        trailing: method.available
            ? method.kind == SyncMethodKind.suwayomi
                  ? const Icon(FluentIcons.chevron_right_24_regular)
                  : null
            : _SoonBadge(),
        onTap: onTap,
        enabled: onTap != null || selected,
      ),
    );
  }
}

class _SoonBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Text(
        localText(context, 'Coming soon', 'Segera hadir'),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// A short sheet with [method]'s diagram while it syncs, what it syncs, and
/// "Coming soon", so the difference is clear before it can be chosen.
Future<void> showSyncMethodPreview(
  BuildContext context,
  SyncMethodSpec method,
) => showAppBottomSheet<void>(
  context: context,
  builder: (sheet) {
    final theme = Theme.of(sheet);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSheetHeader(title: syncCopy(sheet, method.name)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SyncDiagram(scene: sceneFor(method, SyncStatusKind.syncing)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Text(
            syncCopy(sheet, method.copy[SyncStatusKind.syncing]!.explain),
            style: theme.textTheme.bodyMedium,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final item in method.legend)
                Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: Text(item.synced ? '✓' : '–'),
                  label: Text(
                    [
                      syncCopy(sheet, item.label),
                      if (item.note != null) syncCopy(sheet, item.note!),
                    ].join(' · '),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            16 + MediaQuery.paddingOf(sheet).bottom,
          ),
          child: Text(
            localText(
              sheet,
              'Coming soon. Kuchie syncs with a Suwayomi server for now.',
              'Segera hadir. Untuk sekarang Kuchie menyinkronkan lewat server Suwayomi.',
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  },
);
