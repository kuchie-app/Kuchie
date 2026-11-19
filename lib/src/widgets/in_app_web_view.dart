// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/extensions/custom_extensions.dart';
import '../utils/launch_url_in_web.dart';
import '../utils/misc/toast/toast.dart';
import 'ios/apple_glass_capability.dart';
import 'ios/apple_glass_toolbar.dart';

const _viewType = 'kuchie/in_app_web_view';

Uri? _pageUri(String? input) {
  if (input == null) return null;
  final uri = Uri.tryParse(input.trim());
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  return uri;
}

Future<void> openInAppWebView(
  BuildContext context,
  String url, {
  String? serverWebViewUrl,
  Toast? toast,
  String? userAgent,
}) async {
  final serverUri = _pageUri(serverWebViewUrl);
  final uri = _pageUri(url) ?? serverUri;
  if (uri == null) {
    toast?.showError(context.l10n.webPageLoadFailed);
    return;
  }
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(
        builder: (_) => _InAppWebView(
          initial: uri,
          serverWebView: serverUri == uri ? null : serverUri,
          toast: toast,
          userAgent: userAgent,
        ),
      ),
    );
    return;
  }
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    final target = serverUri ?? uri;
    final mode = await supportsLaunchMode(LaunchMode.inAppBrowserView)
        ? LaunchMode.inAppBrowserView
        : LaunchMode.inAppWebView;
    if (!context.mounted) return;
    if (await launchUrl(target, mode: mode)) return;
  }
  if (context.mounted) {
    await launchUrlInWeb(context, (serverUri ?? uri).toString(), toast);
  }
}

/// Builds the Suwayomi endpoint used to manage the source's server-side cookies.
String? serverWebViewLink(String apiBase, String? sourceUrl) {
  if (sourceUrl.isBlank || apiBase.isBlank) return null;
  final base = _pageUri(apiBase);
  if (base == null) return null;
  final path = base.path.endsWith('/') ? base.path : '${base.path}/';
  return base.replace(path: '${path}webview', fragment: sourceUrl).toString();
}

class _InAppWebView extends StatefulWidget {
  const _InAppWebView({
    required this.initial,
    this.serverWebView,
    this.toast,
    this.userAgent,
  });

  final Uri initial;
  final Uri? serverWebView;
  final Toast? toast;

  /// Sent instead of Safari's own, so cookies a site ties to the user agent
  /// (Cloudflare clearance) also work for extensions.
  final String? userAgent;

  @override
  State<_InAppWebView> createState() => _InAppWebViewState();
}

class _InAppWebViewState extends State<_InAppWebView> {
  MethodChannel? _channel;
  var _stateReceived = false;
  double _bottomInset = 0;
  String? _title;
  Uri? _url;
  var _canGoBack = false;
  var _canGoForward = false;
  var _loading = true;
  var _progress = .0;
  var _failed = false;

  Uri get _current => _url ?? widget.initial;

  Future<void> _onCreated(int viewId) async {
    if (!mounted) return;
    final channel = MethodChannel('$_viewType/$viewId');
    _channel = channel;
    channel.setMethodCallHandler((call) async {
      if (call.method != 'stateChanged') throw MissingPluginException();
      _stateReceived = true;
      _update(call.arguments);
    });
    final state = await channel.invokeMethod<Object?>('state');
    if (!_stateReceived) _update(state);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bottomInset = supportsAppleGlass(context)
        ? MediaQuery.paddingOf(context).bottom + 64
        : 0.0;
    if (_bottomInset == bottomInset) return;
    _bottomInset = bottomInset;
    unawaited(_channel?.invokeMethod<void>('setBottomInset', bottomInset));
  }

  void _update(Object? state) {
    if (!mounted || state is! Map) return;
    setState(() {
      _title = state['title'] as String?;
      _url = _pageUri(state['url'] as String?);
      _canGoBack = state['canGoBack'] == true;
      _canGoForward = state['canGoForward'] == true;
      _loading = state['loading'] == true;
      _progress = (state['progress'] as num?)?.toDouble() ?? 0;
      _failed = state['failed'] == true;
    });
  }

  void _navigate(String action) =>
      unawaited(_channel?.invokeMethod<void>(action));

  void _openInBrowser() =>
      launchUrlInWeb(context, _current.toString(), widget.toast);

