import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let mihonRuntimeToken = UUID().uuidString + UUID().uuidString

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AppleAppIconBridge") {
      AppleAppIconBridge.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AppleLiquidGlassTabBar") {
      AppleLiquidGlassTabBarFactory.register(with: registrar)
    }
    if #available(iOS 26.0, *),
       let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AppleGlassSearch") {
      AppleGlassSearchFactory.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AppleGlassSegments") {
      AppleGlassSegmentsFactory.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AppleGlassToolbar") {
      AppleGlassToolbarFactory.register(with: registrar)
    }
    if #available(iOS 26.0, *),
       let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AppleGlassReaderSlider") {
      AppleGlassReaderSliderFactory.register(with: registrar)
    }
    if #available(iOS 26.0, *),
       let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AppleGlassSheet") {
      AppleGlassSheetFactory.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "InAppWebView") {
      InAppWebViewFactory.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "DownloadLiveActivityBridge") {
      DownloadLiveActivityBridge.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "MihonRuntimeBridge") {
      let channel = FlutterMethodChannel(
        name: "m_extension_server", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler(handleMihonRuntime)
    }
  }

  private func handleMihonRuntime(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "startServer":
      #if targetEnvironment(simulator) && DEBUG
      let environment = ProcessInfo.processInfo.environment
      if let value = environment["KUCHIE_QA_EXTENSION_RUNTIME_PORT"],
         let port = Int(value), (1...65535).contains(port),
         let token = environment["KUCHIE_QA_EXTENSION_RUNTIME_TOKEN"],
         token.count == 64, token.allSatisfy({ $0.isASCII && $0.isHexDigit }) {
        result(["port": port, "token": token])
        return
      }
      #endif
      // Zero and the APK converter start lazily, on the first extension request.
      let token = mihonRuntimeToken
      MihonRuntimeBridge.start(onPort: 0, token: token) { port, error in
        if let error {
          result(FlutterError(
            code: "mihon_runtime_unavailable", message: error.localizedDescription, details: nil))
        } else {
          result(["port": port, "token": token])
        }
      }
    case "stopServer":
      MihonRuntimeBridge.stop { error in
        if let error {
          result(FlutterError(
            code: "mihon_runtime_stop_failed", message: error.localizedDescription, details: nil))
        } else {
          result(nil)
        }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
