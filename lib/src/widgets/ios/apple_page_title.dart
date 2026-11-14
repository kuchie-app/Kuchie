import 'package:material_ui/material_ui.dart';

import '../../utils/extensions/custom_extensions.dart';
import 'apple_glass_capability.dart';

class ApplePageTitle extends StatelessWidget {
  const ApplePageTitle(this.text, {super.key, this.cloud = false});

  final String text;
  final bool cloud;

  @override
  Widget build(BuildContext context) {
    if (!supportsAppleGlass(context)) return Text(text);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.textTheme.headlineMedium?.copyWith(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.9,
              height: 1.15,
            ),
          ),
        ),
        if (cloud) ...[
          const SizedBox(width: 8),
          const ExcludeSemantics(child: Icon(Icons.cloud_outlined, size: 21)),
        ],
      ],
    );
  }
}
