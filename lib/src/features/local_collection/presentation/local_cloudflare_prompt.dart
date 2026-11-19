import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../../utils/extensions/custom_extensions.dart';
import '../../../widgets/app_bottom_sheet.dart';
import '../../../widgets/in_app_web_view.dart';
import '../data/local_network_settings.dart';
import '../data/remote_webview/remote_webview_session.dart';

/// Asks the reader to pass Cloudflare checks the hidden browser could not,
/// while [child] is on screen.
class LocalCloudflarePromptHost extends StatefulWidget {
  const LocalCloudflarePromptHost({super.key, required this.child});

  final Widget child;

  @override
  State<LocalCloudflarePromptHost> createState() =>
      _LocalCloudflarePromptHostState();
}

class _LocalCloudflarePromptHostState extends State<LocalCloudflarePromptHost> {
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    unawaited(LocalNetworkSettings.instance.load());
    RemoteWebViewSession.onChallenge = _onChallenge;
  }

  @override
  void dispose() {
    if (RemoteWebViewSession.onChallenge == _onChallenge) {
      RemoteWebViewSession.onChallenge = null;
    }
    super.dispose();
  }

  void _onChallenge(RemoteWebViewChallenge challenge) {
    final settings = LocalNetworkSettings.instance;
    if (!mounted ||
        _showing ||
        !settings.autoBypass.value ||
        settings.isMuted(challenge.url.host)) {
      return;
    }
    _showing = true;
    unawaited(_prompt(challenge).whenComplete(() => _showing = false));
  }

  Future<void> _prompt(RemoteWebViewChallenge challenge) async {
    final host = challenge.url.host;
    final route = ModalRoute.of(context);
    var open = true;
    // The hidden page can still clear on its own; drop the question then.
    unawaited(
      challenge.cleared.then((_) {
        if (open && mounted) Navigator.of(context).maybePop();
      }),
    );
    final choice = await showAppBottomSheet<_Choice>(
      context: context,
      builder: (sheet) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSheetHeader(title: sheet.l10n.cloudflareCheckTitle),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(sheet.l10n.cloudflareCheckBody(host)),
          ),
          ListTile(
            leading: const Icon(FluentIcons.shield_checkmark_24_regular),
            title: Text(sheet.l10n.cloudflareCheckVerify),
            onTap: () => Navigator.pop(sheet, _Choice.verify),
          ),
          ListTile(
            leading: const Icon(FluentIcons.alert_off_24_regular),
            title: Text(sheet.l10n.cloudflareCheckMute),
            onTap: () => Navigator.pop(sheet, _Choice.mute),
          ),
          ListTile(
            leading: const Icon(FluentIcons.dismiss_24_regular),
            title: Text(MaterialLocalizations.of(sheet).cancelButtonLabel),
            onTap: () => Navigator.pop(sheet),
          ),
          SizedBox(height: MediaQuery.paddingOf(sheet).bottom),
        ],
      ),
    );
    open = false;
    if (!mounted || route?.isActive == false) return;
    switch (choice) {
      case _Choice.verify:
        // Same user agent as the hidden page: Cloudflare ties the clearance
        // cookie to it, and both browsers share one cookie store.
        await openInAppWebView(
          context,
          challenge.url.toString(),
          userAgent: challenge.userAgent,
        );
        await challenge.retry();
      case _Choice.mute:
        await LocalNetworkSettings.instance.mute(host);
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

enum _Choice { verify, mute }
