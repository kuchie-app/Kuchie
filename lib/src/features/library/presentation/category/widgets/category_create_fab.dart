// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/misc/toast/toast.dart';
import '../../../../../utils/motion/reduce_motion.dart';
import '../../../../../widgets/custom_circular_progress_indicator.dart';
import '../../../../../widgets/ios/apple_glass_capability.dart';
import '../../../../../widgets/ios/apple_glass_toolbar.dart';
import '../controller/edit_category_controller.dart';
import 'edit_category_dialog.dart';

class CategoryCreateFab extends HookConsumerWidget {
  const CategoryCreateFab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLoading = useState(false);
    final label = context.l10n.addCategory;
    void open() => showDialog<void>(
      context: context,
      builder: (_) => EditCategoryDialog(
        createCategory: (newCategory) async {
          final controller = ref.read(categoryControllerProvider.notifier);
          final toast = ref.read(toastProvider);
          final errorLabel = context.l10n.errorSomethingWentWrong;
          isLoading.value = true;
          try {
            final result = await controller.createCategory(newCategory);
            if (result.hasError && context.mounted) {
              toast?.showError(errorLabel);
            }
          } finally {
            if (context.mounted) isLoading.value = false;
          }
        },
      ),
      animationStyle: context.motionStyle,
    );

    if (supportsAppleGlass(context) && !isLoading.value) {
      return AppleGlassToolbarButton(
        id: 'add-category',
        symbol: 'plus',
        label: label,
        fallbackIcon: FluentIcons.add_24_regular,
        onPressed: open,
      );
    }

    return FloatingActionButton.extended(
      onPressed: isLoading.value ? null : open,
      tooltip: label,
      isExtended:
          context.windowSizeClass >= WindowSizeClass.medium && !isLoading.value,
      label: Text(label),
      icon: isLoading.value
          ? MiniCircularProgressIndicator(color: context.iconColor)
          : const Icon(FluentIcons.add_24_regular),
    );
  }
}
