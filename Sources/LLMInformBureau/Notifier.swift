import Foundation
import UserNotifications
import Phrasing


/// Puts a notification on screen, without a sound.
///
/// Silent is not a preference here: the widget interrupts while the user is working with
/// something else, and a sound would make it an event rather than a note. Neither channel
/// below ever asks for one.
///
/// There are two channels because the first one is not always available:
///
/// - `UNUserNotificationCenter`, which shows the app's own name and icon.
/// - `osascript`, which works from anything and attributes the notification to Script Editor.
///
/// **Today the second one is the channel that works.** An ad-hoc signature is not enough for
/// the notification centre on macOS 26: `requestAuthorization` comes back `granted: false` with
/// "Notifications are not allowed for this application" before any dialog is shown, and the app
/// never appears in the notification settings at all. Measured from three launches — the
/// executable directly, `open` from `.build`, `open` from `/Applications` — with a bundle whose
/// signing identifier matches its `CFBundleIdentifier`, which is what `Scripts/build-app.sh`
/// re-signs for. A build with a real Developer ID signature would use the first channel with no
/// change here: permission is asked for first, every time, and the fallback is what happens when
/// the answer is no.
///
/// The choice is made once, on the first notification, because asking for permission before
/// there is anything to say is how an app gets refused.
@MainActor
final class Notifier {
    private enum Channel {
        case system
        case script
    }

    /// How many notifications may wait while the permission dialog is open. A crossed mark is
    /// worth saying late; twenty of them are worth saying once.
    private static let queueLimit = 5

    private var channel: Channel?
    private var asking = false
    private var queued: [NotificationText] = []

    func deliver(_ texts: [NotificationText]) {
        guard !texts.isEmpty else { return }
        switch channel {
        case .some(let channel):
            for text in texts { post(text, over: channel) }
        case nil:
            queued.append(contentsOf: texts)
            queued = Array(queued.suffix(Self.queueLimit))
            askForPermission()
        }
    }

    private func askForPermission() {
        guard !asking else { return }
        asking = true

        // No bundle identifier means this is the bare SwiftPM executable, where the
        // notification centre is not merely unavailable but fatal to touch.
        guard Bundle.main.bundleIdentifier != nil else {
            settle(on: .script)
            return
        }

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { [weak self] granted, _ in
            Task { @MainActor in self?.settle(on: granted ? .system : .script) }
        }
    }

    private func settle(on channel: Channel) {
        self.channel = channel
        let waiting = queued
        queued = []
        for text in waiting { post(text, over: channel) }
    }

    private func post(_ text: NotificationText, over channel: Channel) {
        switch channel {
        case .system: postThroughCentre(text)
        case .script: postThroughScript(text)
        }
    }

    private func postThroughCentre(_ text: NotificationText) {
        let content = UNMutableNotificationContent()
        content.title = text.title
        content.body = text.body
        // `sound` is deliberately left unset: that is what makes it silent.

        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }

    private func postThroughScript(_ text: NotificationText) {
        // `display notification` without `sound name` is silent, which is the whole reason
        // this is a usable fallback rather than a worse one.
        let script = "display notification \(quoted(text.body)) with title \(quoted(text.title))"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
    }

    /// An AppleScript string literal. The body carries a slash command and a line break, so
    /// this is not decoration.
    private func quoted(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }
}
