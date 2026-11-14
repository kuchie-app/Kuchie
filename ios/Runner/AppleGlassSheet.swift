// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at http://mozilla.org/MPL/2.0/.

import Flutter
import UIKit

@available(iOS 26.0, *)
final class AppleGlassSheetFactory: NSObject, FlutterPlatformViewFactory {
  static func register(with registrar: FlutterPluginRegistrar) {
    registrar.register(AppleGlassSheetFactory(), withId: "kuchie/apple_liquid_glass/sheet")
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?
  ) -> FlutterPlatformView {
    let configuration = args as? [String: Any]
    return AppleGlassSheet(frame: frame, dark: configuration?["dark"] as? Bool == true)
  }
}

@available(iOS 26.0, *)
private final class AppleGlassSheet: NSObject, FlutterPlatformView {
  private let surface = UIVisualEffectView(effect: UIGlassEffect(style: .regular))

  init(frame: CGRect, dark: Bool) {
    super.init()
    surface.frame = frame
    surface.cornerConfiguration = .uniformCorners(radius: .fixed(32))
    surface.overrideUserInterfaceStyle = dark ? .dark : .light
    surface.isUserInteractionEnabled = false
    surface.accessibilityElementsHidden = true
  }

  func view() -> UIView { surface }
}
