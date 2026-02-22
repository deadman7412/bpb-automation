import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "com.bpb.bpb_automation/native",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self else { return }
        switch call.method {
        case "requestNotificationPermission":
          self.requestNotificationPermission(result: result)
        case "showLocalNotification":
          self.showLocalNotification(call: call, result: result)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func requestNotificationPermission(result: @escaping FlutterResult) {
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) {
        granted, error in
        DispatchQueue.main.async {
          if let error = error {
            result(
              FlutterError(
                code: "NOTIFICATION_PERMISSION_FAILED",
                message: error.localizedDescription,
                details: nil
              )
            )
            return
          }
          result(granted)
        }
      }
    } else {
      result(false)
    }
  }

  private func showLocalNotification(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard #available(iOS 10.0, *) else {
      result(false)
      return
    }
    guard let args = call.arguments as? [String: Any] else {
      result(
        FlutterError(
          code: "NOTIFICATION_INVALID_ARGS",
          message: "Expected map arguments",
          details: nil
        )
      )
      return
    }
    let title = (args["title"] as? String) ?? "BPB Automation"
    let body = (args["body"] as? String) ?? ""

    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default

    let request = UNNotificationRequest(
      identifier: UUID().uuidString,
      content: content,
      trigger: nil
    )
    UNUserNotificationCenter.current().add(request) { error in
      DispatchQueue.main.async {
        if let error = error {
          result(
            FlutterError(
              code: "NOTIFICATION_SHOW_FAILED",
              message: error.localizedDescription,
              details: nil
            )
          )
          return
        }
        result(true)
      }
    }
  }
}
