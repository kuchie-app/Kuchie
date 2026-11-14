// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:material_ui/material_ui.dart';

import '../../utils/extensions/custom_extensions.dart';
import 'apple_glass_capability.dart';
import 'apple_glass_toolbar.dart';

class AppleGlassDropdown<T> extends StatelessWidget {
  const AppleGlassDropdown({
    super.key,
    required this.id,
    required this.label,
    required this.options,
    required this.value,
    required this.onSelected,
    required this.fallback,
    this.showLabel = false,
  });

  final String id;
  final String label;
  final List<({T value, String title})> options;
  final T? value;
  final ValueChanged<T>? onSelected;
  final Widget fallback;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    if (!supportsAppleGlass(context)) return fallback;
    final selection = options
        .where((option) => option.value == value)
        .firstOrNull;
    final select = onSelected;
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        if (!available.isFinite || available < 48) return fallback;
        final button = AppleGlassToolbarButton(
          id: id,
          symbol: 'chevron.down',
          label: label,
          title: selection?.title ?? context.l10n.select,
          alignTitleLeading: true,
          accessibilityValue: selection?.title,
          width: available,
          allowParentScroll: true,
          onPressed: null,
          fallback: fallback,
          menu: [
            for (final (index, option) in options.indexed)
              AppleGlassToolbarMenuItem(
                id: '$index',
                title: option.title,
                symbol: '',
                fallbackIcon: Icons.radio_button_unchecked,
                selected: option.value == value,
                onSelected: select == null ? null : () => select(option.value),
              ),
          ],
        );
        if (!showLabel) return button;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsetsDirectional.only(start: 12, bottom: 2),
                child: Text(label, style: context.textTheme.labelLarge),
              ),
            ),
            button,
          ],
        );
      },
    );
  }
}
