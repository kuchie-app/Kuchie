// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:material_ui/material_ui.dart';

import '../../../utils/extensions/custom_extensions.dart';
import '../../../widgets/app_bottom_sheet.dart';
import '../../../widgets/popup_widgets/app_dialog.dart';
import '../../manga_book/presentation/manga_details/widgets/series_personal_section.dart';
import '../data/local_catalog.dart';
import 'local_ui.dart';

/// Rating, notes, personal tags and categories for a Local series.
///
/// Works for series read straight from a source as well as saved ones;
/// categories need the series in the library.
class LocalSeriesPersonal extends StatefulWidget {
  const LocalSeriesPersonal({
    super.key,
    required this.catalog,
    required this.seriesId,
    this.categories,
    this.onCategoriesChanged,
  });

  final LocalCatalog catalog;
  final String seriesId;

  /// Null when the series is not in the library.
  final List<String>? categories;
  final VoidCallback? onCategoriesChanged;

  @override
  State<LocalSeriesPersonal> createState() => _LocalSeriesPersonalState();
}

class _LocalSeriesPersonalState extends State<LocalSeriesPersonal> {
  LocalSeriesMeta _meta = const LocalSeriesMeta();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(LocalSeriesPersonal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.seriesId != widget.seriesId) _load();
  }

  Future<void> _load() async {
    final meta = await widget.catalog.seriesMeta(widget.seriesId);
    if (mounted) setState(() => _meta = meta);
  }

  Future<void> _save(Future<void> Function() write) async {
    try {
      await write();
      await _load();
    } catch (error) {
      if (mounted) localFailure(context, error);
    }
  }

  Future<void> _editNotes() async {
    final notes = await showLocalNotesDialog(context, _meta.notes);
    if (notes != null) {
      await _save(() => widget.catalog.setNotes(widget.seriesId, notes));
    }
  }

  Future<void> _addTag() async {
    final tag = await localInput(
      context,
      context.l10n.addTag,
      context.l10n.tags,
    );
    if (tag != null) {
      await _save(
        () => widget.catalog.setTags(widget.seriesId, [..._meta.tags, tag]),
      );
    }
  }

  Future<void> _editCategories() async {
    final current = widget.categories;
    if (current == null) return;
    final changed = await showLocalCategoryPicker(
      context,
      widget.catalog,
      seriesId: widget.seriesId,
      current: current,
    );
    if (changed) widget.onCategoriesChanged?.call();
  }

  @override
  Widget build(BuildContext context) => SeriesPersonalSection(
    rating: _meta.rating,
    onRate: (rating) =>
        _save(() => widget.catalog.setRating(widget.seriesId, rating)),
    notes: _meta.notes,
    onEditNotes: _editNotes,
    categories: widget.categories,
    onEditCategories: widget.categories == null ? null : _editCategories,
    tags: _meta.tags,
    onAddTag: _addTag,
    onRemoveTag: (tag) => _save(
      () => widget.catalog.setTags(widget.seriesId, [
        for (final other in _meta.tags)
          if (other != tag) other,
      ]),
    ),
  );
}

/// Returns the edited text, or null when cancelled. An empty result clears.
Future<String?> showLocalNotesDialog(BuildContext context, String initial) {
  var value = initial;
  return showAppDialog<String>(
    context: context,
    builder: (context) => AppDialogPanel(
      title: context.l10n.notes,
      content: TextFormField(
        initialValue: initial,
        autofocus: true,
        minLines: 4,
        maxLines: 10,
        maxLength: 20000,
        keyboardType: TextInputType.multiline,
        textCapitalization: TextCapitalization.sentences,
        onChanged: (text) => value = text,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, value.trim()),
          child: Text(context.l10n.save),
        ),
      ],
    ),
  );
}

/// Returns true when the series' categories were saved.
Future<bool> showLocalCategoryPicker(
  BuildContext context,
  LocalCatalog catalog, {
  required String seriesId,
  required List<String> current,
}) async {
  try {
    final categories = await catalog.categories();
    if (!context.mounted) return false;
    final selected = current.toSet();
    final result = await showAppBottomSheet<List<String>>(
      context: context,
      builder: (sheet) => StatefulBuilder(
        builder: (context, update) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppSheetHeader(title: localText(sheet, 'Categories', 'Kategori')),
            if (categories.isEmpty)
              ListTile(
                title: Text(
                  localText(
                    sheet,
                    'Create a category in Library first',
                    'Buat kategori di Perpustakaan dulu',
                  ),
                ),
              ),
            for (final category in categories)
              CheckboxListTile(
                title: Text(category),
                value: selected.contains(category),
                onChanged: (value) => update(() {
                  if (value == true) {
                    selected.add(category);
                  } else {
                    selected.remove(category);
                  }
                }),
              ),
            if (categories.isNotEmpty)
              FilledButton(
                onPressed: () => Navigator.pop(sheet, selected.toList()),
                child: Text(MaterialLocalizations.of(sheet).okButtonLabel),
              ),
          ],
        ),
      ),
    );
    if (result == null) return false;
    await catalog.setCategories(seriesId, result);
    return true;
  } catch (error) {
    if (context.mounted) localFailure(context, error);
    return false;
  }
}
