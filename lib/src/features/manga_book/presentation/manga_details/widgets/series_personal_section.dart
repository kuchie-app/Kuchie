import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../widgets/desktop/desktop_page_frame.dart';
import 'manga_rating_bar.dart';

/// Your own layer on a series, for every collection: rating, then the notes,
/// categories and your tags as chips, and the notes text when there is one.
/// Sits under the series tags on the details screen.
class SeriesPersonalSection extends StatelessWidget {
  const SeriesPersonalSection({
    super.key,
    required this.rating,
    required this.onRate,
    required this.notes,
    required this.onEditNotes,
    required this.tags,
    required this.onAddTag,
    required this.onRemoveTag,
    this.onTagTap,
    this.categories,
    this.onEditCategories,
  });

  final int rating;
  final Future<void> Function(int rating) onRate;
  final String notes;
  final VoidCallback onEditNotes;
  final List<String> tags;
  final VoidCallback onAddTag;
  final ValueChanged<String> onRemoveTag;

  /// E.g. a menu to search the tag; gets the chip's own context.
  final void Function(BuildContext chipContext, String tag)? onTagTap;

  /// Shown as a chip while the series is in the library.
  final List<String>? categories;
  final VoidCallback? onEditCategories;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colorScheme;
    final categories = this.categories;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RatingStars(rating: rating, onChanged: onRate),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            16,
            4,
            16,
            4,
          ).onDesktopPageLine(context),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ActionChip(
                avatar: const Icon(FluentIcons.note_24_regular, size: 18),
                label: Text(
                  notes.isEmpty ? context.l10n.notes : context.l10n.editNotes,
                ),
                onPressed: onEditNotes,
              ),
              if (categories != null && onEditCategories != null)
                ActionChip(
                  avatar: const Icon(FluentIcons.folder_24_regular, size: 18),
                  label: Text(
                    categories.isEmpty
                        ? context.l10n.categories
                        : categories.join(', '),
                    overflow: TextOverflow.ellipsis,
                  ),
                  onPressed: onEditCategories,
                ),
              for (final tag in tags)
                Builder(
                  builder: (chipContext) => InputChip(
                    avatar: Icon(
                      FluentIcons.tag_24_regular,
                      size: 16,
                      color: colors.onSecondaryContainer,
                    ),
                    label: Text(tag),
                    backgroundColor: colors.secondaryContainer,
                    onPressed: onTagTap == null
                        ? null
                        : () => onTagTap!(chipContext, tag),
                    deleteIcon: const Icon(
                      FluentIcons.dismiss_24_regular,
                      size: 16,
                    ),
                    onDeleted: () => onRemoveTag(tag),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ActionChip(
                avatar: const Icon(FluentIcons.add_24_regular, size: 18),
                label: Text(context.l10n.addTag),
                onPressed: onAddTag,
              ),
            ],
          ),
        ),
        if (notes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              16,
              4,
              16,
              8,
            ).onDesktopPageLine(context),
            child: InkWell(
              onTap: onEditNotes,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  notes,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.bodyMedium,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
