// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Flutter
import UIKit

final class AppleGlassSegmentsFactory: NSObject, FlutterPlatformViewFactory {
  private static let channelName = "kuchie/apple_glass_segments"
  private static let viewType = channelName + "/control"
  private let messenger: FlutterBinaryMessenger

  private init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let messenger = registrar.messenger()
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
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
      registrar.register(AppleGlassSegmentsFactory(messenger: messenger), withId: viewType)
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
    let configuration = args as? [String: Any] ?? [:]
    let channel = FlutterMethodChannel(
      name: "\(Self.viewType)/\(viewId)", binaryMessenger: messenger
    )
    if #available(iOS 26.0, *) {
      return AppleGlassSegmentTrack(frame: frame, channel: channel, configuration: configuration)
    }
    preconditionFailure("AppleGlassSegmentTrack requires iOS 26")
  }
}

@available(iOS 26.0, *)
private final class AppleGlassSegmentTrack: NSObject, FlutterPlatformView {
  private let surface: UIVisualEffectView
  private let segments: SegmentScrollView
  private let channel: FlutterMethodChannel

  init(frame: CGRect, channel: FlutterMethodChannel, configuration: [String: Any]) {
    let glass = UIGlassEffect(style: .regular)
    glass.isInteractive = true
    surface = UIVisualEffectView(effect: glass)
    segments = SegmentScrollView(scrollable: configuration["scrollable"] as? Bool == true)
    self.channel = channel
    super.init()

    surface.frame = frame
    surface.cornerConfiguration = .capsule()
    segments.translatesAutoresizingMaskIntoConstraints = false
    surface.contentView.addSubview(segments)
    NSLayoutConstraint.activate([
      segments.leadingAnchor.constraint(equalTo: surface.contentView.leadingAnchor),
      segments.trailingAnchor.constraint(equalTo: surface.contentView.trailingAnchor),
      segments.topAnchor.constraint(equalTo: surface.contentView.topAnchor),
      segments.bottomAnchor.constraint(equalTo: surface.contentView.bottomAnchor),
    ])
    segments.onSelect = { [weak self] index in
      self?.channel.invokeMethod("select", arguments: index)
    }
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

  func view() -> UIView { surface }

  private func update(_ configuration: [String: Any]) {
    guard let labels = configuration["labels"] as? [String],
      let selectedIndex = configuration["selectedIndex"] as? Int,
      labels.indices.contains(selectedIndex)
    else { return }
    surface.overrideUserInterfaceStyle = configuration["dark"] as? Bool == true ? .dark : .light
    segments.update(
      labels: labels,
      symbols: configuration["symbols"] as? [String] ?? [],
      actionIndices: Set(configuration["actionIndices"] as? [Int] ?? []),
      selectedIndex: selectedIndex,
      rtl: configuration["rtl"] as? Bool == true,
      reduceMotion: configuration["reduceMotion"] as? Bool == true
    )
  }
}

private final class SegmentScrollView: UIScrollView {
  private let scrollable: Bool
  private let selection = UIView()
  private let font = UIFont.systemFont(ofSize: 15, weight: .semibold)
  private var buttons: [UIButton] = []
  private var labels: [String] = []
  private var symbols: [String] = []
  private var actionIndices = Set<Int>()
  private var rtl = false
  private var reduceMotion = false
  private var selectedIndex: Int?
  private var viewportSize = CGSize.zero
  private var needsSegmentLayout = true
  private var revealAfterLayout = false
  var onSelect: ((Int) -> Void)?

