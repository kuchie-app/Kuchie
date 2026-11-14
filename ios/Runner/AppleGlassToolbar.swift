// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Flutter
import UIKit

final class AppleGlassToolbarFactory: NSObject, FlutterPlatformViewFactory {
  private static let viewType = "kuchie/apple_liquid_glass/toolbar"
  private let messenger: FlutterBinaryMessenger

  private init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let messenger = registrar.messenger()
    let channel = FlutterMethodChannel(name: viewType, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "isSupported" else {
        result(FlutterMethodNotImplemented)
        return
      }
      if #available(iOS 26.0, *) {
        result(true)
      } else {
        result(false)
      }
    }
    if #available(iOS 26.0, *) {
      registrar.register(AppleGlassToolbarFactory(messenger: messenger), withId: viewType)
    }
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    if #available(iOS 26.0, *) {
      return AppleGlassToolbar(
        frame: frame,
        channel: FlutterMethodChannel(
          name: "\(Self.viewType)/\(viewId)", binaryMessenger: messenger
        ),
        configuration: args as? [String: Any] ?? [:]
      )
    }
    preconditionFailure("AppleGlassToolbar requires iOS 26")
  }
}

@available(iOS 26.0, *)
private final class AppleGlassToolbar: NSObject, FlutterPlatformView {
  private let container: UIView
  private let surface = UIVisualEffectView()
  private let chrome = UIView()
  private let stack = UIStackView()
  private let channel: FlutterMethodChannel
  private var actionIDs: [String] = []
  private var widths: [NSLayoutConstraint] = []
  private var menuDefinitions: [String: NSArray] = [:]

  init(frame: CGRect, channel: FlutterMethodChannel, configuration: [String: Any]) {
    container = UIView(frame: frame)
    self.channel = channel
    super.init()

    container.isOpaque = false
    surface.cornerConfiguration = .capsule()
    surface.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(surface)
    chrome.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(chrome)
    stack.alignment = .center
    stack.spacing = 4
    stack.translatesAutoresizingMaskIntoConstraints = false
    chrome.addSubview(stack)
    NSLayoutConstraint.activate([
      surface.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 2),
      surface.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -2),
      surface.topAnchor.constraint(equalTo: container.topAnchor, constant: 2),
      surface.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -2),
      chrome.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
      chrome.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
      chrome.topAnchor.constraint(equalTo: surface.topAnchor),
      chrome.bottomAnchor.constraint(equalTo: surface.bottomAnchor),
      stack.leadingAnchor.constraint(equalTo: chrome.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: chrome.trailingAnchor),
      stack.centerYAnchor.constraint(equalTo: chrome.centerYAnchor),
    ])
    update(configuration)

    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "update" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let configuration = call.arguments as? [String: Any] else {
        result(FlutterError(code: "invalid_configuration", message: nil, details: nil))
        return
      }
      self?.update(configuration)
      result(nil)
    }
  }

  deinit {
    channel.setMethodCallHandler(nil)
  }

  func view() -> UIView { container }

  private func update(_ configuration: [String: Any]) {
    guard let actions = configuration["actions"] as? [[String: Any]] else { return }
    let ids = actions.compactMap { $0["id"] as? String }
    guard actions.count == ids.count else { return }
    let joined = configuration["joined"] as? Bool == true && actions.count > 1
    if joined && surface.effect == nil {
      surface.effect = UIGlassEffect(style: .regular)
    } else if !joined && surface.effect != nil {
      surface.effect = nil
    }

    container.overrideUserInterfaceStyle =
      configuration["dark"] as? Bool == true ? .dark : .light
    stack.semanticContentAttribute =
      configuration["rtl"] as? Bool == true ? .forceRightToLeft : .forceLeftToRight

    if ids != actionIDs {
      for view in stack.arrangedSubviews { view.removeFromSuperview() }
      widths = []
      menuDefinitions = [:]
      for id in ids {
        let button = UIButton(
          configuration: .glass(),
          primaryAction: UIAction { [weak self] _ in
            self?.channel.invokeMethod("press", arguments: id)
          }
        )
        button.accessibilityIdentifier = "kuchie.toolbar.\(id)"
        stack.addArrangedSubview(button)
        let width = button.widthAnchor.constraint(equalToConstant: 44)
        // A Flutter transition can resize the host one frame before its configuration arrives.
        width.priority = .defaultHigh
        widths.append(width)
        NSLayoutConstraint.activate([
          width,
          button.heightAnchor.constraint(equalToConstant: 44),
        ])
      }
      actionIDs = ids
    }

    for (index, pair) in zip(stack.arrangedSubviews, actions).enumerated() {
      let (view, action) = pair
      guard let button = view as? UIButton, let symbol = action["symbol"] as? String else {
        continue
      }
      let width = (action["width"] as? NSNumber)?.doubleValue ?? 48
      widths[index].constant = max(44, width - 4)
      var style: UIButton.Configuration = joined ? .plain() : .glass()
      style.cornerStyle = .capsule
      style.image = UIImage(systemName: symbol)
      let title = action["title"] as? String
      style.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
        pointSize: title == nil ? 18 : 12, weight: .semibold
      )
      style.contentInsets = .zero
      if let title {
        style.title = title
        style.titleLineBreakMode = .byTruncatingTail
        style.imagePlacement = .trailing
        style.imagePadding = 8
        style.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)
      }
      if joined {
        style.baseForegroundColor = .label
      }
      if let color = action["color"] as? UInt32 {
        style.baseForegroundColor = UIColor(
          red: CGFloat((color >> 16) & 255) / 255,
          green: CGFloat((color >> 8) & 255) / 255,
          blue: CGFloat(color & 255) / 255,
          alpha: CGFloat((color >> 24) & 255) / 255
        )
      }
      if button.configuration != style { button.configuration = style }
      button.contentHorizontalAlignment =
        action["alignTitleLeading"] as? Bool == true ? .leading : .center
      button.isEnabled = action["enabled"] as? Bool == true
      button.accessibilityLabel = action["label"] as? String
      button.accessibilityValue = action["accessibilityValue"] as? String
      let id = ids[index]
      if let menu = action["menu"] as? [[String: Any]], !menu.isEmpty {
        let definition = menu as NSArray
        if menuDefinitions[id] != definition {
          button.menu = UIMenu(children: menu.compactMap { menuElement($0, actionID: id) })
          button.showsMenuAsPrimaryAction = true
          menuDefinitions[id] = definition
        }
      } else if menuDefinitions.removeValue(forKey: id) != nil {
        button.showsMenuAsPrimaryAction = false
        button.menu = nil
      }
    }
  }

  private func menuElement(_ item: [String: Any], actionID: String) -> UIMenuElement? {
    guard let id = item["id"] as? String, let title = item["title"] as? String else {
      return nil
    }
    let image = (item["symbol"] as? String).flatMap { UIImage(systemName: $0) }
    let destructive = item["destructive"] as? Bool == true
    if let definitions = item["children"] as? [[String: Any]], !definitions.isEmpty {
      return UIMenu(
        title: title,
        image: image,
        options: destructive ? .destructive : [],
        children: definitions.compactMap { menuElement($0, actionID: actionID) }
      )
    }
    var attributes: UIMenuElement.Attributes = destructive ? .destructive : []
    if item["enabled"] as? Bool != true { attributes.insert(.disabled) }
    return UIAction(
      title: title,
      image: image,
      attributes: attributes,
      state: item["selected"] as? Bool == true ? .on : .off
    ) { [weak self] _ in
      self?.channel.invokeMethod("menuSelect", arguments: ["action": actionID, "item": id])
    }
  }
}
