// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import ActivityKit

enum DownloadIslandVariant: String, Codable, Hashable {
  case kiriRing = "kiri-face-ring"
  case kiriPercentage = "kiri-face-percentage"
  case scarf = "bookmark-scarf"
  case mangaPanel = "manga-panel"

  static let defaultValue = Self.kiriRing

  // IDs saved by Kuchie 1.0.0, before the assets had English names.
  private static let legacyIDs: [String: Self] = [
    "wajah-kiri-ring": .kiriRing,
    "wajah-kiri-persen": .kiriPercentage,
    "syal-penanda": .scarf,
    "panel-manga": .mangaPanel,
  ]

  init?(id: String) {
    guard let variant = Self(rawValue: id) ?? Self.legacyIDs[id] else { return nil }
    self = variant
  }

  init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer().decode(String.self)
    self = Self(id: value) ?? Self.defaultValue
  }
}

@available(iOS 16.2, *)
struct DownloadActivityAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    enum Source: String, Codable, Hashable {
      case device
      case local
      case server
    }

    var progress: Double?
    var remaining: Int
    var source: Source? = nil
    var islandVariant: DownloadIslandVariant? = nil
    var reduceMotion: Bool? = nil

    var effectiveSource: Source { source ?? .device }
    var effectiveIslandVariant: DownloadIslandVariant { islandVariant ?? .defaultValue }
  }
}
