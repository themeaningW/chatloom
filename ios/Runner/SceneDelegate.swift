import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    // Let Flutter finish any legacy AppDelegate-window migration first. Keep
    // its storyboard-created controller and implicit engine, replacing only
    // the startup window before the scene becomes active or editing begins.
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    guard let windowScene = scene as? UIWindowScene,
          windowScene.activationState != .foregroundActive,
          let previous = window,
          !(previous is ChatLoomShakeWindow),
          let controller = previous.rootViewController else { return }
    let replacement = ChatLoomShakeWindow(windowScene: windowScene)
    replacement.frame = previous.frame
    replacement.windowLevel = previous.windowLevel
    replacement.backgroundColor = previous.backgroundColor
    previous.isHidden = true
    previous.rootViewController = nil
    replacement.rootViewController = controller
    window = replacement
    if let appDelegate = UIApplication.shared.delegate as? FlutterAppDelegate,
       appDelegate.window === previous {
      appDelegate.window = replacement
    }
    replacement.makeKeyAndVisible()
  }
}
