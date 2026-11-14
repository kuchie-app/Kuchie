import 'package:material_ui/material_ui.dart';

import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/motion/reduce_motion.dart';
import '../../../../../widgets/kuchie_character_motion.dart';

/// Shown only after the active download view observes a confirmed completion.
void showDownloadCompletionFeedback(BuildContext context, int completed) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger.showSnackBar(
    SnackBar(
      content: Row(
        spacing: 8,
        children: [
          const KuchieCharacterMotion(
            phase: KuchieCharacterPhase.complete,
            width: 64,
          ),
          Expanded(
            child: Text(
              context.l10n.notificationDownloadsCompleteBody(completed),
            ),
          ),
        ],
      ),
    ),
    snackBarAnimationStyle: context.snackBarMotionStyle,
  );
}
