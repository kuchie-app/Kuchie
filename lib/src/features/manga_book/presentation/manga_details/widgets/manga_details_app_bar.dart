import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../utils/theme/brand.dart';
import '../../../../../widgets/shell/detail_navigation_shell_screen.dart';

class MangaDetailsAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const MangaDetailsAppBar({
    super.key,
    required this.title,
    required this.actions,
    required this.scrollOffset,
    required this.coverBehindBar,
    this.twoColumn = false,
  });

  final Widget title;
  final List<Widget> actions;
  final ValueListenable<double> scrollOffset;
  final bool coverBehindBar;
  final bool twoColumn;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).scaffoldBackgroundColor;
    return ValueListenableBuilder<double>(
      valueListenable: scrollOffset,
      builder: (context, offset, _) {
        final t = (offset / 160).clamp(0.0, 1.0);
        return detailNavigationBar(
          context,
          (leading) => AppBar(
            leading: leading,
            backgroundColor: twoColumn
                ? surface
                : Color.lerp(Colors.transparent, surface, t),
            elevation: 0,
            scrolledUnderElevation: 0,
            systemOverlayStyle: coverBehindBar && t < .55
                ? SystemUiOverlayStyle.light
                : null,
            flexibleSpace: twoColumn || t >= 1
                ? null
                : DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          OnImage.shadow.withValues(alpha: .45 * (1 - t)),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
            title: twoColumn ? title : Opacity(opacity: t, child: title),
            actions: actions,
          ),
        );
      },
    );
  }
}
