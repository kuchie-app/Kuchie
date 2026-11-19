import 'package:flutter/services.dart'
    show MissingPluginException, PlatformException;
import 'package:material_ui/material_ui.dart';

import '../../../utils/extensions/custom_extensions.dart';
import '../../../widgets/app_bottom_sheet.dart';
import '../../settings/widgets/settings_group_card/settings_group_card.dart';
import '../data/apple_app_icon.dart';

class AppIconSettingsTile extends StatelessWidget {
  const AppIconSettingsTile({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: 'kuchie.app-icon.settings',
      child: SettingsGroupRow(
        icon: Icons.apps_rounded,
        title: context.l10n.appIconTitle,
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => showAppBottomSheet<void>(
          context: context,
          constraints: const BoxConstraints(maxWidth: 520),
          builder: (_) => const _AppIconSheet(),
        ),
      ),
    );
  }
}

class _AppIconSheet extends StatefulWidget {
  const _AppIconSheet();

  @override
  State<_AppIconSheet> createState() => _AppIconSheetState();
}

class _AppIconSheetState extends State<_AppIconSheet> {
  final _icons = const AppleAppIcon();
  AppleAppIconState? _state;
  String? _message;
  var _busy = true;
  var _loadFailed = false;
  var _isError = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _beginAction() {
    setState(() {
      _busy = true;
      _message = null;
      _isError = false;
    });
  }

  Future<void> _load() async {
    try {
      final state = await _icons.load();
      if (!mounted) return;
      setState(() {
        _state = state;
        _loadFailed = false;
        _busy = false;
      });
    } on MissingPluginException {
      if (!mounted) return;
      setState(() {
        _state = const AppleAppIconState();
        _busy = false;
      });
    } on PlatformException {
      if (!mounted) return;
      setState(() {
        _loadFailed = true;
        _busy = false;
      });
    }
  }

  Future<void> _apply(AppIconDesign icon) async {
    _beginAction();
    try {
      final state = await _icons.apply(icon);
      if (!mounted) return;
      setState(() => _state = state);
    } on PlatformException {
      if (!mounted) return;
      _report(context.l10n.appIconChangeFailed, isError: true);
    } finally {
      _finishAction();
    }
  }

  Future<void> _openShortcuts() async {
    _beginAction();
    try {
      final didOpen = await _icons.openShortcuts();
      if (!mounted || didOpen) return;
      _report(context.l10n.appIconShortcutUnavailable, isError: true);
    } on PlatformException {
      if (!mounted) return;
      _report(context.l10n.appIconShortcutUnavailable, isError: true);
    } finally {
      _finishAction();
    }
  }

  void _report(String message, {bool isError = false}) {
    setState(() {
      _message = message;
      _isError = isError;
    });
  }

  void _finishAction() {
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final state = _state;
    final message = _message;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppSheetHeader(title: l10n.appIconTitle),
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_loadFailed)
                  ListTile(
                    title: Text(l10n.appIconUnavailable),
                    trailing: TextButton(
                      onPressed: _busy
                          ? null
                          : () {
                              _beginAction();
                              _load();
                            },
                      child: Text(l10n.retry),
                    ),
                  )
                else if (state != null)
                  if (state.available)
                    for (final icon in AppIconDesign.values)
                      _IconOption(
                        design: icon,
                        selected: state.current == icon,
                        onTap: _busy || state.current == icon
                            ? null
                            : () => _apply(icon),
                      )
                  else
                    ListTile(title: Text(l10n.appIconUnavailable)),
                if (message != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        message,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: _isError ? theme.colorScheme.error : null,
                        ),
                      ),
                    ),
                  ),
                const Divider(height: 28),
                _CustomIconSteps(busy: _busy, openShortcuts: _openShortcuts),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _IconOption extends StatelessWidget {
  const _IconOption({required this.design, required this.selected, this.onTap});

  final AppIconDesign design;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      identifier: 'kuchie.app-icon.${design.name}',
      selected: selected,
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        selected: selected,
        selectedColor: colors.onSurface,
        selectedTileColor: colors.surfaceContainerHighest.withValues(
          alpha: 0.6,
        ),
        leading: _IconPreview(
          image: Image.asset(design.previewAsset, excludeFromSemantics: true),
        ),
        title: Text(design.title),
        trailing: selected
            ? Icon(Icons.check_rounded, color: colors.primary)
            : null,
        onTap: onTap,
      ),
    );
  }
}

/// iOS has no API for an app icon from a picture, so a custom image goes
/// through a Home Screen shortcut that opens Kuchie.
class _CustomIconSteps extends StatelessWidget {
  const _CustomIconSteps({required this.busy, required this.openShortcuts});

  final bool busy;
  final VoidCallback openShortcuts;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              l10n.appIconCustomHeading,
              style: theme.textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.appIconCustomSubtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Text(l10n.appIconShortcutSteps),
          const SizedBox(height: 12),
          Semantics(
            identifier: 'kuchie.app-icon.open-shortcuts',
            child: FilledButton.tonalIcon(
              onPressed: busy ? null : openShortcuts,
              icon: const Icon(Icons.open_in_new_rounded),
              label: Text(l10n.appIconOpenShortcuts),
            ),
          ),
        ],
      ),
    );
  }
}

class _IconPreview extends StatelessWidget {
  const _IconPreview({required this.image});

  final Widget image;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(11),
      child: SizedBox.square(dimension: 42, child: image),
    );
  }
}
