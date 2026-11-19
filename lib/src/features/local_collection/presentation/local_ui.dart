import 'dart:async' show TimeoutException;
import 'dart:io' show HttpException, SocketException;

import 'package:material_ui/material_ui.dart';

import '../../../widgets/popup_widgets/app_dialog.dart';
import '../data/local_mihon_runtime.dart';
import '../data/local_sources.dart';

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

/// Why a repository or package was refused, in words a reader can act on.
String localSecurityMessage(
  BuildContext context,
  LocalSourceSecurityException error,
) => error.insecureUrl
    ? localText(
        context,
        'Use an HTTPS address without a username, password or # fragment.',
        'Gunakan alamat HTTPS tanpa nama pengguna, kata sandi, atau fragmen #.',
      )
    : localText(
        context,
        'This extension failed a security check and was not installed.',
        'Ekstensi ini gagal pemeriksaan keamanan dan tidak dipasang.',
      );

/// Why [error] happened, in words a reader can act on.
String localErrorMessage(BuildContext context, Object error) => switch (error) {
  LocalSourceSecurityException() => localSecurityMessage(context, error),
  MihonRuntimeUnavailable(missing: true) => localText(
    context,
    'Extensions need the extension runtime, which this build does not include.',
    'Ekstensi butuh runtime ekstensi, yang tidak ada di build ini.',
  ),
  // Startup failed or timed out this time; the next attempt usually works.
  MihonRuntimeUnavailable() => localText(
    context,
    'The extension runtime is still starting or stopped responding. Try again.',
    'Runtime ekstensi masih memulai atau tidak merespons. Coba lagi.',
  ),
  TimeoutException() => localText(
    context,
    'The source took too long to respond. Try again.',
    'Sumber terlalu lama merespons. Coba lagi.',
  ),
  MihonRuntimeException(looksBlocked: true, :final detail) => localText(
    context,
    'The site blocked the request ($detail). Open it in WebView to pass the check, or change the user agent in Settings → Advanced.',
    'Situs memblokir permintaan ($detail). Buka di WebView untuk lolos pemeriksaan, atau ganti user agent di Pengaturan → Lanjutan.',
  ),
  MihonRuntimeException(:final detail?) => localText(
    context,
    'The extension could not complete this request: $detail',
    'Ekstensi gagal memproses permintaan ini: $detail',
  ),
  MihonRuntimeException() => localText(
    context,
    'The extension could not complete this request.',
    'Ekstensi gagal memproses permintaan ini.',
  ),
  SocketException() || HttpException() => localText(
    context,
    'Could not reach the site. Check your connection and try again.',
    'Tidak dapat menghubungi situs. Periksa koneksi lalu coba lagi.',
  ),
  LocalSourceRetiredStoreException(:final storeName) => localText(
    context,
    '$storeName no longer publishes extensions. Remove it and add Keiyoushi '
        'instead.',
    '$storeName sudah tidak menerbitkan ekstensi. Hapus store ini dan '
        'tambahkan Keiyoushi.',
  ),
  FormatException() => localText(
    context,
    'This file or repository is invalid or unsupported.',
    'File atau repositori ini tidak valid atau belum didukung.',
  ),
  StateError(:final message) => message,
  _ => localText(
    context,
    'Could not complete the action. Try again.',
    'Tindakan gagal. Silakan coba lagi.',
  ),
};

void localFailure(BuildContext context, Object error) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(localErrorMessage(context, error))));
}
