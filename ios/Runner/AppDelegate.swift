import Flutter
import UIKit
import workmanager

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Workmanager on iOS uses BGTaskScheduler. Every periodic task identifier
    // must be registered BEFORE `GeneratedPluginRegistrant.register(with:)`
    // and must also be listed under `BGTaskSchedulerPermittedIdentifiers`
    // in Info.plist, otherwise iOS silently drops the schedule.
    //
    // The string must match `kBackgroundPingTaskName` in
    // lib/services/background_ping_worker.dart.
    WorkmanagerPlugin.registerTask(withIdentifier: "mecpl.attendance.location_ping")

    // 30-minute target frequency for the attendance ping. iOS treats this
    // as a hint — BGTaskScheduler is opportunistic and may fire later.
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "mecpl.attendance.location_ping",
      frequency: NSNumber(value: 30 * 60)
    )

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
