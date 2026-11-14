// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../constants/app_constants.dart';
import '../../../../../constants/app_sizes.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../widgets/fluent_expansion_tile.dart';
import '../../../../../widgets/ios/apple_glass_dropdown.dart';
import '../../../../../widgets/search_field.dart';
import '../../../../../widgets/sort_list_tile.dart';
import '../../../domain/filter/filter_model.dart';

class FilterToWidget extends StatelessWidget {
  const FilterToWidget({
    super.key,
    required this.filter,
    required this.currentChanges,
    required this.onChanged,
    this.singleLineLabels = false,
    this.inSheet = false,
    this.fieldPath,
  });
  final PrimitiveFilter filter;
  final List<FilterChange> currentChanges;
  final ValueChanged<List<FilterChange>> onChanged;
  final bool singleLineLabels;
  final bool inSheet;
  final String? fieldPath;

  @override
  Widget build(BuildContext context) {
    final firstCurrentChange = currentChanges.firstOrNull;
    return switch (filter) {
      FilterHeader(name: String? name) =>
        name.isNotBlank
            ? inSheet
                  ? _FilterLabel(name)
                  : ListTile(title: Text(name), dense: true)
            : const SizedBox.shrink(),
      FilterSeparator() =>
        inSheet
            ? const Divider(indent: 12, endIndent: 12, height: 20)
            : const Divider(),
      FilterText(name: String? name, textState: String? state) => Padding(
        padding: inSheet
            ? const EdgeInsets.symmetric(horizontal: 12, vertical: 6)
            : KEdgeInsets.h16v4.size,
        child: inSheet
            ? TextFormField(
                initialValue: firstCurrentChange?.textState ?? state,
                decoration: InputDecoration(labelText: name),
                onChanged: (value) => onChanged([
                  FilterChange(
                    textState: value,
                    position: kPositionPlaceholder,
                  ),
                ]),
              )
            : SearchField(
                autofocus: false,
                onChanged: (val) => onChanged([
                  FilterChange(textState: val, position: kPositionPlaceholder),
                ]),
                labelText: name,
                initialText: firstCurrentChange?.textState ?? state,
              ),
      ),
      FilterCheckBox(name: String? name, checkBoxState: bool? state) =>
        CheckboxListTile(
          value: firstCurrentChange?.checkBoxState ?? state.ifNull(),
          title: singleLineLabels && name.isNotBlank
              ? Tooltip(
                  message: name,
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                )
              : Text(name),
          onChanged: (value) => onChanged([
            FilterChange(checkBoxState: value, position: kPositionPlaceholder),
          ]),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: singleLineLabels ? EdgeInsets.zero : null,
          horizontalTitleGap: singleLineLabels ? 8 : null,
          dense: singleLineLabels ? true : null,
          visualDensity: singleLineLabels ? VisualDensity.compact : null,
        ),
      FilterTriState(name: String? name, tristate: TriState state) =>
        _TriStateTile(
          name: name,
          state: firstCurrentChange?.triState ?? state,
          singleLine: singleLineLabels,
          onChanged: (value) => onChanged([
            FilterChange(triState: value, position: kPositionPlaceholder),
          ]),
        ),
      FilterSort(
        name: String name,
        sortState: SortSelectionDto state,
        displayValues: List<String> values,
      ) =>
        FluentExpansionTile(
          title: Text(name, style: context.textTheme.labelLarge),
          children: [
            for (int i = 0; i < (values.length).getValueOnNullOrNegative(); i++)
              SortListTile(
                key: ValueKey("$name-$i"),
                ascending:
                    (firstCurrentChange?.sortState?.ascending ??
                            state.ascending)
                        .ifNull(true),
                title: Text(values[i]),
                selected:
                    i == (firstCurrentChange?.sortState?.index ?? state.index),
                onChanged: (value) {
                  final sortChange = SortStateChange(
                    ascending: value.ifNull(true),
                    index: i,
                  );
                  onChanged([
                    FilterChange(
                      sortState: sortChange,
                      position: kPositionPlaceholder,
                    ),
                  ]);
                },
                onSelected: () {
                  final sortChange = SortStateChange(ascending: true, index: i);
                  onChanged([
                    FilterChange(
                      sortState: sortChange,
                      position: kPositionPlaceholder,
                    ),
                  ]);
                },
              ),
          ],
        ),
      FilterSelect(
        name: String name,
        selectState: int state,
        displayValues: List<String> displayValues,
      ) =>
        _buildSelect(
          context,
          name,
          firstCurrentChange?.selectState ?? state,
          displayValues,
        ),
      FilterGroup(name: String name, groupState: List<PrimitiveFilter> state) =>
        FilterGroupWidget(
          name: name,
          filters: state,
          currentChanges: currentChanges,
          onChanged: onChanged,
          singleLineLabels: singleLineLabels,
          inSheet: inSheet,
          fieldPath: fieldPath,
        ),
      PrimitiveFilter() => throw UnimplementedError(),
    };
  }

