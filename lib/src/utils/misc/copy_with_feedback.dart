import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../extensions/custom_extensions.dart';

/// Copies [text] and confirms it with a light haptic and a short snackbar.
void copyWithFeedback(BuildContext context, String text) {
  if (text.trim().isEmpty) return;
  Clipboard.setData(ClipboardData(text: text)).ignore();
  HapticFeedback.selectionClick().ignore();
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(context.l10n.copiedToClipboard),
        duration: const Duration(milliseconds: 1400),
      ),
    );
}
