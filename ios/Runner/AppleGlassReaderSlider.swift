// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at http://mozilla.org/MPL/2.0/.

import Flutter
import UIKit

@available(iOS 26.0, *)
final class AppleGlassReaderSliderFactory: NSObject, FlutterPlatformViewFactory {
  private static let viewType = "kuchie/apple_liquid_glass/reader_slider"
  private let messenger: FlutterBinaryMessenger

  private init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    registrar.register(AppleGlassReaderSliderFactory(messenger: registrar.messenger()),
                       withId: viewType)
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?
  ) -> FlutterPlatformView {
    AppleGlassReaderSlider(
      frame: frame,
      channel: FlutterMethodChannel(name: "\(Self.viewType)/\(viewId)", binaryMessenger: messenger),
      configuration: args as? [String: Any] ?? [:]
    )
  }
}

@available(iOS 26.0, *)
private final class AppleGlassReaderSlider: NSObject, FlutterPlatformView, UIGestureRecognizerDelegate {
  private let surface: UIVisualEffectView
  private let slider = PageSlider()
  private let first = UILabel()
  private let last = UILabel()
  private let channel: FlutterMethodChannel
  private let numbers = NumberFormatter()
  private let numberFont = UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
  private var numberWidths: [NSLayoutConstraint] = []
  private var localeTag: String?
  private var pageLabelTemplate: String?
  private var totalText = ""
  private var count = 0
  private var reversed = false
  private var committedIndex = 0
  private var shownIndex = 0
  private var awaitingIndex: Int?
  private var dragTrack: (start: CGFloat, end: CGFloat, grab: CGFloat)?
  private var isPanning = false

