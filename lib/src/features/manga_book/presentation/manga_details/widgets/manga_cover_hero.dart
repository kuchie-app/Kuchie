import 'package:material_ui/material_ui.dart';

import '../../../../../utils/theme/brand.dart';

class MangaCoverHero extends StatelessWidget {
  const MangaCoverHero({
    super.key,
    required this.backdrop,
    required this.child,
  });

  final Widget backdrop;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(child: backdrop),
      Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                OnImage.lightThemeCoverHeroTopScrim,
                OnImage.lightThemeCoverHeroMiddleScrim,
                Theme.of(context).scaffoldBackgroundColor,
              ],
            ),
          ),
        ),
      ),
      Theme(
        data: Theme.of(context).copyWith(
          textTheme: Theme.of(context).textTheme.apply(
            bodyColor: OnImage.text,
            displayColor: OnImage.text,
          ),
        ),
        child: child,
      ),
    ],
  );
}