  Future<void> _copyUrl() async {
    await Clipboard.setData(ClipboardData(text: _current.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.copiedToClipboard)));
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    AppleGlassToolbarAction openInBrowser(String id) => AppleGlassToolbarAction(
      id: id,
      symbol: 'safari',
      label: l10n.openInBrowser,
      fallbackIcon: Icons.open_in_browser_rounded,
      onPressed: _openInBrowser,
    );
    final reload = AppleGlassToolbarAction(
      id: 'reload',
      symbol: 'arrow.clockwise',
      label: l10n.reload,
      fallbackIcon: Icons.refresh_rounded,
      onPressed: _channel == null ? null : () => _navigate('reload'),
    );
    final more = AppleGlassToolbarAction(
      id: 'more',
      symbol: 'ellipsis',
      label: l10n.more,
      fallbackIcon: Icons.more_horiz_rounded,
      onPressed: null,
      menu: [
        AppleGlassToolbarMenuItem(
          id: 'copy-url',
          title: l10n.copyToClipboard,
          symbol: 'doc.on.doc',
          fallbackIcon: Icons.copy_rounded,
          onSelected: _copyUrl,
        ),
        if (widget.serverWebView case final serverUri?)
          AppleGlassToolbarMenuItem(
            id: 'open-server-webview',
            title: l10n.openServerWebView,
            symbol: 'server.rack',
            fallbackIcon: Icons.dns_outlined,
            onSelected: () => openInAppWebView(
              context,
              serverUri.toString(),
              toast: widget.toast,
            ),
          ),
      ],
    );
    final glass = supportsAppleGlass(context);
    final bottomPadding = MediaQuery.paddingOf(context).bottom + 6;
    final navigation = AppleGlassToolbar(
      actions: [
        AppleGlassToolbarAction(
          id: 'previous',
          symbol: 'arrow.backward',
          label: l10n.back,
          fallbackIcon: Icons.arrow_back_rounded,
          onPressed: _canGoBack ? () => _navigate('back') : null,
        ),
        AppleGlassToolbarAction(
          id: 'next',
          symbol: 'arrow.forward',
          label: l10n.next,
          fallbackIcon: Icons.arrow_forward_rounded,
          onPressed: _canGoForward ? () => _navigate('forward') : null,
        ),
        reload,
        openInBrowser('web-view-bottom-open-browser'),
      ],
      joined: true,
    );
    final domain = _current.hasPort
        ? '${_current.host}:${_current.port}'
        : _current.host;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
              child: Row(
                children: [
                  AppleGlassToolbarButton(
                    id: 'close-web-view',
                    symbol: 'chevron.backward',
                    label: l10n.close,
                    fallbackIcon: Icons.arrow_back_ios_new_rounded,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Column(
                        children: [
                          Text(
                            _title.isNotBlank ? _title! : l10n.webView,
                            style: theme.textTheme.titleSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            domain,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            textDirection: TextDirection.ltr,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                  AppleGlassToolbar(
                    actions: [openInBrowser('web-view-top-open-browser'), more],
                    joined: true,
                  ),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: UiKitView(
                      viewType: _viewType,
                      layoutDirection: Directionality.of(context),
                      creationParams: {
                        'url': widget.initial.toString(),
                        'bottomInset': _bottomInset,
                        'userAgent': ?widget.userAgent,
                      },
                      gestureBlockingPolicy:
                          UiKitViewGestureBlockingPolicy.doNotBlockGesture,
                      creationParamsCodec: const StandardMessageCodec(),
                      onPlatformViewCreated: _onCreated,
                      gestureRecognizers: {
                        Factory<OneSequenceGestureRecognizer>(
                          EagerGestureRecognizer.new,
                        ),
                      },
                    ),
                  ),
                  if (_failed)
                    Positioned.fill(
                      child: ColoredBox(
                        color: theme.colorScheme.surface,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Wrap(
                              alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              runSpacing: 12,
                              spacing: 8,
                              children: [
                                SizedBox(
                                  width: double.infinity,
                                  child: Text(
                                    l10n.webPageLoadFailed,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                FilledButton(
                                  onPressed: reload.onPressed,
                                  child: Text(l10n.retry),
                                ),
                                TextButton(
                                  onPressed: _openInBrowser,
                                  child: Text(l10n.openInBrowser),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (_loading && !_failed)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      child: LinearProgressIndicator(
                        value: _progress > 0 ? _progress : null,
                      ),
                    ),
                  if (glass)
                    Positioned(
                      bottom: bottomPadding,
                      left: 0,
                      right: 0,
                      child: Center(child: navigation),
                    ),
                ],
              ),
            ),
            if (!glass)
              Padding(
                padding: EdgeInsets.only(top: 8, bottom: bottomPadding),
                child: navigation,
              ),
          ],
        ),
      ),
    );
  }
}