  init(frame: CGRect, channel: FlutterMethodChannel, configuration: [String: Any]) {
    surface = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
    self.channel = channel
    super.init()

    surface.frame = frame
    surface.cornerConfiguration = .capsule()
    surface.overrideUserInterfaceStyle = .dark
    numbers.numberStyle = .none
    let labels = [first, last]
    for label in labels {
      label.font = numberFont
      label.textColor = .label
      label.adjustsFontSizeToFitWidth = true
      label.minimumScaleFactor = 0.6
      label.isAccessibilityElement = false
      label.setContentHuggingPriority(.required, for: .horizontal)
      label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
      let width = label.widthAnchor.constraint(equalToConstant: 0)
      width.priority = UILayoutPriority(751)
      width.isActive = true
      numberWidths.append(width)
    }
    first.textAlignment = .right
    last.textAlignment = .left
    slider.sliderStyle = .default
    slider.minimumValue = 0
    slider.isContinuous = true
    slider.accessibilityIdentifier = "kuchie.reader.page-slider"
    slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
    slider.addTarget(self, action: #selector(valueChanged), for: .valueChanged)
    slider.onFinishTracking = { [weak self] in
      guard let self, !self.isPanning else { return }
      self.finishTracking()
    }
    slider.onCancelTracking = { [weak self] in
      guard let self, !self.isPanning else { return }
      self.cancelTracking()
    }
    let tap = UITapGestureRecognizer(target: self, action: #selector(seekToTap(_:)))
    tap.cancelsTouchesInView = false
    slider.addGestureRecognizer(tap)
    let pan = PageSliderPan(target: self, action: #selector(dragThumb(_:)))
    pan.maximumNumberOfTouches = 1
    pan.delegate = self
    slider.addGestureRecognizer(pan)
    tap.require(toFail: pan)

    let row = UIStackView(arrangedSubviews: [first, slider, last])
    row.semanticContentAttribute = .forceLeftToRight
    row.alignment = .center
    row.spacing = 8
    row.translatesAutoresizingMaskIntoConstraints = false
    surface.contentView.addSubview(row)
    NSLayoutConstraint.activate([
      row.leadingAnchor.constraint(equalTo: surface.contentView.leadingAnchor, constant: 12),
      row.trailingAnchor.constraint(equalTo: surface.contentView.trailingAnchor, constant: -12),
      row.centerYAnchor.constraint(equalTo: surface.contentView.centerYAnchor),
      slider.heightAnchor.constraint(equalTo: surface.contentView.heightAnchor),
    ])
    update(configuration)

    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "update" else { result(FlutterMethodNotImplemented); return }
      guard let data = call.arguments as? [String: Any] else {
        result(FlutterError(code: "invalid_configuration", message: nil, details: nil))
        return
      }
      self?.update(data)
      result(nil)
    }
  }

  deinit { channel.setMethodCallHandler(nil) }

  func view() -> UIView { surface }

  private func update(_ data: [String: Any]) {
    slider.minimumTrackTintColor =
      UIColor.kuchieARGB(data["tint"]) ?? UIColor(red: 0.69, green: 0.78, blue: 1, alpha: 1)
    guard let index = data["index"] as? Int, let count = data["count"] as? Int,
          (0..<max(count, 0)).contains(index) else { return }
    let reversed = data["reversed"] as? Bool == true
    let countChanged = self.count != count
    let directionChanged = self.reversed != reversed
    let configurationChanged = countChanged || directionChanged
    self.count = count
    self.reversed = reversed
    committedIndex = index
    let locale = data["locale"] as? String
    let localeChanged = localeTag != locale
    if localeChanged, let locale {
      localeTag = locale
      numbers.locale = Locale(identifier: locale)
    }
    if countChanged || localeChanged {
      totalText = pageNumber(count)
      let width = (totalText as NSString).size(withAttributes: [.font: numberFont]).width
      // Reserve the widest page number once so crossing 9 / 10 doesn't resize the track.
      for constraint in numberWidths { constraint.constant = ceil(width) }
    }
    let pageLabel = data["pageLabel"] as? String ?? "%@"
    if pageLabelTemplate != pageLabel {
      pageLabelTemplate = pageLabel
      slider.accessibilityLabel = pageLabel.replacingOccurrences(of: "%@", with: "")
        .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
    }
    if directionChanged || countChanged {
      slider.semanticContentAttribute = reversed ? .forceRightToLeft : .forceLeftToRight
    }
    if countChanged {
      slider.maximumValue = Float(max(1, count - 1))
      slider.isEnabled = count > 1
    }
    if configurationChanged { awaitingIndex = nil }
    if index == awaitingIndex { awaitingIndex = nil }
    // Don't move the thumb in response to committed pages until the gesture finishes.
    let oldShownIndex = shownIndex
    if configurationChanged || !isPanning && !slider.isTracking && awaitingIndex == nil {
      shownIndex = index
      if slider.value != Float(index) {
        slider.setValue(Float(index), animated: false)
      }
    }
    if oldShownIndex != shownIndex || configurationChanged || localeChanged {
      updateNumbers()
    }
  }

  @objc private func valueChanged() {
    let index = min(max(Int(slider.value.rounded()), 0), count - 1)
    guard index != shownIndex else { return }
    shownIndex = index
    updateNumbers()
    if !isPanning && !slider.isTracking { emitSeek() }
  }

  func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
    guard let pan = recognizer as? PageSliderPan, let origin = pan.origin,
          slider.isEnabled else { return false }
    let translation = pan.translation(in: slider)
    let velocity = pan.velocity(in: slider)
    guard abs(velocity.x) > abs(velocity.y) || abs(translation.x) > abs(translation.y) else {
      return false
    }
    let track = slider.trackRect(forBounds: slider.bounds)
    let thumb = slider.thumbRect(forBounds: slider.bounds, trackRect: track,
                                value: Float(shownIndex))
    // Keep an off-thumb tap as a tap and accept the full visible thumb.
    guard abs(origin.x - thumb.midX) <= max(22, thumb.width / 2 + 6) else { return false }
    let start = slider.thumbRect(forBounds: slider.bounds, trackRect: track, value: 0).midX
    let end = slider.thumbRect(forBounds: slider.bounds, trackRect: track,
                              value: slider.maximumValue).midX
    guard start != end else { return false }
    dragTrack = (start, end, origin.x - thumb.midX)
    isPanning = true
    return true
  }

  @objc private func dragThumb(_ pan: UIPanGestureRecognizer) {
    switch pan.state {
    case .began, .changed, .ended:
      guard let track = dragTrack else { return }
      let x = pan.location(in: slider).x - track.grab
      let fraction = min(max((x - track.start) / (track.end - track.start), 0), 1)
      slider.setValue(Float(fraction) * slider.maximumValue, animated: false)
      valueChanged()
      if pan.state == .ended {
        isPanning = false
        dragTrack = nil
        finishTracking()
      }
    case .cancelled, .failed:
      isPanning = false
      dragTrack = nil
      cancelTracking()
    default:
      break
    }
  }

  @objc private func seekToTap(_ tap: UITapGestureRecognizer) {
    guard slider.isEnabled else { return }
    let track = slider.trackRect(forBounds: slider.bounds)
    let start = slider.thumbRect(forBounds: slider.bounds, trackRect: track, value: 0).midX
    let end = slider.thumbRect(forBounds: slider.bounds, trackRect: track,
                              value: slider.maximumValue).midX
    guard start != end else { return }
    let x = tap.location(in: slider).x
    let thumb = slider.thumbRect(forBounds: slider.bounds, trackRect: track, value: slider.value)
      .insetBy(dx: -6, dy: 0)
    guard !(thumb.minX...thumb.maxX).contains(x) else { return }
    let fraction = (x - start) / (end - start)
    let target = min(max(Float(fraction), 0), 1) * slider.maximumValue
    slider.setValue(target.rounded(), animated: false)
    finishTracking()
  }

  private func finishTracking() {
    valueChanged()
    slider.setValue(Float(shownIndex), animated: false)
    emitSeek()
  }

  private func emitSeek() {
    guard shownIndex != (awaitingIndex ?? committedIndex) else { return }
    let requested = shownIndex
    awaitingIndex = requested
    channel.invokeMethod("seek", arguments: requested)
  }

  private func cancelTracking() {
    shownIndex = awaitingIndex ?? committedIndex
    slider.setValue(Float(shownIndex), animated: false)
    updateNumbers()
  }

  private func pageNumber(_ value: Int) -> String {
    numbers.string(from: NSNumber(value: value)) ?? "\(value)"
  }

  private func updateNumbers() {
    let current = pageNumber(shownIndex + 1)
    let firstText = reversed ? totalText : current
    let lastText = reversed ? current : totalText
    if first.text != firstText { first.text = firstText }
    if last.text != lastText { last.text = lastText }
    slider.accessibilityValue = "\(current) / \(totalText)"
  }
}

private final class PageSliderPan: UIPanGestureRecognizer {
  private(set) var origin: CGPoint?

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
    if origin == nil { origin = touches.first?.location(in: view) }
    super.touchesBegan(touches, with: event)
  }

  override func reset() {
    super.reset()
    origin = nil
  }
}

@available(iOS 26.0, *)
private final class PageSlider: UISlider {
  var onFinishTracking: (() -> Void)?
  var onCancelTracking: (() -> Void)?

  override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
    super.endTracking(touch, with: event)
    onFinishTracking?()
  }

  override func cancelTracking(with event: UIEvent?) {
    super.cancelTracking(with: event)
    onCancelTracking?()
  }

  override func accessibilityIncrement() { step(by: 1) }
  override func accessibilityDecrement() { step(by: -1) }

  private func step(by delta: Float) {
    guard isEnabled else { return }
    setValue(value.rounded() + delta, animated: false)
    sendActions(for: .valueChanged)
  }
}
