import Flutter
import FirebaseCore
import UIKit
import WidgetKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let appGroupId = "group.com.lucienadvornik.levelup"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if FirebaseApp.app() == nil {
      FirebaseApp.configure()
    }
    configureWidgetDataChannel()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  private func configureWidgetDataChannel() {
    DispatchQueue.main.async {
      guard let controller = self.window?.rootViewController as? FlutterViewController else {
        return
      }

      let channel = FlutterMethodChannel(
        name: "levelup/widget_data",
        binaryMessenger: controller.binaryMessenger
      )

      channel.setMethodCallHandler { call, result in
        guard call.method == "updateWidgetData" else {
          result(FlutterMethodNotImplemented)
          return
        }

        let arguments = call.arguments as? [String: Any] ?? [:]
        let defaults = UserDefaults(suiteName: self.appGroupId)

        for (key, value) in arguments {
          defaults?.set(value, forKey: key)
        }

        defaults?.synchronize()

        if #available(iOS 14.0, *) {
          WidgetCenter.shared.reloadAllTimelines()
        }

        result(nil)
      }
    }
  }
}
