// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:material_ui/material_ui.dart';

import '../../constants/app_sizes.dart';
import '../../utils/extensions/custom_extensions.dart';
import '../ios/apple_glass_capability.dart';
import 'app_dialog.dart';
import 'pop_button.dart';

class RadioListPopup<T> extends StatelessWidget {
  const RadioListPopup({
    super.key,
    required this.title,
    required this.optionList,
    required this.value,
    required this.onChange,
    this.getOptionTitle,
    this.getOptionSubtitle,
    this.isOptionEnabled,
    this.separatorBefore,
  });

  final String title;
  final List<T> optionList;
  final T value;
  final ValueChanged<T> onChange;
  final String Function(T)? getOptionTitle;
  final String Function(T)? getOptionSubtitle;
  final bool Function(T)? isOptionEnabled;
  final T? separatorBefore;

  @override
  Widget build(BuildContext context) {
    final glass = appleGlassEnabled(context);
    final options = RadioList(
      optionList: optionList,
      value: value,
      onChange: onChange,
      getTitle: getOptionTitle,
      getSubtitle: getOptionSubtitle,
      isOptionEnabled: isOptionEnabled,
      useCheckmarks: glass,
      separatorBefore: separatorBefore,
    );
    if (glass) {
      return AppDialogPanel(
        title: title,
        content: options,
        scrollContent: false,
        actions: const [PopButton()],
      );
    }
    return AlertDialog(
      contentPadding: KEdgeInsets.v8.size,
      title: Text(title),
      content: options,
      actions: const [PopButton()],
    );
  }
}

class RadioList<T> extends StatelessWidget {
  const RadioList({
    super.key,
    required this.optionList,
    required this.value,
    required this.onChange,
    this.getTitle,
    this.getSubtitle,
    this.isOptionEnabled,
    this.useCheckmarks = false,
    this.separatorBefore,
  });

  final List<T> optionList;
  final T value;
  final ValueChanged<T> onChange;
  final String Function(T)? getTitle;
  final String Function(T)? getSubtitle;
  final bool Function(T)? isOptionEnabled;
  final bool useCheckmarks;
  final T? separatorBefore;

  Widget getRadioListTile(BuildContext context, T option) {
    final label = getTitle?.call(option) ?? option.toString();
    final subtitle = getSubtitle?.call(option);
    final enabled = isOptionEnabled?.call(option) ?? true;
    if (useCheckmarks) {
      final selected = option == value;
      final scheme = context.theme.colorScheme;
      return RadioListTile<T>.adaptive(
        value: option,
        enabled: enabled,
        activeColor: scheme.primary,
        title: Text(
          label,
          style: selected ? const TextStyle(fontWeight: FontWeight.w600) : null,
        ),
        subtitle: subtitle == null ? null : Text(subtitle),
        controlAffinity: ListTileControlAffinity.trailing,
        useCupertinoCheckmarkStyle: true,
        minTileHeight: 48,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        visualDensity: VisualDensity.standard,
        selected: selected,
        selectedTileColor: scheme.onSurface.withValues(alpha: 0.07),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      );
    }
    return RadioListTile<T>(
      activeColor: context.theme.colorScheme.primary,
      title: Text(label),
      subtitle: subtitle == null ? null : Text(subtitle),
      value: option,
      enabled: enabled,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: context.height * .7),
      child: SingleChildScrollView(
        child: RadioGroup<T>(
          groupValue: value,
          onChanged: (value) {
            if (value != null) {
              onChange(value);
            }
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final option in optionList) ...[
                if (separatorBefore != null && option == separatorBefore)
                  const Divider(height: 12, indent: 12, endIndent: 12),
                getRadioListTile(context, option),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
