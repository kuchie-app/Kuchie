import 'package:material_ui/material_ui.dart';

import '../../../widgets/popup_widgets/app_dialog.dart';
import '../../../widgets/shell/detail_navigation_shell_screen.dart';
import '../../settings/widgets/settings_group_card/settings_group_card.dart';
import '../data/local_mihon_runtime.dart';
import '../data/local_sources.dart';
import 'local_ui.dart';

/// An APK source's own settings, as Mihon shows them for a configurable
/// source: switches, text fields and single or multiple choices.
class LocalSourceSettingsScreen extends StatefulWidget {
  const LocalSourceSettingsScreen({
    super.key,
    required this.sources,
    required this.extension,
  });

  final LocalSources sources;
  final LocalExtension extension;

  @override
  State<LocalSourceSettingsScreen> createState() =>
      _LocalSourceSettingsScreenState();
}

class _LocalSourceSettingsScreenState extends State<LocalSourceSettingsScreen> {
  List<MihonPreference>? _preferences;
  Object? _error;
  String? _saving;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final preferences = await widget.sources.sourcePreferences(
        widget.extension.id,
      );
      if (mounted) setState(() => _preferences = preferences);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _save(MihonPreference changed) async {
    if (_saving != null) return;
    setState(() => _saving = changed.key);
    try {
      final preferences = await widget.sources.setSourcePreference(
        widget.extension.id,
        changed,
      );
      if (mounted) setState(() => _preferences = preferences);
    } catch (error) {
      if (mounted) localFailure(context, error);
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preferences = _preferences;
    return Scaffold(
      appBar: detailNavigationAppBar(
        context,
        title: Text(localText(context, 'Source settings', 'Pengaturan sumber')),
      ),
      body: switch ((preferences, _error)) {
        (_, final Object _) => _Message(
          text: localText(
            context,
            'Could not load the settings of ${widget.extension.name}.',
            'Pengaturan ${widget.extension.name} tidak dapat dimuat.',
          ),
          action: TextButton(
            onPressed: _load,
            child: Text(localText(context, 'Retry', 'Coba lagi')),
          ),
        ),
        (null, _) => const Center(child: CircularProgressIndicator.adaptive()),
        (final List<MihonPreference> items, _) when items.isEmpty => _Message(
          text: localText(
            context,
            '${widget.extension.name} has no settings.',
            '${widget.extension.name} tidak memiliki pengaturan.',
          ),
        ),
        (final List<MihonPreference> items, _) => ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            SettingsGroupCard(
              children: [
                for (final preference in items)
                  _PreferenceTile(
                    preference: preference,
                    busy: _saving == preference.key,
                    enabled: _saving == null,
                    onChanged: _save,
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
              child: Text(
                localText(
                  context,
                  'Some sources apply a change only after Kuchie restarts, as '
                      'in Mihon.',
                  'Beberapa sumber baru menerapkan perubahan setelah Kuchie '
                      'dibuka ulang, seperti di Mihon.',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      },
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 12), action!],
        ],
      ),
    ),
  );
}

class _PreferenceTile extends StatelessWidget {
  const _PreferenceTile({
    required this.preference,
    required this.busy,
    required this.enabled,
    required this.onChanged,
  });

  final MihonPreference preference;
  final bool busy;
  final bool enabled;
  final ValueChanged<MihonPreference> onChanged;

  @override
  Widget build(BuildContext context) {
    final summary = _summary(context);
    final subtitle = summary.isEmpty ? null : Text(summary);
    final trailing = busy
        ? const SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator.adaptive(strokeWidth: 2),
          )
        : null;
    switch (preference.kind) {
      case MihonPreferenceKind.checkBox || MihonPreferenceKind.toggle:
        return SwitchListTile.adaptive(
          title: Text(preference.title),
          subtitle: subtitle,
          value: preference.checked,
          onChanged: enabled
              ? (value) => onChanged(preference.withChecked(value))
              : null,
        );
      case MihonPreferenceKind.text:
        return ListTile(
          title: Text(preference.title),
          subtitle: subtitle,
          trailing: trailing,
          enabled: enabled,
          onTap: () => _editText(context),
        );
      case MihonPreferenceKind.list:
        return ListTile(
          title: Text(preference.title),
          subtitle: subtitle,
          trailing: trailing,
          enabled: enabled && preference.entryValues.isNotEmpty,
          onTap: () => _chooseOne(context),
        );
      case MihonPreferenceKind.multiSelect:
        return ListTile(
          title: Text(preference.title),
          subtitle: subtitle,
          trailing: trailing,
          enabled: enabled && preference.entryValues.isNotEmpty,
          onTap: () => _chooseMany(context),
        );
    }
  }

  /// Mihon shows the chosen value where the summary is a `%s` placeholder or
  /// empty, so readers see what is set.
  String _summary(BuildContext context) {
    final current = switch (preference.kind) {
      MihonPreferenceKind.list when preference.selectedIndex >= 0 => _entry(
        preference.selectedIndex,
      ),
      MihonPreferenceKind.multiSelect => [
        for (final (index, value) in preference.entryValues.indexed)
          if (preference.selectedValues.contains(value)) _entry(index),
      ].join(', '),
      MihonPreferenceKind.text => preference.text,
      _ => '',
    };
    final summary = preference.summary;
    if (summary.contains('%s')) return summary.replaceAll('%s', current);
    if (summary.isNotEmpty) return summary;
    return current;
  }

  String _entry(int index) => index < preference.entries.length
      ? preference.entries[index]
      : preference.entryValues[index];

  Future<void> _editText(BuildContext context) async {
    final value = await localInput(
      context,
      preference.dialogTitle ?? preference.title,
      preference.dialogMessage ?? preference.title,
      initial: preference.text,
    );
    if (value != null && value != preference.text) {
      onChanged(preference.withText(value));
    }
  }

  Future<void> _chooseOne(BuildContext context) async {
    final selected = await showAppDialog<int>(
      context: context,
      builder: (dialogContext) => AppDialogPanel(
        title: preference.dialogTitle ?? preference.title,
        content: RadioGroup<int>(
          groupValue: preference.selectedIndex,
          onChanged: (index) => Navigator.pop(dialogContext, index),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final index in preference.entryValues.indexed.map(
                (entry) => entry.$1,
              ))
                RadioListTile<int>.adaptive(
                  value: index,
                  title: Text(_entry(index)),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected != null && selected != preference.selectedIndex) {
      onChanged(preference.withSelectedIndex(selected));
    }
  }

  Future<void> _chooseMany(BuildContext context) async {
    final selected = await showAppDialog<Set<String>>(
      context: context,
      builder: (dialogContext) =>
          _MultiSelectDialog(preference: preference, entry: _entry),
    );
    if (selected != null &&
        (selected.length != preference.selectedValues.length ||
            !selected.containsAll(preference.selectedValues))) {
      onChanged(preference.withSelectedValues(selected));
    }
  }
}

class _MultiSelectDialog extends StatefulWidget {
  const _MultiSelectDialog({required this.preference, required this.entry});

  final MihonPreference preference;
  final String Function(int index) entry;

  @override
  State<_MultiSelectDialog> createState() => _MultiSelectDialogState();
}

class _MultiSelectDialogState extends State<_MultiSelectDialog> {
  late final Set<String> _selected = {...widget.preference.selectedValues};

  @override
  Widget build(BuildContext context) => AppDialogPanel(
    title: widget.preference.dialogTitle ?? widget.preference.title,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (index, value) in widget.preference.entryValues.indexed)
          CheckboxListTile.adaptive(
            value: _selected.contains(value),
            title: Text(widget.entry(index)),
            onChanged: (checked) => setState(
              () => checked == true
                  ? _selected.add(value)
                  : _selected.remove(value),
            ),
          ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _selected),
        child: Text(MaterialLocalizations.of(context).okButtonLabel),
      ),
    ],
  );
}
