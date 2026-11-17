import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../../../../utils/logger/logger.dart';
import 'remote_webview_host.dart';

/// Lets extensions in the runtime use real WebViews on this device.
///
/// Mihon extensions create `android.webkit.WebView`s, most often to pass a
/// Cloudflare challenge. The runtime opens a WebSocket to this loopback
/// server and each of those WebViews runs here as a headless WKWebView
/// ([RemoteWebViewHost]). The port and a per-launch token reach the runtime
/// as headers on every extension call; the token, and refusing any request
/// with an `Origin`, keep web pages and other local processes out.
class RemoteWebViewServer {
  RemoteWebViewServer._();

  static final instance = RemoteWebViewServer._();

  static const portHeader = 'x-mangayomi-webview-port';
  static const tokenHeader = RemoteWebViewHost.tokenHeader;

  final String _token = _randomToken();
  Future<HttpServer?>? _server;

  /// Headers that offer this device's WebViews to the runtime, or none when
  /// the server cannot start.
  Future<Map<String, String>> headers() async {
    final server = await (_server ??= _start());
    if (server == null) return const {};
    return {portHeader: '${server.port}', tokenHeader: _token};
  }

  Future<HttpServer?> _start() async {
    try {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) {
        if (request.uri.path == RemoteWebViewHost.path) {
          unawaited(RemoteWebViewHost.accept(request, token: _token));
        } else {
          request.response.statusCode = HttpStatus.notFound;
          unawaited(request.response.close());
        }
      }, onError: (Object error) => logger.w('WebView server error: $error'));
      return server;
    } catch (error) {
      logger.w('Could not start the extension WebView server: $error');
      // Try again on the next extension call.
      _server = null;
      return null;
    }
  }

  static String _randomToken() {
    final random = Random.secure();
    return base64UrlEncode(List<int>.generate(32, (_) => random.nextInt(256)));
  }
}