  Widget _buildSelect(
    BuildContext context,
    String name,
    int value,
    List<String> choices,
  ) {
    void select(int? index) => onChanged([
      FilterChange(selectState: index, position: kPositionPlaceholder),
    ]);
    final items = [
      for (var i = 0; i < choices.length; i++)
        DropdownMenuItem(
          value: i,
          child: Text(
            choices[i],
            maxLines: inSheet ? 3 : 2,
            overflow: TextOverflow.ellipsis,
            style: inSheet ? null : context.textTheme.bodySmall,
          ),
        ),
    ];
    final selected = value >= 0 && value < choices.length ? value : null;
    const icon = Icon(FluentIcons.chevron_down_24_regular);
    if (inSheet) {
      final fallback = InputDecorator(
        decoration: InputDecoration(labelText: name),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            icon: icon,
            isExpanded: true,
            isDense: true,
            itemHeight: null,
            value: selected,
            items: items,
            onChanged: select,
          ),
        ),
      );
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: AppleGlassDropdown<int>(
          id: 'source-filter-${fieldPath ?? name}',
          label: name,
          showLabel: true,
          options: [
            for (final (index, title) in choices.indexed)
              (value: index, title: title),
          ],
          value: selected,
          onSelected: select,
          fallback: fallback,
        ),
      );
    }
    return Row(
      children: [
        Expanded(
          child: ListTile(
            title: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
        ),
        Expanded(
          child: Padding(
            padding: KEdgeInsets.h16.size,
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                icon: icon,
                isExpanded: true,
                value: selected,
                hint: Text(name),
                items: items,
                onChanged: select,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FilterLabel extends StatelessWidget {
  const _FilterLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 4),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: context.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class FilterGroupWidget extends HookWidget {
  const FilterGroupWidget({
    super.key,
    required this.name,
    required this.filters,
    required this.currentChanges,
    required this.onChanged,
    this.expanded = false,
    this.singleLineLabels = false,
    this.inSheet = false,
    this.fieldPath,
  });

  final String name;
  final List<PrimitiveFilter> filters;
  final List<FilterChange> currentChanges;
  final ValueChanged<List<FilterChange>> onChanged;
  final bool expanded;
  final bool singleLineLabels;
  final bool inSheet;
  final String? fieldPath;

  void onChangedWrapper(Map<int, List<FilterChange>> filterChangeMap) {
    final filterChanges = filterChangeMap.values.fold(<FilterChange>[], (
      prev,
      curr,
    ) {
      prev.addAll(curr);
      return prev;
    });
    onChanged(
      filterChanges
          .map(
            (groupFilter) => FilterChange(
              groupChange: groupFilter,
              position: kPositionPlaceholder,
            ),
          )
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filterChangeMap = useState<Map<int, List<FilterChange>>>({});

    useEffect(() {
      Map<int, List<FilterChange>> changeMap = {};
      for (final change in currentChanges) {
        if (change.groupChange != null) {
          changeMap[change.groupChange!.position] = [
            ...?changeMap[change.groupChange!.position],
            change.groupChange!,
          ];
        }
      }
      filterChangeMap.value = changeMap;
      return null;
    }, [currentChanges]);

    Widget item(int index) => FilterToWidget(
      key: ValueKey("$name-$index"),
      filter: filters[index],
      currentChanges: filterChangeMap.value[index] ?? const [],
      singleLineLabels: singleLineLabels,
      inSheet: inSheet,
      fieldPath: '${fieldPath ?? name}.$index',
      onChanged: (groupFilter) {
        final updatedGroupFilters = <FilterChange>[];
        for (final filter in groupFilter) {
          updatedGroupFilters.add(filter.copyWith(position: index));
        }
        onChangedWrapper({
          ...filterChangeMap.value,
          index: updatedGroupFilters,
        });
      },
    );
    if (expanded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(name, style: context.textTheme.labelLarge),
          for (var i = 0; i < filters.length; i += 2)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: item(i)),
                if (i + 1 < filters.length)
                  Expanded(child: item(i + 1))
                else
                  const Expanded(child: SizedBox.shrink()),
              ],
            ),
        ],
      );
    }
    return FluentExpansionTile(
      title: Text(name, style: context.textTheme.labelLarge),
      children: [
        for (int index = 0; index < filters.length; index++) item(index),
      ],
    );
  }
}

class _TriStateTile extends StatelessWidget {
  const _TriStateTile({
    required this.name,
    required this.state,
    required this.onChanged,
    this.singleLine = false,
  });
  final String name;
  final TriState state;
  final ValueChanged<TriState> onChanged;
  final bool singleLine;

  @override
  Widget build(BuildContext context) {
    final scheme = context.theme.colorScheme;
    final (icon, next) = switch (state) {
      TriState.INCLUDE => (
        FluentIcons.checkbox_checked_24_regular,
        TriState.EXCLUDE,
      ),
      TriState.EXCLUDE => (
        FluentIcons.dismiss_square_24_regular,
        TriState.IGNORE,
      ),
      _ => (FluentIcons.checkbox_unchecked_24_regular, TriState.INCLUDE),
    };
    return ListTile(
      leading: Icon(
        icon,
        color: state == TriState.IGNORE
            ? scheme.onSurfaceVariant
            : scheme.primary,
      ),
      title: singleLine && name.isNotBlank
          ? Tooltip(
              message: name,
              child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
            )
          : Text(name),
      onTap: () => onChanged(next),
      contentPadding: singleLine ? EdgeInsets.zero : null,
      horizontalTitleGap: singleLine ? 8 : null,
      dense: singleLine ? true : null,
      visualDensity: singleLine ? VisualDensity.compact : null,
    );
  }
}
