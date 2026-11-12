import React
import React_RCTAppDelegate
import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
  var window: UIWindow?
  // Detox looks up the React Native factory on the app delegate; the UIScene
  // architecture creates it in SceneDelegate, which publishes it here.
  var reactNativeFactory: RCTReactNativeFactory?

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    true
  }
}
