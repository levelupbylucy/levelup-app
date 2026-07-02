import Flutter
import FirebaseCore
import UIKit
import WidgetKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let appGroupId = "group.com.lucienadvornik.levelup"
  private var futureImagePickerDelegate: NSObject?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if FirebaseApp.app() == nil {
      FirebaseApp.configure()
    }
    let didFinish = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    configurePlatformChannels()
    return didFinish
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  private func configurePlatformChannels(retry: Int = 0) {
    DispatchQueue.main.asyncAfter(deadline: .now() + (retry == 0 ? 0.0 : 0.25)) {
      guard let controller = self.findFlutterViewController() else {
        if retry < 8 {
          self.configurePlatformChannels(retry: retry + 1)
        }
        return
      }

      self.configurePhotoPickerChannel(controller: controller)
      self.configureWidgetDataChannel(controller: controller)
    }
  }

  private func findFlutterViewController() -> FlutterViewController? {
    if let controller = window?.rootViewController as? FlutterViewController {
      return controller
    }

    for scene in UIApplication.shared.connectedScenes {
      guard let windowScene = scene as? UIWindowScene else { continue }
      for window in windowScene.windows {
        if let controller = findFlutterViewController(in: window.rootViewController) {
          return controller
        }
      }
    }

    return nil
  }

  private func findFlutterViewController(in controller: UIViewController?) -> FlutterViewController? {
    if let flutterController = controller as? FlutterViewController {
      return flutterController
    }
    for child in controller?.children ?? [] {
      if let flutterController = findFlutterViewController(in: child) {
        return flutterController
      }
    }
    if let presented = controller?.presentedViewController {
      return findFlutterViewController(in: presented)
    }
    return nil
  }

  private func configurePhotoPickerChannel(controller: FlutterViewController) {
      let channel = FlutterMethodChannel(
        name: "levelup/photo_picker",
        binaryMessenger: controller.binaryMessenger
      )

      channel.setMethodCallHandler { call, result in
        guard call.method == "pickFutureImage" else {
          result(FlutterMethodNotImplemented)
          return
        }

        guard UIImagePickerController.isSourceTypeAvailable(.photoLibrary) else {
          result(FlutterError(
            code: "UNAVAILABLE",
            message: "Photo library is not available on this device.",
            details: nil
          ))
          return
        }

        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.mediaTypes = ["public.image"]
        picker.allowsEditing = true

        let delegate = FutureImagePickerDelegate { [weak self] path in
          result(path)
          self?.futureImagePickerDelegate = nil
        }
        picker.delegate = delegate
        self.futureImagePickerDelegate = delegate
        controller.present(picker, animated: true)
      }
  }

  private func configureWidgetDataChannel(controller: FlutterViewController) {
      let channel = FlutterMethodChannel(
        name: "levelup/widget_data",
        binaryMessenger: controller.binaryMessenger
      )

      channel.setMethodCallHandler { call, result in
        let defaults = UserDefaults(suiteName: self.appGroupId)

        switch call.method {
        case "updateWidgetData":
          let arguments = call.arguments as? [String: Any] ?? [:]

          for (key, value) in arguments {
            defaults?.set(value, forKey: key)
          }

          defaults?.synchronize()

          if #available(iOS 14.0, *) {
            WidgetCenter.shared.reloadAllTimelines()
          }

          result(nil)
        case "readWidgetTaskStates":
          result(defaults?.string(forKey: "widget_tasks_json") ?? "[]")
        default:
          result(FlutterMethodNotImplemented)
        }
      }
  }
}


private final class FutureImagePickerDelegate: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
  private let completion: (String?) -> Void

  init(completion: @escaping (String?) -> Void) {
    self.completion = completion
  }

  func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
    picker.dismiss(animated: true)
    completion(nil)
  }

  func imagePickerController(
    _ picker: UIImagePickerController,
    didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
  ) {
    picker.dismiss(animated: true)

    let sourceUrl = info[.imageURL] as? URL
    let editedImage = info[.editedImage] as? UIImage
    let image = editedImage ?? (info[.originalImage] as? UIImage)
    let fileManager = FileManager.default
    let extensionValue = sourceUrl?.pathExtension.isEmpty == false ? sourceUrl!.pathExtension : "jpg"
    let destination = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("future_me_\(UUID().uuidString).\(extensionValue)")

    do {
      if let editedImage, let data = editedImage.jpegData(compressionQuality: 0.88) {
        try data.write(to: destination, options: .atomic)
      } else if let sourceUrl {
        if fileManager.fileExists(atPath: destination.path) {
          try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: sourceUrl, to: destination)
      } else if let image, let data = image.jpegData(compressionQuality: 0.88) {
        try data.write(to: destination, options: .atomic)
      } else {
        completion(nil)
        return
      }
      completion(destination.path)
    } catch {
      completion(nil)
    }
  }
}
