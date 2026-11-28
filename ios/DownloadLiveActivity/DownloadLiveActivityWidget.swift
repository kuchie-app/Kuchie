// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import ActivityKit
import SwiftUI
import WidgetKit

@main
struct DownloadLiveActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: DownloadActivityAttributes.self) { context in
      DownloadActivityContent(context: context) { download in
        VStack(alignment: .leading, spacing: 10) {
          HStack(spacing: 8) {
            download.glyph(size: 20).accessibilityHidden(true)
            download.title.font(.headline)
            Spacer(minLength: 4)
            download.percentage
          }
          download.details
        }
        .padding(16)
      }
      .widgetURL(downloadsURL(source: context.state.effectiveSource))
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          DownloadActivityContent(context: context) { download in
            download.glyph(size: 24).accessibilityHidden(true)
          }
        }
        DynamicIslandExpandedRegion(.trailing) {
          DownloadActivityContent(context: context) { $0.percentage }
        }
        DynamicIslandExpandedRegion(.bottom) {
          DownloadActivityContent(context: context) { download in
            VStack(alignment: .leading, spacing: 6) {
              download.title.font(.headline)
              download.details
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
      } compactLeading: {
        DownloadActivityContent(context: context) { download in
          download.glyph(size: 22)
            .accessibilityLabel(download.title)
            .accessibilityValue(download.status)
        }
      } compactTrailing: {
        DownloadActivityContent(context: context) { $0.compactTrailing }
      } minimal: {
        DownloadActivityContent(context: context) { $0.minimal }
      }
      .widgetURL(downloadsURL(source: context.state.effectiveSource))
    }
  }

  private func downloadsURL(source: DownloadActivityAttributes.ContentState.Source) -> URL? {
    URL(string: "kuchie://downloads?tab=\(source.rawValue)")
  }
}

private struct DownloadActivityContent<Content: View>: View {
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @Environment(\.isLuminanceReduced) private var isLuminanceReduced

  let context: ActivityViewContext<DownloadActivityAttributes>
  @ViewBuilder let content: (DownloadActivityDisplay) -> Content

  var body: some View {
    content(DownloadActivityDisplay(
      context: context,
      shouldAnimate: !systemReduceMotion && !isLuminanceReduced && context.state.reduceMotion != true
    ))
  }
}

private struct DownloadActivityDisplay {
  let context: ActivityViewContext<DownloadActivityAttributes>
  let shouldAnimate: Bool

  private var variant: DownloadIslandVariant { context.state.effectiveIslandVariant }

  private var progressAnimation: Animation? {
    shouldAnimate ? .easeOut(duration: 0.28) : nil
  }

  var progress: Double? {
    context.isStale ? nil : context.state.progress
  }

  var title: Text {
    if context.state.effectiveSource == .server {
      return Text("Server downloads")
    }
    if context.state.effectiveSource == .local {
      // Kuchie 2.0 has one collection, on this iPhone.
      return Text("iPhone downloads")
    }
    return progress == nil ? Text("Chapter downloads") : Text("Downloading chapter")
  }

  var icon: some View {
    Image(systemName: symbol)
      .font(.subheadline.weight(.semibold))
      .contentTransition(shouldAnimate ? .opacity : .identity)
  }

  @ViewBuilder
  func glyph(size: CGFloat) -> some View {
    if context.isStale {
      icon.frame(width: size, height: size)
    } else {
      Image(glyphAsset)
        .renderingMode(.original)
        .resizable()
        .scaledToFit()
        .frame(width: size, height: size)
        .contentTransition(shouldAnimate ? .opacity : .identity)
    }
  }

  private var glyphAsset: String {
    switch variant {
    case .kiriRing, .kiriPercentage: "IslandKiriFace"
    case .scarf: "IslandBookmarkScarf"
    case .mangaPanel: "IslandMangaPanel"
    }
  }

  private var symbol: String {
    if context.isStale { return "clock.arrow.circlepath" }
    return context.state.effectiveSource == .server ? "icloud.and.arrow.down" : "arrow.down.to.line"
  }

  @ViewBuilder
  var percentage: some View {
    if let progress {
      formattedPercentage(progress)
        .font(.subheadline.weight(.semibold))
        .monospacedDigit()
        .contentTransition(shouldAnimate ? .numericText() : .identity)
        .animation(progressAnimation, value: progress)
        .accessibilityLabel(Text("Current chapter progress"))
        .accessibilityValue(formattedPercentage(progress))
    }
  }

  @ViewBuilder
  var compactTrailing: some View {
    if let progress {
      switch variant {
      case .kiriRing, .scarf:
        standaloneRing(progress)
      case .kiriPercentage:
        ViewThatFits(in: .horizontal) {
          percentage
          standaloneRing(progress)
        }
      case .mangaPanel:
        remainingCount
      }
    } else if variant == .mangaPanel && !context.isStale {
      remainingCount
    } else {
      Image(systemName: context.isStale ? "exclamationmark.circle" : "ellipsis")
        .font(.subheadline.weight(.semibold))
        .accessibilityLabel(status)
    }
  }

  private var remainingCount: some View {
    ViewThatFits(in: .horizontal) {
      Text("\(context.state.remaining) left")
      Text(context.state.remaining, format: .number)
    }
    .font(.subheadline.weight(.semibold))
    .monospacedDigit()
    .contentTransition(shouldAnimate ? .numericText(countsDown: true) : .identity)
    .animation(progressAnimation, value: context.state.remaining)
    .accessibilityLabel(Text("Chapters remaining: \(context.state.remaining)"))
  }

  @ViewBuilder
  var details: some View {
    if context.isStale {
      Text("Progress hasn’t updated")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    } else {
      Text("Chapters remaining: \(context.state.remaining)")
        .font(.subheadline)
        .foregroundStyle(.secondary)
      if let progress {
        ProgressView(value: progress)
          .progressViewStyle(.linear)
          .tint(.primary)
          .animation(progressAnimation, value: progress)
          .accessibilityHidden(true)
      }
    }
  }

  var minimal: some View {
    ZStack {
      if let progress {
        progressRing(progress, size: 24)
      }
      glyph(size: 15)
    }
    .frame(width: 24, height: 24)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title)
    .accessibilityValue(status)
  }

  private func standaloneRing(_ progress: Double) -> some View {
    progressRing(progress, size: 20)
      .accessibilityLabel(Text("Current chapter progress"))
      .accessibilityValue(formattedPercentage(progress))
  }

  private func progressRing(_ progress: Double, size: CGFloat) -> some View {
    ZStack {
      Circle().strokeBorder(Color.primary.opacity(0.28), lineWidth: 2)
      Circle()
        .trim(from: 0, to: progress)
        .stroke(Color(red: 0.82, green: 0.72, blue: 0.97),
                style: StrokeStyle(lineWidth: 2, lineCap: .round))
        .rotationEffect(.degrees(-90))
        .padding(1)
        .opacity(progress > 0 ? 1 : 0)
        .animation(progressAnimation, value: progress)
    }
    .frame(width: size, height: size)
  }

  var status: Text {
    if context.isStale {
      return Text("Progress hasn’t updated")
    }
    if let progress {
      return formattedPercentage(progress)
    }
    return Text("Progress unavailable")
  }

  private func formattedPercentage(_ progress: Double) -> Text {
    Text(progress, format: .percent.precision(.fractionLength(0)).rounded(rule: .down))
  }
}
