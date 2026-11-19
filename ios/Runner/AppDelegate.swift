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

  #if targetEnvironment(simulator) && DEBUG
  /// The Mac-side runtime a Debug Simulator build uses, since the embedded
  /// OpenJDK has no Simulator slice. Launch environment variables win; without
  /// them the app reads the port and token that
  /// tool/qa/ensure_simulator_runtime.sh writes during the Xcode build.
  private static func simulatorRuntimeHost() -> (port: Int, token: String)? {
    func valid(_ port: Int?, _ token: String?) -> (port: Int, token: String)? {
      guard let port, (1...65535).contains(port), let token, token.count == 64,
            token.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
      return (port, token)
    }
    let environment = ProcessInfo.processInfo.environment
    if let host = valid(
      environment["KUCHIE_QA_EXTENSION_RUNTIME_PORT"].flatMap { Int($0) },
      environment["KUCHIE_QA_EXTENSION_RUNTIME_TOKEN"]) {
      return host
    }
    guard let home = environment["SIMULATOR_HOST_HOME"] else { return nil }
    let directory = URL(fileURLWithPath: home)
      .appendingPathComponent("development/kuchie-qa-extension-runtime", isDirectory: true)
    func read(_ name: String) -> String? {
      (try? String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8))?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return valid(read("runtime.port").flatMap { Int($0) }, read("runtime.token"))
  }
  #endif

  private func handleMihonRuntime(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "startServer":
      #if targetEnvironment(simulator) && DEBUG
      if let host = Self.simulatorRuntimeHost() {
        result(["port": host.port, "token": host.token])
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
