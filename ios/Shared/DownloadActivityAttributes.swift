// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import ActivityKit

enum DownloadIslandVariant: String, Codable, Hashable {
  case kiriRing = "wajah-kiri-ring"
  case kiriPercentage = "wajah-kiri-persen"
  case scarf = "syal-penanda"
  case mangaPanel = "panel-manga"

  static let defaultValue = Self.kiriRing

  init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer().decode(String.self)
    self = Self(rawValue: value) ?? Self.defaultValue
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
