import 'package:material_ui/material_ui.dart';

import '../../../widgets/popup_widgets/app_dialog.dart';
import '../data/local_mihon_runtime.dart';

String localText(BuildContext context, String english, String indonesian) =>
    Localizations.localeOf(context).languageCode == 'id' ? indonesian : english;

Future<String?> localInput(
  BuildContext context,
  String title,
  String label, {
  String? initial,
}) async {
  var value = initial ?? '';
  return showAppDialog<String>(
    context: context,
    builder: (context) => AppDialogPanel(
      title: title,
      content: TextFormField(
        initialValue: initial,
        autofocus: true,
        decoration: InputDecoration(labelText: label),
        onChanged: (text) => value = text,
        onFieldSubmitted: (text) {
          if (text.trim().isNotEmpty) Navigator.pop(context, text.trim());
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: () {
            if (value.trim().isNotEmpty) Navigator.pop(context, value.trim());
          },
          child: Text(MaterialLocalizations.of(context).okButtonLabel),
        ),
      ],
    ),
  );
}

Future<bool> localConfirm(
  BuildContext context,
  String title,
  String body,
) async =>
    await showAppDialog<bool>(
      context: context,
      builder: (context) => AppDialogPanel(
        title: title,
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(MaterialLocalizations.of(context).okButtonLabel),
          ),
        ],
      ),
    ) ??
    false;

void localFailure(BuildContext context, Object error) {
  if (!context.mounted) return;
  final message = switch (error) {
    MihonRuntimeUnavailable() => localText(
      context,
      'The extension runtime is unavailable on this build.',
      'Runtime ekstensi belum tersedia di build ini.',
    ),
    MihonRuntimeException() => localText(
      context,
      'The extension could not complete this request.',
      'Ekstensi gagal memproses permintaan ini.',
    ),
    FormatException() => localText(
      context,
      'This file or repository is invalid or unsupported.',
      'File atau repositori ini tidak valid atau belum didukung.',
    ),
    _ => localText(
      context,
      'Could not complete the action. Try again.',
      'Tindakan gagal. Silakan coba lagi.',
    ),
  };
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
