import Foundation
import SwiftUI
import UserNotifications
import Phrasing
import SessionHealthCore


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
///
/// **Whether to say anything at all is the person's, and it is answered here — at the last
/// step before the screen.** Everything above this line runs exactly as it does for somebody
/// who has said nothing: the rules read, the lights change, and `AlertDispatch` goes on
/// remembering which marks it has accounted for. That is the point of putting the silence at
/// the edge rather than higher up: a memory that stopped recording while the app was quiet
/// would have a backlog in it, and switching the notifications back on would empty that
/// backlog onto somebody who had just asked to be interrupted again.
@MainActor
final class Notifier {
    /// How many notifications may wait while the permission dialog is open. A crossed mark is
    /// worth saying late; twenty of them are worth saying once.
    private static let queueLimit = 5

    /// Which channel this run settled on, or `nil` while nothing has been sent yet.
    ///
    /// Read by the checkup, which is the only honest thing it can say about notifications:
    /// there is no tick to show for something whose availability is not decided until it is
    /// used, and whose banners may arrive under somebody else's name.
    private(set) var channel: NotificationChannel?

    private var asking = false
    private var queued: [NotificationText] = []

    /// Whether the person has asked the app to keep quiet. A way of asking rather than an
    /// answer, because the answer changes under a running app: the settings window writes that
    /// file, and a copy of it taken at launch would go on announcing marks to somebody who had
    /// switched them off a minute ago.
    private let isSilenced: () -> Bool

    init(isSilenced: @escaping () -> Bool = { NotificationChoice.isSilenced() }) {
        self.isSilenced = isSilenced
    }

    func deliver(_ texts: [NotificationText]) {
        guard !texts.isEmpty else { return }
        // Asked after the caller has done its accounting and before anything reaches the
        // screen — the whole of the silence, in one place. Nothing is queued either: these are
        // not notifications waiting for a channel, they are notifications somebody asked not
        // to have.
        guard !isSilenced() else { return }
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
            settle(on: .scriptEditor)
            return
        }

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { [weak self] granted, _ in
            Task { @MainActor in self?.settle(on: granted ? .ownName : .scriptEditor) }
        }
    }

    private func settle(on channel: NotificationChannel) {
        self.channel = channel
        let waiting = queued
        queued = []
        for text in waiting { post(text, over: channel) }
    }

    private func post(_ text: NotificationText, over channel: NotificationChannel) {
        switch channel {
        case .ownName: postThroughCentre(text)
        case .scriptEditor: postThroughScript(text)
        }
    }

    private func postThroughCentre(_ text: NotificationText) {
        let content = UNMutableNotificationContent()
        content.title = said(text.title)
        content.body = said(text.body)
        // `sound` is deliberately left unset: that is what makes it silent.

        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }

    private func postThroughScript(_ text: NotificationText) {
        let script = NotificationScript.display(title: said(text.title), body: said(text.body))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
    }

    /// Which side of a phrase goes on the screen, asked at the moment it goes there.
    ///
    /// Not when the notification was built: a mark crossed while the permission dialog was open
    /// can be minutes old by the time it is shown, and the language it should arrive in is the
    /// one the reader is looking at now.
    private func said(_ phrase: Phrase) -> String { InterfaceLanguage.shared.say(phrase) }
}

/// The checkbox on the notifications row of the checkup: say something, or keep quiet.
///
/// It stands in that row rather than in a preferences pane of its own for the reason the login
/// checkbox does: the line is already there saying what notifications are for and whose name
/// they arrive under, and a decision belongs beside the sentence that explains it. Both are
/// controls in a list of readings, and both say what they are by being the answer.
///
/// The choice lives in a file (`NotificationChoice`), which is read here and written here and
/// nowhere else in this window. The system is not involved at any point: this is not a
/// permission, and there is nothing to ask anybody for.
struct NotificationToggle: View {
    @EnvironmentObject private var interface: InterfaceLanguage

    /// Seeded from the disk when the row is built, and read again whenever it appears — the
    /// file can be deleted by hand while the app runs, which is the other half of keeping a
    /// choice where a person can see it.
    @State private var isAnnouncing = !NotificationChoice.isSilenced()

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Toggle(interface.say(CheckupPhrasing.announceMarks), isOn: Binding(
                get: { isAnnouncing },
                set: { wanted in
                    isAnnouncing = wanted
                    NotificationChoice.silence(!wanted)
                }
            ))
            .toggleStyle(.checkbox)
            if !isAnnouncing {
                Text(interface.say(CheckupPhrasing.silenced))
                    .font(WindowType.detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { isAnnouncing = !NotificationChoice.isSilenced() }
    }
}
