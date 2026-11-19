import 'package:flutter_test/flutter_test.dart';
import 'package:kuchie/src/features/browse_center/domain/filter/filter_model.dart';
import 'package:kuchie/src/features/local_collection/data/local_source_filters.dart';

// The filter list the Kiryuu extension reports through the runtime.
final _kiryuu = <Map<String, Object?>>[
  {
    'name': 'Sort',
    'state': {'index': 0, 'ascending': false},
    'values': ['Popular', 'Rating', 'Updated', 'Bookmarked', 'Title'],
  },
  {
    'name': 'Type',
    'state': [
      {'name': 'Manga', 'state': false},
      {'name': 'Manhwa', 'state': false},
    ],
  },
  {'name': 'Project Only', 'state': false},
  {'name': '', 'state': 0},
  {'name': "Tap 'Reset' to load filters", 'state': 0},
  {
    'name': 'Status',
    'state': 0,
    'values': ['All', 'Ongoing', 'Completed'],
  },
];

void main() {
  test('reads runtime filters into the Server filter model', () {
    final filters = filtersFromRuntime(_kiryuu);
    expect(filters.map((filter) => filter.runtimeType.toString()), [
      contains('SortFilter'),
      contains('GroupFilter'),
      contains('CheckBoxFilter'),
      contains('SeparatorFilter'),
      contains('HeaderFilter'),
      contains('SelectFilter'),
    ]);
    final sort = filters.first as FilterSort;
    expect(sort.displayValues, hasLength(5));
    expect(sort.sortState?.ascending, isFalse);
    final group = filters[1] as FilterGroup;
    expect(group.groupState, hasLength(2));
  });

  test('sends nothing until the reader changes a filter', () {
    expect(runtimeFilterList(_kiryuu, const []), isEmpty);
  });

  test('turns changes into the runtime filter list, matched by name', () {
    final list = runtimeFilterList(_kiryuu, [
      FilterChange(
        position: 0,
        sortState: SortStateChange(index: 4, ascending: true),
      ),
      FilterChange(
        position: 1,
        groupChange: FilterChange(position: 1, checkBoxState: true),
      ),
      FilterChange(position: 2, checkBoxState: true),
      FilterChange(position: 5, selectState: 2),
    ]);
    final byName = {for (final entry in list) entry['name']: entry};
    // Headers and separators carry no state to send.
    expect(byName.keys, ['Sort', 'Type', 'Project Only', 'Status']);
    expect(byName['Sort']!['stateSort'], {'index': 4, 'ascending': true});
    expect(byName['Type']!['stateList'], [
      {'name': 'Manga', 'type': 'CheckBox', 'stateBoolean': false},
      {'name': 'Manhwa', 'type': 'CheckBox', 'stateBoolean': true},
    ]);
    expect(
      (byName['Project Only']!['stateList']! as List).single,
      containsPair('stateBoolean', true),
    );
    expect(byName['Status']!['stateInt'], 2);
  });
}
