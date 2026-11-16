// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Flutter
import UIKit

@available(iOS 26.0, *)
final class AppleGlassSearchFactory: NSObject, FlutterPlatformViewFactory {
  private static let viewType = "kuchie/apple_glass/search"
  private let messenger: FlutterBinaryMessenger

  private init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    registrar.register(AppleGlassSearchFactory(messenger: registrar.messenger()), withId: viewType)
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?
  ) -> FlutterPlatformView {
    AppleGlassSearchView(
      frame: frame,
      channel: FlutterMethodChannel(name: "\(Self.viewType)/\(viewId)", binaryMessenger: messenger),
      arguments: args as? [String: Any] ?? [:]
    )
  }
}

@available(iOS 26.0, *)
private final class AppleGlassSearchView: NSObject, FlutterPlatformView, UITextFieldDelegate {
  private let channel: FlutterMethodChannel
  private let host: SearchHost
  private let field = UISearchTextField()
  private let prompt = UIButton(configuration: .glass())
  private var lastInput: Input?
  private var applyingUpdate = false

  private struct Input: Equatable {
    var text: String
    var start: Int
    var end: Int
    var composing: Bool
  }

  init(frame: CGRect, channel: FlutterMethodChannel, arguments: [String: Any]) {
    self.channel = channel
    self.host = SearchHost(frame: frame)
    super.init()

    let glass = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
    glass.cornerConfiguration = .capsule()
    field.background = UIImage()
    field.backgroundColor = .clear
    field.borderStyle = .none
    field.returnKeyType = .search
    field.adjustsFontForContentSizeCategory = true
    field.font = .preferredFont(forTextStyle: .body)
    field.clearButtonMode = .always
    field.delegate = self
    field.addTarget(self, action: #selector(emitInput), for: .editingChanged)
    prompt.addTarget(self, action: #selector(openPrompt), for: .touchUpInside)

    func install(_ view: UIView, in parent: UIView, horizontal: CGFloat = 0) {
      view.translatesAutoresizingMaskIntoConstraints = false
      parent.addSubview(view)
      NSLayoutConstraint.activate([
        view.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: horizontal),
        view.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -horizontal),
        view.topAnchor.constraint(equalTo: parent.topAnchor),
        view.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
      ])
    }
    install(glass, in: host)
    install(field, in: glass.contentView, horizontal: 12)
    install(prompt, in: host)
    let entry = arguments["entry"] as? Bool == true
    glass.isHidden = entry
    prompt.isHidden = !entry
    if !entry {
      host.whenAttached = { [weak self] in self?.applyFocus() }
    }
    update(arguments)
    requestedFocus = !entry && arguments["autofocus"] as? Bool == true

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(nil); return }
      switch call.method {
      case "update":
        if let config = call.arguments as? [String: Any] { self.update(config) }
      case "focus":
        self.requestedFocus = call.arguments as? Bool == true
        if self.requestedFocus { self.applyFocus() } else { self.field.resignFirstResponder() }
      default:
        result(FlutterMethodNotImplemented)
        return
      }
      result(nil)
    }
  }

  private var requestedFocus = false

  deinit { channel.setMethodCallHandler(nil) }

  func view() -> UIView { host }

  private func applyFocus() {
    guard requestedFocus, host.window != nil else { return }
    DispatchQueue.main.async { [weak self] in
      guard let self, self.requestedFocus, self.host.window != nil else { return }
      if self.field.becomeFirstResponder() { self.requestedFocus = false }
    }
  }

  private func update(_ config: [String: Any]) {
    applyingUpdate = true
    defer { applyingUpdate = false }
    host.overrideUserInterfaceStyle = config["dark"] as? Bool == true ? .dark : .light
    // Caret and selection follow the app theme's accent.
    host.tintColor = UIColor.kuchieARGB(config["tint"])
    host.semanticContentAttribute = config["rtl"] as? Bool == true
      ? .forceRightToLeft : .forceLeftToRight
    let placeholder = config["placeholder"] as? String ?? ""
    let label = config["label"] as? String ?? placeholder
    keepFocusOnSubmit = config["keepFocusOnSubmit"] as? Bool == true
    field.placeholder = placeholder
    field.accessibilityLabel = label
    let text = config["text"] as? String ?? ""
    if !prompt.isHidden {
      let displayTitle = text.isEmpty ? placeholder : text
      if prompt.configuration?.title != displayTitle {
        var configuration = UIButton.Configuration.glass()
        configuration.title = displayTitle
        configuration.titleLineBreakMode = .byTruncatingTail
        configuration.image = UIImage(systemName: "magnifyingglass")
        configuration.imagePadding = 8
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14)
        if text.isEmpty { configuration.baseForegroundColor = .secondaryLabel }
        prompt.configuration = configuration
        prompt.contentHorizontalAlignment = .leading
      }
      prompt.accessibilityLabel = label
      prompt.accessibilityValue = text.isEmpty ? nil : text
      return
    }
    guard let start = config["start"] as? Int, let end = config["end"] as? Int else { return }
    if field.text != text {
      lastInput = nil
      field.text = text
    }
    if field.markedTextRange == nil,
       start >= 0,
       let from = field.position(from: field.beginningOfDocument, offset: start),
       let to = field.position(from: field.beginningOfDocument, offset: end),
       let range = field.textRange(from: from, to: to),
       field.selectedTextRange != range {
      field.selectedTextRange = range
    }
  }

  @objc private func openPrompt() { channel.invokeMethod("open", arguments: nil) }

  @objc private func emitInput() {
    guard !applyingUpdate else { return }
    let text = field.text ?? ""
    let selection = field.selectedTextRange
    let start = selection.map { field.offset(from: field.beginningOfDocument, to: $0.start) } ?? text.utf16.count
    let end = selection.map { field.offset(from: field.beginningOfDocument, to: $0.end) } ?? start
    let input = Input(text: text, start: start, end: end, composing: field.markedTextRange != nil)
    guard input != lastInput else { return }
    lastInput = input
    let marked = field.markedTextRange
    channel.invokeMethod("input", arguments: [
      "text": text, "start": start, "end": end,
      "markedStart": marked.map { field.offset(from: field.beginningOfDocument, to: $0.start) } ?? -1,
      "markedEnd": marked.map { field.offset(from: field.beginningOfDocument, to: $0.end) } ?? -1,
    ])
  }

  func textFieldDidChangeSelection(_ textField: UITextField) { emitInput() }
  func textFieldDidBeginEditing(_ textField: UITextField) {
    channel.invokeMethod("focusChanged", arguments: true)
  }
  func textFieldDidEndEditing(_ textField: UITextField) {
    channel.invokeMethod("focusChanged", arguments: false)
  }
  func textFieldShouldReturn(_ textField: UITextField) -> Bool {
    emitInput()
    channel.invokeMethod("submit", arguments: field.text ?? "")
    if !keepFocusOnSubmit { requestedFocus = false; field.resignFirstResponder() }
    return false
  }
  private var keepFocusOnSubmit = false
}

private final class SearchHost: UIView {
  var whenAttached: (() -> Void)?

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window != nil { whenAttached?() }
  }
}
