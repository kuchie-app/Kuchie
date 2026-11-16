// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../constants/db_keys.dart';
import '../../../../../constants/enum.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../widgets/ios/apple_glass_toolbar.dart';
import '../../../../../widgets/popup_widgets/app_dialog.dart';
import '../../../../../widgets/popup_widgets/radio_list_popup.dart';
import '../controller/source_manga_controller.dart';

class SourceMangaDisplayIconPopup extends ConsumerWidget {
  const SourceMangaDisplayIconPopup({super.key});

  static void show(BuildContext context, WidgetRef ref) {
    final displayMode =
        ref.read(sourceDisplayModeProvider) ?? DBKeys.sourceDisplayMode.initial;
    showAppDialog<void>(
      context: context,
      builder: (dialogContext) => RadioListPopup<DisplayMode>(
        optionList: DisplayMode.sourceDisplayList,
        getOptionTitle: (value) => value.toLocale(dialogContext),
        title: dialogContext.l10n.displayMode,
        value: displayMode,
        onChange: (enumValue) async {
          ref.read(sourceDisplayModeProvider.notifier).update(enumValue);
          if (dialogContext.mounted) Navigator.pop(dialogContext);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayMode =
        ref.watch(sourceDisplayModeProvider) ??
        DBKeys.sourceDisplayMode.initial;
    return AppleGlassToolbarButton(
      id: 'source-display',
      symbol: displayMode.isGrid == false ? 'list.bullet' : 'square.grid.2x2',
      label: context.l10n.displayMode,
      fallbackIcon: displayMode.icon,
      onPressed: () => show(context, ref),
    );
  }
}
