import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'remote_webview/remote_webview_server.dart';

/// Which `User-Agent` extensions in the Local collection send.
enum LocalUserAgent {
  /// Desktop Chrome, Mihon's default and what extensions are written for.
  desktopChrome,

  /// The runtime's original desktop Firefox string. Cloudflare blocks it on
  /// some sites (Doujindesu answers error 1010), since Java's TLS handshake
  /// does not look like Firefox.
  desktopFirefox,

  /// This iPhone's Safari, as the system WebView reports it. The default:
  /// some sites (Danbooru) show Cloudflare checks to desktop browsers only,
  /// and it matches the browser Kuchie opens to pass a check.
  device,
  desktopSafari,
  custom,
}

/// Network settings for extensions in the Local collection.
///
/// The runtime reads the `User-Agent` of each request Kuchie sends it and
/// makes that the default for the extension's own requests. Cloudflare ties
/// its clearance cookie to a user agent, so the browser Kuchie opens to pass a
/// check uses the same one.
class LocalNetworkSettings {
  LocalNetworkSettings._();

  static final instance = LocalNetworkSettings._();

  /// `NetworkHelper.DEFAULT_USER_AGENT` in the pinned runtime.
  static const desktopFirefoxUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:136.0) Gecko/20100101 Firefox/136.0';
  static const desktopChromeUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36';

  /// Used when the WebView cannot report its own string.
  static const mobileSafariUserAgent =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 '
      'Safari/604.1';
  static const desktopSafariUserAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 '
      '(KHTML, like Gecko) Version/26.0 Safari/605.1.15';

  static const _autoBypassKey = 'local.cloudflare.autoBypass';
  static const _mutedHostsKey = 'local.cloudflare.mutedHosts';
  static const _userAgentKey = 'local.network.userAgent';
  static const _customUserAgentKey = 'local.network.customUserAgent';

  /// When on, extensions get a hidden browser to pass Cloudflare checks, and
  /// Kuchie asks the reader to verify when a check needs a tap.
  final autoBypass = ValueNotifier<bool>(true);
  final userAgent = ValueNotifier<LocalUserAgent>(LocalUserAgent.device);
  final customUserAgent = ValueNotifier<String>('');

  /// Sites whose verification prompt the reader turned off.
  final mutedHosts = ValueNotifier<Set<String>>(const {});

  Future<void>? _loading;
  Future<String?>? _deviceUserAgent;

  Future<void> load() => _loading ??= () async {
    final prefs = await SharedPreferences.getInstance();
    autoBypass.value = prefs.getBool(_autoBypassKey) ?? true;
    userAgent.value = LocalUserAgent.values.firstWhere(
      (mode) => mode.name == prefs.getString(_userAgentKey),
      orElse: () => LocalUserAgent.device,
    );
    customUserAgent.value = prefs.getString(_customUserAgentKey) ?? '';
    mutedHosts.value = Set.unmodifiable(
      prefs.getStringList(_mutedHostsKey) ?? const <String>[],
    );
  }();

  Future<void> setAutoBypass(bool value) async {
    await load();
    autoBypass.value = value;
    await (await SharedPreferences.getInstance()).setBool(
      _autoBypassKey,
      value,
    );
  }

  Future<void> setUserAgent(LocalUserAgent mode, {String? custom}) async {
    await load();
    final prefs = await SharedPreferences.getInstance();
    if (custom != null) {
      // A header value: printable ASCII only, so it cannot break the request.
      customUserAgent.value = custom
          .replaceAll(RegExp(r'[^\x20-\x7E]'), '')
          .trim();
      await prefs.setString(_customUserAgentKey, customUserAgent.value);
    }
    userAgent.value = mode;
    await prefs.setString(_userAgentKey, mode.name);
  }

  bool isMuted(String host) => mutedHosts.value.contains(_hostKey(host));

  Future<void> mute(String host) async {
    await load();
    mutedHosts.value = Set.unmodifiable({...mutedHosts.value, _hostKey(host)});
    await _saveMutes();
  }

  Future<void> clearMutes() async {
    await load();
    mutedHosts.value = const {};
    await _saveMutes();
  }

  Future<void> _saveMutes() async => (await SharedPreferences.getInstance())
      .setStringList(_mutedHostsKey, mutedHosts.value.toList()..sort());

  static String _hostKey(String host) {
    final lower = host.toLowerCase();
    return lower.startsWith('www.') ? lower.substring(4) : lower;
  }

  /// The user agent extensions send, resolved for [userAgent].
  Future<String> effectiveUserAgent() async {
    await load();
    return switch (userAgent.value) {
      LocalUserAgent.desktopChrome => desktopChromeUserAgent,
      LocalUserAgent.desktopFirefox => desktopFirefoxUserAgent,
      LocalUserAgent.device => await deviceUserAgent() ?? mobileSafariUserAgent,
      LocalUserAgent.desktopSafari => desktopSafariUserAgent,
      LocalUserAgent.custom =>
        customUserAgent.value.isEmpty
            ? desktopChromeUserAgent
            : customUserAgent.value,
    };
  }

  /// This iPhone's WebView user agent, or null when it cannot be read.
  Future<String?> deviceUserAgent() => _deviceUserAgent ??= () async {
    try {
      final value = await InAppWebViewController.getDefaultUserAgent();
      return value.isEmpty ? null : value;
    } catch (_) {
      return null;
    }
  }();

  /// The WebView's cookies for [site] as one `Cookie` header value, or null.
  Future<String?> siteCookies(Uri site) async {
    if (!Platform.isIOS) return null;
    try {
      final cookies = await CookieManager.instance().getCookies(
        url: WebUri(site.origin),
      );
      final pairs = [
        for (final cookie in cookies)
          if (_isHeaderSafe(cookie.name) && _isHeaderSafe('${cookie.value}'))
            '${cookie.name}=${cookie.value}',
      ];
      return pairs.isEmpty ? null : pairs.join('; ');
    } catch (_) {
      return null;
    }
  }

  static bool _isHeaderSafe(String value) =>
      value.isNotEmpty &&
      !value.contains(RegExp(r'[\x00-\x1F\x7F;]')) &&
      value.length <= 4096;

  /// Removes every cookie and site data the WebViews keep.
  Future<void> clearWebViewCookies() async {
    await CookieManager.instance().deleteAllCookies();
    try {
      await WebStorageManager.instance().deleteAllData();
    } catch (_) {
      // Cookies are what matters for sign-ins and Cloudflare.
    }
  }

  /// Headers for every runtime request: the user agent, and, while automatic
  /// bypass is on, the address of the hidden browser.
  Future<Map<String, String>> runtimeHeaders() async {
    await load();
    return {
      'User-Agent': await effectiveUserAgent(),
      if (autoBypass.value && Platform.isIOS)
        ...await RemoteWebViewServer.instance.headers(),
    };
  }
}
