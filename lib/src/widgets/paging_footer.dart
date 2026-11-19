import 'package:material_ui/material_ui.dart';

/// The end of a paged list while more pages exist.
///
/// The paging package keeps its next-page indicator built whenever another
/// page exists, even far below the screen, and an indicator's animation then
/// ticks at 60 frames a second on an idle page. This shows [child] only while
/// a page is loading and an empty space of [height] otherwise.
class PagingFooter extends StatelessWidget {
  const PagingFooter({
    super.key,
    required this.loading,
    required this.child,
    this.height = 80,
  });

  final bool loading;
  final Widget child;
  final double height;

  @override
  Widget build(BuildContext context) =>
      loading ? child : SizedBox(height: height);
}
