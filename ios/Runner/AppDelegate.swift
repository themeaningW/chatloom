import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Some plugins install their own delegate while registering. Restore Flutter's
    // delegate so local notifications reach all registered application delegates.
    UNUserNotificationCenter.current().delegate = self
    ChatLoomShakeBridge.shared.register(
      messenger: engineBridge.applicationRegistrar.messenger()
    )
  }
}

/// UIKit already recognizes shakes; no accelerometer polling or extra permission.
/// The window sees motion before the first responder, including a text editor.
final class ChatLoomShakeWindow: UIWindow {
  override func sendEvent(_ event: UIEvent) {
    if isKeyWindow,
       windowScene?.activationState == .foregroundActive,
       event.type == .motion,
       event.subtype == .motionShake {
      ChatLoomShakeBridge.shared.emitShake()
    }
    super.sendEvent(event)
  }
}

/// A content-free, non-buffering stream. Dart controls foreground/privacy and
/// preference subscription, deduplication and the single feedback sheet.
final class ChatLoomShakeBridge: NSObject, FlutterStreamHandler {
  static let shared = ChatLoomShakeBridge()
  private var channel: FlutterEventChannel?
  private var availability: FlutterMethodChannel?
  private var sink: FlutterEventSink?
  private var subscription: String?
  private var previousShakeToEdit: Bool?

  private override init() {
    super.init()
    NotificationCenter.default.addObserver(
      self, selector: #selector(resumeShake),
      name: UIApplication.didBecomeActiveNotification, object: nil
    )
    NotificationCenter.default.addObserver(
      self, selector: #selector(suspendShake),
      name: UIApplication.willResignActiveNotification, object: nil
    )
  }

  func register(messenger: FlutterBinaryMessenger) {
    channel?.setStreamHandler(nil)
    availability?.setMethodCallHandler(nil)
    sink = nil
    subscription = nil
    suspendShake()
    let channel = FlutterEventChannel(
      name: "chatloom/ios_shake", binaryMessenger: messenger
    )
    self.channel = channel
    channel.setStreamHandler(self)
    let availability = FlutterMethodChannel(
      name: "chatloom/ios_shake/availability", binaryMessenger: messenger
    )
    self.availability = availability
    availability.setMethodCallHandler { call, result in
      guard call.method == "isAvailable" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let installed = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }
        .contains { $0 is ChatLoomShakeWindow }
      result(installed)
    }
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = nil
    subscription = nil
    suspendShake()
    guard let nonce = arguments as? String, !nonce.isEmpty else {
      return FlutterError(
        code: "invalid_subscription",
        message: "A nonempty subscription nonce is required.", details: nil
      )
    }
    subscription = nonce
    sink = events
    resumeShake()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    subscription = nil
    suspendShake()
    return nil
  }

  @objc private func resumeShake() {
    guard sink != nil,
          UIApplication.shared.applicationState == .active else { return }
    if previousShakeToEdit == nil {
      previousShakeToEdit = UIApplication.shared.applicationSupportsShakeToEdit
    }
    // The opted-in gesture opens feedback instead of also presenting Undo.
    // This never changes focus or the text editor's other undo/redo actions.
    UIApplication.shared.applicationSupportsShakeToEdit = false
  }

  @objc private func suspendShake() {
    if let previous = previousShakeToEdit {
      UIApplication.shared.applicationSupportsShakeToEdit = previous
      previousShakeToEdit = nil
    }
  }

  func emitShake() {
    guard UIApplication.shared.applicationState == .active,
          let sink = sink, let subscription = subscription else { return }
    sink(["type": "shake", "subscription": subscription])
  }
}
