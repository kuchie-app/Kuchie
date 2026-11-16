// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Flutter
import UIKit

extension UIColor {
  /// Decodes a Flutter `Color.toARGB32()` value; nil keeps the system tint.
  static func kuchieARGB(_ value: Any?) -> UIColor? {
    guard let number = value as? NSNumber else { return nil }
    let argb = number.uint32Value
    return UIColor(
      red: CGFloat((argb >> 16) & 255) / 255,
      green: CGFloat((argb >> 8) & 255) / 255,
      blue: CGFloat(argb & 255) / 255,
      alpha: CGFloat((argb >> 24) & 255) / 255
    )
  }
}

final class AppleLiquidGlassTabBarFactory: NSObject, FlutterPlatformViewFactory {
  private static let channelName = "kuchie/apple_liquid_glass"
  private static let viewType = channelName + "/tab_bar"
  private let messenger: FlutterBinaryMessenger

  private init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let messenger = registrar.messenger()
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "isSupported":
        if #available(iOS 26.0, *) {
          result(true)
        } else {
          result(false)
        }
      case "physicalMemory":
        // Dart decides whether the glass effects suit this device.
        result(NSNumber(value: ProcessInfo.processInfo.physicalMemory))
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    if #available(iOS 26.0, *) {
      // The Dart side always claims these touches, so waiting on Flutter's
      // gesture arena only cancels quick taps whenever the UI thread is busy
      // (launch, building a heavy tab), leaving the tab unselected.
      registrar.register(
        AppleLiquidGlassTabBarFactory(messenger: messenger),
        withId: viewType,
        gestureRecognizersBlockingPolicy:
          FlutterPlatformViewGestureRecognizersBlockingPolicyDoNotBlockGesture
      )
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
    AppleLiquidGlassTabBar(
      frame: frame,
      channel: FlutterMethodChannel(
        name: "\(Self.viewType)/\(viewId)", binaryMessenger: messenger
      ),
      arguments: args
    )
  }
}

private final class AppleLiquidGlassTabBar: NSObject, FlutterPlatformView, UITabBarDelegate {
  private let container: TabBarContainer
  private let channel: FlutterMethodChannel
  private var symbols: [String] = []

  init(frame: CGRect, channel: FlutterMethodChannel, arguments: Any?) {
    container = TabBarContainer(frame: frame)
    self.channel = channel
    super.init()
    container.tabBar.delegate = self
    if let configuration = arguments as? [String: Any] {
      update(configuration)
    }
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "update" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let configuration = call.arguments as? [String: Any] else {
        result(FlutterError(
          code: "invalid_configuration", message: "Expected a tab bar configuration", details: nil
        ))
        return
      }
      self?.update(configuration)
      result(nil)
    }
  }

  deinit {
    channel.setMethodCallHandler(nil)
  }

  func view() -> UIView {
    container
  }

  func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
    channel.invokeMethod("select", arguments: item.tag)
  }

  private func update(_ configuration: [String: Any]) {
    guard let tabs = configuration["tabs"] as? [[String: Any]],
      let selectedIndex = configuration["selectedIndex"] as? Int,
      tabs.indices.contains(selectedIndex)
    else { return }

    let tabBar = container.tabBar
    tabBar.overrideUserInterfaceStyle = configuration["dark"] as? Bool == true ? .dark : .light
    // The selected tab follows the app theme's accent instead of system blue.
    tabBar.tintColor = UIColor.kuchieARGB(configuration["tint"])
    tabBar.semanticContentAttribute =
      configuration["rtl"] as? Bool == true ? .forceRightToLeft : .forceLeftToRight

    let nextSymbols = tabs.map { $0["symbol"] as? String ?? "" }
    if symbols != nextSymbols {
      symbols = nextSymbols
      tabBar.setItems(
        tabs.indices.map { index in
          UITabBarItem(
            title: tabs[index]["title"] as? String,
            image: UIImage(systemName: nextSymbols[index]),
            tag: index
          )
        },
        animated: false
      )
    }
    guard let items = tabBar.items else { return }
    for (item, tab) in zip(items, tabs) {
      let title = tab["title"] as? String
      let badge = tab["badge"] as? String
      if item.title != title { item.title = title }
      if item.badgeValue != badge { item.badgeValue = badge }
    }
    guard tabBar.selectedItem !== items[selectedIndex] else { return }
    if configuration["reduceMotion"] as? Bool == true {
      UIView.performWithoutAnimation {
        tabBar.selectedItem = items[selectedIndex]
        tabBar.layoutIfNeeded()
      }
    } else {
      tabBar.selectedItem = items[selectedIndex]
    }
  }
}

private final class TabBarContainer: UIView {
  let tabBar = UITabBar(frame: .zero)

  override init(frame: CGRect) {
    super.init(frame: frame)
    isOpaque = false
    addSubview(tabBar)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    // Anchor the first measurement at the bottom so UIKit sees the window inset.
    if tabBar.frame.isEmpty {
      tabBar.frame = bounds
    }
    let fittedHeight = tabBar.sizeThatFits(
      CGSize(width: bounds.width, height: .greatestFiniteMagnitude)
    ).height
    let height = fittedHeight > 0 ? min(fittedHeight, bounds.height) : bounds.height
    tabBar.frame = CGRect(x: 0, y: bounds.height - height, width: bounds.width, height: height)
  }

  override func safeAreaInsetsDidChange() {
    super.safeAreaInsetsDidChange()
    setNeedsLayout()
  }
}
