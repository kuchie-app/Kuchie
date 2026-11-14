import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../widgets/app_bottom_sheet.dart';
import '../../../../widgets/settings_group_card/settings_group_card.dart';
import 'download_island_preference.dart';

class DownloadIslandSettingsTile extends StatelessWidget {
  const DownloadIslandSettingsTile({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    identifier: 'kuchie.island.settings',
    child: SettingsGroupRow(
      icon: Icons.download_for_offline_outlined,
      title: context.l10n.downloadIslandTitle,
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => showAppBottomSheet<void>(
        context: context,
        constraints: const BoxConstraints(maxWidth: 520),
        builder: (_) => const _DownloadIslandSheet(),
      ),
    ),
  );
}

class _DownloadIslandSheet extends StatefulWidget {
  const _DownloadIslandSheet();

  @override
  State<_DownloadIslandSheet> createState() => _DownloadIslandSheetState();
}

class _DownloadIslandSheetState extends State<_DownloadIslandSheet> {
  DownloadIslandVariant? _selected;
  bool _busy = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    try {
      final selected = await DownloadIslandPreference.read();
      if (mounted) setState(() => _selected = selected);
    } on PlatformException {
      if (mounted) setState(() => _failed = true);
    } on MissingPluginException {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _choose(DownloadIslandVariant variant) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await DownloadIslandPreference.write(variant);
      if (mounted) setState(() => _selected = variant);
    } on PlatformException {
      if (mounted) setState(() => _failed = true);
    } on MissingPluginException {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppSheetHeader(title: l10n.downloadIslandTitle),
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_selected != null)
                  for (final option in DownloadIslandVariant.values)
                    Semantics(
                      identifier: 'kuchie.island.${option.id}',
                      selected: _selected == option,
                      child: ListTile(
                        title: Text(switch (option) {
                          DownloadIslandVariant.kiriRing =>
                            l10n.downloadIslandKiriRing,
                          DownloadIslandVariant.kiriPercentage =>
                            l10n.downloadIslandKiriPercentage,
                          DownloadIslandVariant.scarf =>
                            l10n.downloadIslandScarf,
                          DownloadIslandVariant.mangaPanel =>
                            l10n.downloadIslandMangaPanel,
                        }),
                        trailing: _selected == option
                            ? Icon(
                                Icons.check_rounded,
                                color: Theme.of(context).colorScheme.primary,
                              )
                            : null,
                        onTap: _busy || _selected == option
                            ? null
                            : () => _choose(option),
                      ),
                    ),
                if (_failed)
                  Semantics(
                    liveRegion: true,
                    child: ListTile(
                      title: Text(l10n.downloadIslandUnavailable),
                      trailing: _selected == null
                          ? TextButton(
                              onPressed: _busy
                                  ? null
                                  : () {
                                      setState(() {
                                        _busy = true;
                                        _failed = false;
                                      });
                                      _read();
                                    },
                              child: Text(l10n.retry),
                            )
                          : null,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
