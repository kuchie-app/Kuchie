import 'package:flutter_test/flutter_test.dart';
import 'package:kuchie/src/features/browse_center/domain/source/source_model.dart';
import 'package:kuchie/src/routes/router_config.dart';
import 'package:kuchie/src/widgets/ios/collapsing_title_scaffold.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('a search field under the title spans the page like the tabs', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: CollapsingTitleScaffold(
          title: 'Local source',
          below: const SizedBox(key: Key('search'), height: 44),
          pinned: const PreferredSize(
            preferredSize: Size.fromHeight(48),
            child: SizedBox.shrink(),
          ),
          actions: const [],
          body: ListView(children: const [SizedBox(height: 2000)]),
        ),
      ),
    );
    await tester.pump();
    final field = tester.getRect(find.byKey(const Key('search')));
    expect(field.left, 16);
    expect(field.width, 402 - 32, reason: 'not a short field in the middle');
  });

  test('a kept search travels with popular and latest', () {
    const route = SourceTypeRoute(
      sourceId: '1',
      sourceType: SourceType.LATEST,
      search: 'one piece',
    );
    expect(Uri.parse(route.location).queryParameters['search'], 'one piece');
    expect(
      Uri.parse(
        const SourceTypeRoute(
          sourceId: '1',
          sourceType: SourceType.POPULAR,
        ).location,
      ).queryParameters,
      isEmpty,
      reason: 'clearing the search drops it from the page',
    );
  });
}
