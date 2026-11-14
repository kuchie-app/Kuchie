// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at http://mozilla.org/MPL/2.0/.

import Flutter
import UIKit
import WebKit

final class InAppWebViewFactory: NSObject, FlutterPlatformViewFactory {
  private static let viewType = "kuchie/in_app_web_view"
  private let messenger: FlutterBinaryMessenger

  private init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    registrar.register(InAppWebViewFactory(messenger: registrar.messenger()), withId: viewType)
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?
  ) -> FlutterPlatformView {
    let parameters = args as? [String: Any]
    return InAppWebView(
      frame: frame,
      channel: FlutterMethodChannel(name: "\(Self.viewType)/\(viewId)", binaryMessenger: messenger),
      initialURL: (parameters?["url"] as? String).flatMap { URL(string: $0) },
      bottomInset: (parameters?["bottomInset"] as? NSNumber)?.doubleValue ?? 0
    )
  }
}

private final class InAppWebView: NSObject, FlutterPlatformView, WKNavigationDelegate, WKUIDelegate {
  private let webView: WKWebView
  private let channel: FlutterMethodChannel
  private var observations: [NSKeyValueObservation] = []
  private var lastAttemptedURL: URL?
  private var failed = false

  init(frame: CGRect, channel: FlutterMethodChannel, initialURL: URL?, bottomInset: Double) {
    let configuration = WKWebViewConfiguration()
    configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
    webView = WKWebView(frame: frame, configuration: configuration)
    self.channel = channel
    super.init()

    webView.isOpaque = false
    webView.backgroundColor = .clear
    webView.scrollView.contentInsetAdjustmentBehavior = .never
    webView.navigationDelegate = self
    webView.uiDelegate = self
    setBottomInset(bottomInset)
    observations = [
      webView.observe(\.estimatedProgress, options: [.new]) { [weak self] _, _ in self?.publishState() },
      webView.observe(\.isLoading, options: [.new]) { [weak self] _, _ in self?.publishState() },
      webView.observe(\.canGoBack, options: [.new]) { [weak self] _, _ in self?.publishState() },
      webView.observe(\.canGoForward, options: [.new]) { [weak self] _, _ in self?.publishState() },
      webView.observe(\.title, options: [.new]) { [weak self] _, _ in self?.publishState() },
      webView.observe(\.url, options: [.new]) { [weak self] _, _ in self?.publishState() },
    ]
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(nil); return }
      switch call.method {
      case "state": result(self.state())
      case "back": self.webView.goBack(); result(nil)
      case "forward": self.webView.goForward(); result(nil)
      case "setBottomInset":
        self.setBottomInset((call.arguments as? NSNumber)?.doubleValue ?? 0)
        result(nil)
      case "reload":
        if self.failed, let url = self.lastAttemptedURL {
          self.webView.load(URLRequest(url: url))
        } else {
          self.webView.reload()
        }
        result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
    if let initialURL, Self.isWebURL(initialURL) {
      lastAttemptedURL = initialURL
      webView.load(URLRequest(url: initialURL))
    } else {
      failed = true
    }
  }

  deinit {
    observations.forEach { $0.invalidate() }
    channel.setMethodCallHandler(nil)
  }

  func view() -> UIView { webView }

  private func setBottomInset(_ bottomInset: Double) {
    if #available(iOS 26.0, *) {
      webView.obscuredContentInsets = UIEdgeInsets(top: 0, left: 0, bottom: max(0, bottomInset), right: 0)
    }
  }

  private static func isWebURL(_ url: URL) -> Bool {
    guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
      return false
    }
    return url.host?.isEmpty == false && url.user == nil && url.password == nil
  }

  private func state() -> [String: Any] {
    [
      "url": (failed ? lastAttemptedURL : webView.url)?.absoluteString ?? "",
      "title": webView.title ?? "",
      "canGoBack": webView.canGoBack,
      "canGoForward": webView.canGoForward,
      "loading": webView.isLoading,
      "progress": webView.estimatedProgress,
      "failed": failed,
    ]
  }

  private func publishState() {
    channel.invokeMethod("stateChanged", arguments: state())
  }

  func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
               decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    guard let url = action.request.url else { decisionHandler(.cancel); return }
    if action.targetFrame?.isMainFrame == false && url.absoluteString == "about:blank" {
      decisionHandler(.allow)
      return
    }
    guard Self.isWebURL(url) else { decisionHandler(.cancel); return }
    if action.targetFrame?.isMainFrame == true { lastAttemptedURL = url }
    decisionHandler(.allow)
  }

  func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
               for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
    if action.targetFrame == nil, action.navigationType == .linkActivated,
       let url = action.request.url, Self.isWebURL(url) {
      webView.load(action.request)
    }
    return nil
  }

  func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
    failed = false
    publishState()
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    publishState()
  }

  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
               withError error: Error) {
    navigationFailed(error)
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    navigationFailed(error)
  }

  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    failed = true
    publishState()
  }

  private func navigationFailed(_ error: Error) {
    let error = error as NSError
    guard error.domain != NSURLErrorDomain || error.code != NSURLErrorCancelled else { return }
    failed = true
    publishState()
  }
}
