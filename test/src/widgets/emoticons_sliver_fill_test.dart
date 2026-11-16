import 'package:flutter_test/flutter_test.dart';
import 'package:kuchie/src/widgets/emoticons.dart';
import 'package:material_ui/material_ui.dart';

/// Empty states sit under headers in a CustomScrollView. Emoticons sizes itself
/// with a LayoutBuilder, which cannot report intrinsic dimensions, so the fill
/// sliver must not measure it (hasScrollBody: true).
void main() {
  Future<void> pumpEmptyState(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(child: SizedBox(height: 108)),
            SliverFillRemaining(
              child: Emoticons(
                title: 'Nothing here',
                button: TextButton(onPressed: () {}, child: const Text('Add')),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  testWidgets('Emoticons empty state lays out below a header', (tester) async {
    await pumpEmptyState(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Nothing here'), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);
    // Fills the space below the header so the message stays centered.
    final fill = tester.getRect(find.byType(Emoticons));
    expect(fill.top, 108);
    expect(fill.bottom, tester.getRect(find.byType(CustomScrollView)).bottom);
  });

  // Paged lists put first-page error and empty states in a fill sliver that
  // measures its child, so a failing source showed a blank page while the
  // LayoutBuilder assertion repeated every frame.
  testWidgets('Emoticons fits a fill sliver that measures its child', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              const SliverToBoxAdapter(child: SizedBox(height: 54)),
              SliverFillRemaining(
                hasScrollBody: false,
                child: Emoticons(
                  title: 'Could not load manga',
                  button: TextButton(
                    onPressed: () {},
                    child: const Text('Retry'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Could not load manga'), findsOneWidget);
    expect(find.text('Retry').hitTestable(), findsOneWidget);
    final fill = tester.getRect(find.byType(Emoticons));
    expect(fill.top, 54);
    expect(fill.bottom, tester.getRect(find.byType(CustomScrollView)).bottom);
  });
}
