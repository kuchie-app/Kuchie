// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../constants/enum.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../controller/manga_details_controller.dart';

class ChapterListModeToggle extends ConsumerWidget {
  const ChapterListModeToggle({super.key, required this.mangaId});
  final int mangaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(mangaChapterListModeProvider(mangaId: mangaId));
    return ChapterListLayoutToggle(
      mode: mode,
      onChanged: (value) => ref
          .read(mangaChapterListModeProvider(mangaId: mangaId).notifier)
          .update(value),
    );
  }
}

class ChapterListLayoutToggle extends StatelessWidget {
  const ChapterListLayoutToggle({
    super.key,
    required this.mode,
    required this.onChanged,
  });

  final ChapterListMode mode;
  final ValueChanged<ChapterListMode> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    spacing: 6,
    children: [
      for (final value in ChapterListMode.values)
        ChapterHeaderButton(
          icon: value.icon,
          tooltip: value.toLocale(context),
          selected: mode == value,
          onPressed: () => onChanged(value),
        ),
    ],
  );
}

/// One square button of the chapter list header (list, grid, filter, sort),
/// so the three read as one set.
class ChapterHeaderButton extends StatelessWidget {
  const ChapterHeaderButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final cs = context.theme.colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: selected
            ? cs.primary.withValues(alpha: 0.18)
            : cs.onSurface.withValues(alpha: 0.04),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: selected
                ? cs.primary.withValues(alpha: 0.5)
                : cs.outlineVariant,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox.square(
            dimension: 34,
            child: Icon(
              icon,
              size: 18,
              color: selected ? cs.primary : cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
