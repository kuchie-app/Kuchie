import 'package:material_ui/material_ui.dart';

/// Space a scroll view needs under its last item to clear the floating tab
/// bar (and the home indicator). Scaffolds with `extendBody` report the bar
/// in the bottom padding, which ListView applies only when it has no padding
/// of its own and CustomScrollView never applies.
double scrollBottomInset(BuildContext context, {double extra = 16}) =>
    MediaQuery.paddingOf(context).bottom + extra;

/// [scrollBottomInset] as the last sliver of a CustomScrollView.
class SliverBottomInset extends StatelessWidget {
  const SliverBottomInset({super.key, this.extra = 16});

  final double extra;

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
    child: SizedBox(height: scrollBottomInset(context, extra: extra)),
  );
}
