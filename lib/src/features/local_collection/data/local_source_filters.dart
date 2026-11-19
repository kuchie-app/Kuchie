import '../../browse_center/domain/filter/filter_model.dart';

// Mihon extensions describe their filters to the runtime as JSON entries of
// `name`, `state` and, for selections and sorts, `values`. Kuchie shows them
// with the same filter sheet as the Server collection, so they are converted
// to the Server's filter model, and the reader's changes back into the
// runtime's JFilterList, which it matches to the extension's filters by name.

/// Mihon's TriState values: 0 ignore, 1 include, 2 exclude.
const _ignore = 0, _include = 1, _exclude = 2;

String _valueLabel(Object? value) => switch (value) {
  final String text => text,
  {'name': final String name} => name,
  _ => '$value',
};

List<String> _values(Object? raw) => [
  if (raw is List)
    for (final value in raw) _valueLabel(value),
];

String _triState(Object? state) => switch (state) {
  _include => 'INCLUDE',
  _exclude => 'EXCLUDE',
  _ => 'IGNORE',
};

Map<String, Object?>? _primitive(Map<String, Object?> raw) {
  final name = '${raw['name'] ?? ''}';
  final state = raw['state'];
  final values = raw['values'];
  return switch (state) {
    final bool checked => {
      '__typename': 'CheckBoxFilter',
      'name': name,
      'checkBoxState': checked,
    },
    final String text => {
      '__typename': 'TextFilter',
      'name': name,
      'textState': text,
    },
    final int index when values is List => {
      '__typename': 'SelectFilter',
      'name': name,
      'selectState': index,
      'displayValues': _values(values),
    },
    {'index': final Object? index, 'ascending': final Object? ascending}
        when values is List =>
      {
        '__typename': 'SortFilter',
        'name': name,
        'sortState': {
          '__typename': 'SortSelection',
          'ascending': ascending == true,
          'index': index is int ? index : null,
        },
        'displayValues': _values(values),
      },
    // A header and a separator also carry 0; only a set TriState stands out.
    final int value when value != _ignore => {
      '__typename': 'TriStateFilter',
      'name': name,
      'tristate': _triState(value),
    },
    _ when name.trim().isEmpty => {
      '__typename': 'SeparatorFilter',
      'name': name,
    },
    _ => {'__typename': 'HeaderFilter', 'name': name},
  };
}

/// The extension's filters in the Server filter model.
List<Filter> filtersFromRuntime(List<Map<String, Object?>> raw) => [
  for (final entry in raw) ?_filter(entry),
];

Filter? _filter(Map<String, Object?> raw) {
  final state = raw['state'];
  if (state is List) {
    final children = <Map<String, Object?>>[];
    for (final child in state) {
      if (child is! Map) continue;
      final map = {for (final e in child.entries) '${e.key}': e.value};
      // Inside a group a 0 is an ignored TriState, never a header.
      final value = map['state'];
      children.add(
        value is int && map['values'] is! List
            ? {
                '__typename': 'TriStateFilter',
                'name': '${map['name'] ?? ''}',
                'tristate': _triState(value),
              }
            : _primitive(map)!,
      );
    }
    return Filter.fromJson({
      '__typename': 'GroupFilter',
      'name': '${raw['name'] ?? ''}',
      'groupState': children,
    });
  }
  final primitive = _primitive(raw);
  return primitive == null ? null : Filter.fromJson(primitive);
}

/// The runtime's JFilterList for [raw] with the reader's [changes] applied;
/// empty when nothing differs from the extension's defaults.
List<Map<String, Object?>> runtimeFilterList(
  List<Map<String, Object?>> raw,
  List<FilterChange> changes,
) {
  if (changes.isEmpty) return const [];
  final byPosition = <int, List<FilterChange>>{};
  for (final change in changes) {
    byPosition.putIfAbsent(change.position, () => []).add(change);
  }
  final list = <Map<String, Object?>>[];
  for (final (index, entry) in raw.indexed) {
    final name = '${entry['name'] ?? ''}';
    final state = entry['state'];
    final changed = byPosition[index] ?? const <FilterChange>[];
    FilterChange? last() => changed.lastOrNull;
    switch (state) {
      case List<Object?>():
        final childChanges = <int, FilterChange>{};
        for (final change in changed) {
          final child = change.groupChange;
          if (child != null) childChanges[child.position] = child;
        }
        list.add({
          'name': name,
          'type': 'Group',
          'stateList': [
            for (final (childIndex, child) in state.indexed)
              if (child is Map)
                _groupChild({
                  for (final e in child.entries) '${e.key}': e.value,
                }, childChanges[childIndex]),
          ],
        });
      case final bool checked:
        list.add({
          'name': name,
          'type': 'CheckBox',
          'stateList': [
            {
              'name': name,
              'type': 'CheckBox',
              'stateBoolean': last()?.checkBoxState ?? checked,
            },
          ],
        });
      case final String text:
        list.add({
          'name': name,
          'type': 'Text',
          'stateString': last()?.textState ?? text,
        });
      case final int value when entry['values'] is List:
        list.add({
          'name': name,
          'type': 'Select',
          'stateInt': last()?.selectState ?? value,
        });
      case {'index': final Object? index, 'ascending': final Object? ascending}:
        final sort = last()?.sortState;
        list.add({
          'name': name,
          'type': 'Sort',
          'stateSort': {
            'index': sort?.index ?? (index is int ? index : 0),
            'ascending': sort?.ascending ?? ascending == true,
          },
        });
      case final int value:
        final tri = last()?.triState;
        if (tri == null && value == _ignore) break; // A header or separator.
        list.add({
          'name': name,
          'type': 'TriState',
          'stateInt': tri == null ? value : _fromTriState(tri),
        });
    }
  }
  return list;
}

Map<String, Object?> _groupChild(
  Map<String, Object?> child,
  FilterChange? change,
) {
  final name = '${child['name'] ?? ''}';
  return switch (child['state']) {
    final bool checked => {
      'name': name,
      'type': 'CheckBox',
      'stateBoolean': change?.checkBoxState ?? checked,
    },
    final int value when child['values'] is List => {
      'name': name,
      'type': 'Select',
      'stateInt': change?.selectState ?? value,
    },
    final int value => {
      'name': name,
      'type': 'TriState',
      'stateInt': change?.triState == null
          ? value
          : _fromTriState(change!.triState!),
    },
    final String text => {
      'name': name,
      'type': 'Text',
      'stateString': change?.textState ?? text,
    },
    _ => {'name': name, 'type': 'Header'},
  };
}

int _fromTriState(TriState state) => switch (state) {
  TriState.INCLUDE => _include,
  TriState.EXCLUDE => _exclude,
  _ => _ignore,
};
