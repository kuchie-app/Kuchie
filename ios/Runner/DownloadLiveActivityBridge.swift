// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import ActivityKit
import Flutter
import UIKit
import os

enum DownloadLiveActivityBridge {
  @MainActor
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "kuchie/download_live_activity", binaryMessenger: registrar.messenger()
    )

    channel.setMethodCallHandler { call, result in
      if #available(iOS 16.2, *) {
        // A method channel without a background task queue runs on the main thread.
        MainActor.assumeIsolated {
          DownloadLiveActivityCoordinator.shared.handle(call, result: result)
        }
      } else {
        switch call.method {
        case "update", "end": result(nil)
        case "getIslandVariant", "setIslandVariant":
          result(FlutterError(
            code: "live_activity_unavailable", message: "Live Activities require iOS 16.2", details: nil
          ))
        default: result(FlutterMethodNotImplemented)
        }
      }
    }
  }
}

@available(iOS 16.2, *)
@MainActor
private final class DownloadLiveActivityCoordinator {
  static let shared = DownloadLiveActivityCoordinator()

  private typealias DownloadActivity = Activity<DownloadActivityAttributes>
  private typealias ContentState = DownloadActivityAttributes.ContentState

  private enum Command {
    case downloading(ContentState)
    case idle
    case setIslandVariant(DownloadIslandVariant)
  }

  private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "Kuchie", category: "LiveActivity"
  )
  private var lastCommand: Task<Void, Never>?
  private var activity: DownloadActivity?
  private let variantKey = "kuchie.downloadLiveActivity.islandVariant"

  private var preferredVariant: DownloadIslandVariant {
    UserDefaults.standard.string(forKey: variantKey)
      .flatMap { DownloadIslandVariant(id: $0) } ?? .defaultValue
  }

  func handle(_ call: FlutterMethodCall, result: FlutterResult) {
    let state: Command
    switch call.method {
    case "update":
      guard let args = call.arguments as? [String: Any],
        let remaining = args["remaining"] as? Int, remaining > 0
      else {
        result(FlutterError(
          code: "invalid_download_activity", message: "Expected a positive remaining count",
          details: nil
        ))
        return
      }
      let progress = args["progress"] as? Double
      state = .downloading(ContentState(
        progress: progress.flatMap { (0...1).contains($0) ? $0 : nil },
        remaining: remaining,
        source: (args["source"] as? String).flatMap(ContentState.Source.init(rawValue:)),
        reduceMotion: args["reduceMotion"] as? Bool
      ))
    case "end":
      state = .idle
    case "getIslandVariant":
      result(preferredVariant.rawValue)
      return
    case "setIslandVariant":
      guard let id = call.arguments as? String,
            let variant = DownloadIslandVariant(id: id)
      else {
        result(FlutterError(
          code: "invalid_island_variant", message: "Expected a supported appearance ID", details: nil
        ))
        return
      }
      if variant == .defaultValue {
        UserDefaults.standard.removeObject(forKey: variantKey)
      } else {
        UserDefaults.standard.set(variant.rawValue, forKey: variantKey)
      }
      state = .setIslandVariant(variant)
    default:
      result(FlutterMethodNotImplemented)
      return
    }

    // ActivityKit updates suspend. Complete them in arrival order so an earlier
    // update cannot recreate an activity after a later idle event.
    let previous = lastCommand
    lastCommand = Task {
      await previous?.value
      switch state {
      case .downloading(let contentState): await update(contentState)
      case .idle: await end()
      case .setIslandVariant(let variant):
        await applyIslandVariant(variant)
      }
    }
    result(nil)
  }

  private func update(_ snapshot: ContentState) async {
    var state = snapshot
    state.islandVariant = preferredVariant
    let now = Date()
    let content = ActivityContent(state: state, staleDate: now.addingTimeInterval(60))
    if activity == nil {
      activity = DownloadActivity.activities.first
    }
    if let activity {
      // Keep the last activity until idle, including after someone dismisses it.
      // A later progress tick should never undo that person's action.
      if activity.activityState == .active || activity.activityState == .stale {
        let displayed = activity.content
        if activity.activityState == .active,
          displayed.state == state,
          let staleDate = displayed.staleDate,
          staleDate.timeIntervalSince(now) > 30
        {
          return
        }
        await activity.update(content)
      }
      return
    }

    guard ActivityAuthorizationInfo().areActivitiesEnabled,
      UIApplication.shared.applicationState == .active
    else { return }

    do {
      activity = try DownloadActivity.request(
        attributes: DownloadActivityAttributes(), content: content, pushType: nil
      )
    } catch {
      logger.error("Unable to start the download Live Activity: \(error.localizedDescription)")
    }
  }

  private func applyIslandVariant(_ variant: DownloadIslandVariant) async {
    guard variant == preferredVariant else { return }
    guard let current = activity ?? DownloadActivity.activities.first,
          current.activityState == .active || current.activityState == .stale
    else { return }
    let displayed = current.content
    guard displayed.state.effectiveIslandVariant != variant else { return }
    var state = displayed.state
    state.islandVariant = variant
    await current.update(ActivityContent(
      state: state, staleDate: displayed.staleDate, relevanceScore: displayed.relevanceScore
    ))
  }

  private func end() async {
    let current = activity
    activity = nil
    await current?.end(nil, dismissalPolicy: .immediate)
    // An idle snapshot can be the first command after the app relaunches.
    for existing in DownloadActivity.activities where existing.id != current?.id {
      await existing.end(nil, dismissalPolicy: .immediate)
    }
  }
}
