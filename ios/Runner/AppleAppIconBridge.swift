import Flutter
import ImageIO
import UIKit
import UniformTypeIdentifiers

final class AppleAppIconBridge {
  private static let channelName = "kuchie/app_icon"
  private static let imageSize = 1024
  private static let maxFileSize = 40 * 1024 * 1024

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "state":
        DispatchQueue.main.async { result(state()) }
      case "setAlternateIcon":
        DispatchQueue.main.async {
          setAlternateIcon(call.arguments as? String, result: result)
        }
      case "prepareImage":
        guard let path = call.arguments as? String else {
          result(FlutterError(code: "invalid_image", message: nil, details: nil))
          return
        }
        DispatchQueue.global(qos: .userInitiated).async {
          let image = prepareImage(at: URL(fileURLWithPath: path))
          DispatchQueue.main.async {
            guard let image else {
              result(FlutterError(code: "invalid_image", message: nil, details: nil))
              return
            }
            result(FlutterStandardTypedData(bytes: image))
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func state() -> [String: Any] {
    let app = UIApplication.shared
    return [
      "available": app.supportsAlternateIcons,
      "current": app.alternateIconName.map { $0 as Any } ?? NSNull(),
    ]
  }

  private static func setAlternateIcon(_ name: String?, result: @escaping FlutterResult) {
    let app = UIApplication.shared
    guard app.supportsAlternateIcons else {
      result(FlutterError(code: "icons_unavailable", message: nil, details: nil))
      return
    }
    if name == app.alternateIconName {
      result(state())
      return
    }
    app.setAlternateIconName(name) { error in
      DispatchQueue.main.async {
        if let error {
          result(FlutterError(code: "icon_change_failed", message: error.localizedDescription, details: nil))
        } else {
          result(state())
        }
      }
    }
  }

  // Downsample before cropping; a large photo should never need a full-size decoded buffer.
  private static func prepareImage(at url: URL) -> Data? {
    guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
          values.isRegularFile == true, let size = values.fileSize,
          size > 0 && size <= maxFileSize,
          let source = CGImageSourceCreateWithURL(url as CFURL, [
            kCGImageSourceShouldCache: false,
          ] as CFDictionary),
          let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: imageSize * 2,
          ] as CFDictionary),
          let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: nil, width: imageSize, height: imageSize,
                                  bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
      return nil
    }

    let side = CGFloat(imageSize)
    let scale = side / CGFloat(min(thumbnail.width, thumbnail.height))
    let width = CGFloat(thumbnail.width) * scale
    let height = CGFloat(thumbnail.height) * scale
    context.setFillColor(red: 0.094, green: 0.078, blue: 0.176, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: side, height: side))
    context.interpolationQuality = .high
    context.draw(thumbnail, in: CGRect(x: (side - width) / 2, y: (side - height) / 2,
                                       width: width, height: height))

    let bytes = NSMutableData()
    guard let cropped = context.makeImage(),
          let encoder = CGImageDestinationCreateWithData(
            bytes as CFMutableData, UTType.png.identifier as CFString, 1, nil
          ) else { return nil }
    CGImageDestinationAddImage(encoder, cropped, nil)
    return CGImageDestinationFinalize(encoder) ? bytes as Data : nil
  }
}
