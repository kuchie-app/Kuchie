// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../widgets/app_bottom_sheet.dart';
import '../../../domain/filter/filter_model.dart';
import 'filter_to_widget.dart';
import 'saved_source_searches.dart';

class SourceMangaFilter extends HookWidget {
  const SourceMangaFilter({
    super.key,
    required this.filters,
    this.currentQuery,
    this.onSavedSearchSelected,
    required this.sourceId,
    required this.appliedChanges,
    required this.onSubmitted,
    required this.onReset,
    this.inSheet = false,
  });
  final List<Filter> filters;
  final String? Function()? currentQuery;
  final void Function(String?, List<FilterChange>)? onSavedSearchSelected;
  final String sourceId;
  final List<FilterChange> appliedChanges;
  final ValueChanged<List<FilterChange>?> onSubmitted;
  final VoidCallback onReset;
  final bool inSheet;
  @override
  Widget build(BuildContext context) {
    final filterChangeMap = useState<Map<int, List<FilterChange>>>(const {});
    final resetCount = useState(0);

    useEffect(() {
      final changeMap = <int, List<FilterChange>>{};
      for (final change in appliedChanges) {
        changeMap[change.position] = [...?changeMap[change.position], change];
      }
      filterChangeMap.value = changeMap;
      return null;
    }, [appliedChanges]);

    List<FilterChange> currentChanges() => [
      for (final changes in filterChangeMap.value.values) ...changes,
    ];

    final actions = OverflowBar(
      spacing: 8,
      overflowSpacing: 4,
      overflowAlignment: OverflowBarAlignment.end,
      alignment: MainAxisAlignment.spaceBetween,
      children: [
        TextButton(
          onPressed: () {
            onReset();
            filterChangeMap.value = const {};
            resetCount.value++;
          },
          child: Text(context.l10n.reset),
        ),
        FilledButton(
          onPressed: () => onSubmitted(currentChanges()),
          child: Text(
            inSheet ? context.l10n.applyFilters : context.l10n.filter,
          ),
        ),
      ],
    );

    final hasSavedSearches = onSavedSearchSelected != null;
    final filterCount = filters.length + (hasSavedSearches ? 1 : 0);
    Widget filterAt(int index) {
      if (index == 0 && hasSavedSearches) {
        return SavedSourceSearches(
          sourceId: sourceId,
          currentQuery: currentQuery ?? () => null,
          currentChanges: currentChanges,
          onSelected: onSavedSearchSelected!,
        );
      }
      final filterIndex = hasSavedSearches ? index - 1 : index;
      return FilterToWidget(
        key: ValueKey((filterIndex, resetCount.value)),
        filter: filters[filterIndex],
        currentChanges: filterChangeMap.value[filterIndex] ?? const [],
        inSheet: inSheet,
        fieldPath: '$filterIndex',
        onChanged: (changes) {
          filterChangeMap.value = {
            ...filterChangeMap.value,
            filterIndex: [
              for (final filter in changes)
                filter.copyWith(position: filterIndex),
            ],
          };
        },
      );
    }

    Widget list({Widget? header, Widget? footer}) => ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: ListView.builder(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: inSheet ? const EdgeInsets.fromLTRB(8, 4, 8, 12) : null,
        itemBuilder: (_, index) {
          if (header != null && index == 0) return header;
          final filterIndex = header == null ? index : index - 1;
          if (footer != null && filterIndex == filterCount) return footer;
          return filterAt(filterIndex);
        },
        itemCount:
            filterCount + (header == null ? 0 : 1) + (footer == null ? 0 : 1),
      ),
    );

    if (!inSheet) {
      return Scaffold(
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: Padding(padding: const EdgeInsets.all(8), child: actions),
        ),
        body: list(),
      );
    }

    final header = AppSheetHeader(
      title: context.l10n.unifiedSearchFiltersSection,
    );
    final footer = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1, color: context.colorScheme.outlineVariant),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: ButtonTheme(
            materialTapTargetSize: MaterialTapTargetSize.padded,
            child: actions,
          ),
        ),
      ],
    );
    return FractionallySizedBox(
      heightFactor: 0.82,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxHeight <
              MediaQuery.textScalerOf(context).scale(170)) {
            return list(header: header, footer: footer);
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              Expanded(child: list()),
              footer,
            ],
          );
        },
      ),
    );
  }
}
