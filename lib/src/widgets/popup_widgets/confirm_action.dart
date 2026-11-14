import 'package:material_ui/material_ui.dart';

import '../../utils/theme/oklch_contrast.dart';
import '../ios/apple_glass_capability.dart';
import 'app_dialog.dart';
import 'pop_button.dart';

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
  bool destructive = false,
}) async =>
    await showAppDialog<bool>(
      context: context,
      builder: (context) {
        final colors = Theme.of(context).colorScheme;
        void confirm() => Navigator.pop(context, true);
        return AppDialogPanel(
          title: title,
          content: Text(message),
          actions: [
            const PopButton(),
            if (appleGlassEnabled(context))
              FilledButton(
                onPressed: confirm,
                style: destructive
                    ? FilledButton.styleFrom(
                        backgroundColor: colors.error,
                        foregroundColor: contrastingMonochromeForeground(
                          colors.error,
                        ),
                      )
                    : null,
                child: Text(action),
              )
            else
              TextButton(
                onPressed: confirm,
                style: destructive
                    ? TextButton.styleFrom(foregroundColor: colors.error)
                    : null,
                child: Text(action),
              ),
          ],
        );
      },
    ) ==
    true;
