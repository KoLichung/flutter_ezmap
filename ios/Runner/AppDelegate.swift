import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var eventSink: FlutterEventSink?
  
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller = window?.rootViewController as! FlutterViewController
    
    // Method Channel: 獲取啟動時接收到的檔案
    let methodChannel = FlutterMethodChannel(
      name: "com.chijia.flutter_ezmap/shared_file",
      binaryMessenger: controller.binaryMessenger
    )
    methodChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      if call.method == "getInitialSharedFile" {
        if let url = self?.getInitialSharedFileURL() {
          result(url.path)
        } else {
          result(nil)
        }
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    
    // Event Channel: 處理運行時接收到的檔案
    let eventChannel = FlutterEventChannel(
      name: "com.chijia.flutter_ezmap/shared_file_stream",
      binaryMessenger: controller.binaryMessenger
    )
    eventChannel.setStreamHandler(self)
    
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey : Any] = [:]
  ) -> Bool {
    if url.pathExtension == "gpx" {
      handleSharedFile(url: url)
    }
    return true
  }
  
  override func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
  ) -> Bool {
    if userActivity.activityType == NSUserActivityTypeBrowsingWeb,
       let url = userActivity.webpageURL,
       url.pathExtension == "gpx" {
      handleSharedFile(url: url)
    }
    return true
  }
  
  private func getInitialSharedFileURL() -> URL? {
    // 檢查是否有啟動時的檔案 URL
    // 這通常在應用啟動時通過 URL scheme 或 document picker 傳遞
    return nil
  }
  
  private func handleSharedFile(url: URL) {
    // 通知 Flutter 檔案路徑
    // 實際的檔案複製會在 Flutter 端處理
    if let eventSink = eventSink {
      eventSink(url.path)
    }
  }
}

extension AppDelegate: FlutterStreamHandler {
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = events
    return nil
  }
  
  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }
}
