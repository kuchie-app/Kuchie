import Flutter
import UIKit

final class AppleAppIconBridge {
  private static let channelName = "kuchie/app_icon"

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
}
