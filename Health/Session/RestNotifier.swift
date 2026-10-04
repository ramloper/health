import AudioToolbox
import UIKit
import UserNotifications

/// Local notification that makes the rest timer "ring": on the lock screen, in another app, and — through
/// `RestAlertPresenter` — while this app is on screen.
enum RestNotifier {
    private static let id = "gym.rest.done"
    /// nil until the system has answered the permission request.
    private(set) static var authorized: Bool?
    /// Bumped by every schedule/cancel so a late permission answer cannot add a stale request.
    private static var generation = 0

    /// Reads the current permission so an already-granted app schedules synchronously from the first rest.
    static func refreshAuthorization() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status = settings.authorizationStatus
            DispatchQueue.main.async {
                switch status {
                case .notDetermined: break
                case .denied: authorized = false
                default: authorized = true
                }
            }
        }
    }

    static func schedule(after seconds: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        generation += 1
        guard seconds > 0 else { return }
        let token = generation
        let add = {
            let content = UNMutableNotificationContent()
            content.title = "휴식 끝"
            content.body = "다음 세트 갈 시간이에요."
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(seconds), repeats: false)
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
        switch authorized {
        case true?:
            add()
        case false?:
            break
        case nil:
            center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                DispatchQueue.main.async {
                    authorized = granted
                    if granted, token == generation { add() }
                }
            }
        }
    }

    static func cancel() {
        generation += 1
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    /// The timer reached zero with the app on screen. The pending notification is left alone: it is the alarm,
    /// presented by `RestAlertPresenter`. Without notification permission a system alert sound stands in.
    static func ringInApp() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if authorized != true {
            AudioServicesPlayAlertSound(SystemSoundID(1005))
        }
    }

    /// The rest ended while the app was away and the notification already rang: clear it from Notification Center.
    static func clearDelivered() {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
    }
}

/// Without a delegate iOS drops notifications that fire while the app is in the foreground, so the rest timer
/// stayed silent whenever the screen was on. Present them with a banner and sound instead.
final class RestAlertPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = RestAlertPresenter()
    static let foregroundOptions: UNNotificationPresentationOptions = [.banner, .sound]

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler(Self.foregroundOptions)
    }
}