  init(scrollable: Bool) {
    self.scrollable = scrollable
    super.init(frame: .zero)
    isScrollEnabled = scrollable
    showsHorizontalScrollIndicator = false
    showsVerticalScrollIndicator = false
    contentInsetAdjustmentBehavior = .never
    semanticContentAttribute = .forceLeftToRight
    delaysContentTouches = false
    clipsToBounds = true
    layer.cornerCurve = .continuous
    selection.backgroundColor = UIColor { traits in
      if traits.userInterfaceStyle == .dark {
        return UIColor.white.withAlphaComponent(
          traits.accessibilityContrast == .high ? 0.34 : 0.15
        )
      }
      return UIColor.black.withAlphaComponent(
        traits.accessibilityContrast == .high ? 0.25 : 0.09
      )
    }
    selection.isUserInteractionEnabled = false
    selection.isAccessibilityElement = false
    selection.layer.cornerCurve = .continuous
    addSubview(selection)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func touchesShouldCancel(in view: UIView) -> Bool {
    true
  }

  func update(
    labels: [String], symbols: [String], actionIndices: Set<Int>,
    selectedIndex: Int, rtl: Bool, reduceMotion: Bool
  ) {
    self.reduceMotion = reduceMotion
    self.actionIndices = actionIndices
    if self.labels != labels || self.symbols != symbols {
      self.labels = labels
      self.symbols = symbols
      if buttons.count != labels.count {
        buttons.forEach { $0.removeFromSuperview() }
        buttons = labels.indices.map { index in
          let button = UIButton(type: .system)
          button.titleLabel?.font = font
          button.titleLabel?.lineBreakMode = .byTruncatingTail
          button.setTitleColor(.label, for: .normal)
          button.setTitleColor(.secondaryLabel, for: .highlighted)
          button.tag = index
          button.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
          addSubview(button)
          return button
        }
        accessibilityElements = buttons
        self.selectedIndex = nil
      }
      let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
      for (index, button) in buttons.enumerated() {
        let icon = symbols.indices.contains(index) && !symbols[index].isEmpty
          ? UIImage(systemName: symbols[index], withConfiguration: symbolConfiguration) : nil
        var style = UIButton.Configuration.plain()
        style.image = icon
        style.imagePlacement = .leading
        style.imagePadding = 5
        style.titleLineBreakMode = .byTruncatingTail
        style.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8)
        style.baseForegroundColor = .label
        var title = AttributedString(labels[index])
        title.font = font
        style.attributedTitle = title
        button.configuration = style
        button.accessibilityLabel = labels[index]
      }
      needsSegmentLayout = true
    }
    if self.rtl != rtl {
      self.rtl = rtl
      needsSegmentLayout = true
      revealAfterLayout = true
    }
    select(selectedIndex)
    if needsSegmentLayout { setNeedsLayout() }
  }

  @objc private func tapped(_ button: UIButton) {
    if !actionIndices.contains(button.tag) {
      select(button.tag)
    }
    onSelect?(button.tag)
  }

  private func select(_ index: Int) {
    guard selectedIndex != index else { return }
    let animate = selectedIndex != nil && !reduceMotion
    selectedIndex = index
    for (buttonIndex, button) in buttons.enumerated() {
      if buttonIndex == index {
        button.accessibilityTraits.insert(.selected)
      } else {
        button.accessibilityTraits.remove(.selected)
      }
    }
    if needsSegmentLayout || viewportSize != bounds.size || bounds.isEmpty {
      revealAfterLayout = true
      setNeedsLayout()
    } else {
      showSelection(animated: animate, reveal: true)
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    guard !bounds.isEmpty, !buttons.isEmpty,
      needsSegmentLayout || viewportSize != bounds.size
    else { return }
    needsSegmentLayout = false
    let resized = viewportSize != bounds.size
    viewportSize = bounds.size
    layer.cornerRadius = min(bounds.width, bounds.height) / 2

    let values = scrollable
      ? buttons.map { max(64, ceil($0.intrinsicContentSize.width) + 12) }
      : Array(repeating: bounds.width / CGFloat(buttons.count), count: buttons.count)
    let measuredWidth = values.reduce(0, +)
    let extraWidth = max(0, bounds.width - measuredWidth) / CGFloat(values.count)
    let trackWidth = max(measuredWidth, bounds.width)
    var offset: CGFloat = 0
    for (index, width) in values.enumerated() {
      let segmentWidth = width + extraWidth
      let x = rtl ? trackWidth - offset - segmentWidth : offset
      buttons[index].frame = CGRect(x: x, y: 0, width: segmentWidth, height: bounds.height)
      offset += segmentWidth
    }
    if contentSize.width != trackWidth || contentSize.height != bounds.height {
      contentSize = CGSize(width: trackWidth, height: bounds.height)
    }
    showSelection(animated: false, reveal: revealAfterLayout || resized)
    revealAfterLayout = false
  }

  private func showSelection(animated: Bool, reveal: Bool) {
    guard let selectedIndex, buttons.indices.contains(selectedIndex) else { return }
    let segment = buttons[selectedIndex].frame
    let thumb = segment.insetBy(dx: 4, dy: 4)
    selection.layer.cornerRadius = max(0, thumb.height / 2)
    if animated {
      UIView.animate(
        withDuration: 0.25,
        delay: 0,
        options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut]
      ) { self.selection.frame = thumb }
    } else {
      selection.frame = thumb
    }
    guard scrollable, reveal else { return }
    if segment.width > bounds.width {
      let x = rtl ? segment.maxX - bounds.width : segment.minX
      setContentOffset(CGPoint(x: x, y: 0), animated: animated)
    } else {
      scrollRectToVisible(segment, animated: animated)
    }
  }
}
