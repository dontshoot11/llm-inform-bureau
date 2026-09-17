import Foundation
import Phrasing
import ServiceManagement
import SwiftUI

/// Starting with the Mac, and saying so honestly when it cannot.
///
/// `SMAppService` is the supported way since macOS 13: the app registers itself, the system
/// lists it under Login Items, and a person can turn it off there without the app knowing.
/// So the state is read back from the system on every look rather than remembered here — a
/// remembered "on" that the system disagrees with is the classic way this control starts
/// lying.
///
/// Two states are not simply on and off and are worth their own sentence:
///
/// - **Approval pending.** Registering succeeds while the system still shows the item as
///   waiting for the user in Settings, and it will not launch until they allow it.
/// - **No bundle.** Run straight from `swift run` there is no `.app` to register. That is a
///   developer running the executable, and the panel says so rather than failing silently.
@MainActor
final class LoginItem: ObservableObject {
    /// One instance per app. This is a proxy for a single system-wide setting, and the first
    /// run and the panel both show it — two copies would disagree the moment either changed it.
    static let shared = LoginItem()

    /// What the system says, in the terms the panel shows.
    enum State: Equatable {
        case on
        case off
        /// Registered, but the user has yet to allow it in System Settings.
        case waitingForApproval
        /// Cannot be offered at all, with the reason.
        case unavailable(String)
    }

    @Published private(set) var state: State = .off

    /// Non-nil after a register or unregister that failed. The panel shows it next to the
    /// toggle: a switch that flips back with no explanation is worse than no switch.
    @Published private(set) var problem: String?

    private let service: SMAppService? = Bundle.main.bundleIdentifier == nil ? nil : .mainApp

    init() {
        refresh()
    }

    /// Re-reads the system's answer. Called when the panel opens, because Login Items can be
    /// changed in System Settings while this app is running.
    func refresh() {
        guard let service else {
            state = .unavailable("Available once the app runs from the bundle built by Scripts/build-app.sh.")
            return
        }
        switch service.status {
        case .enabled: state = .on
        case .requiresApproval: state = .waitingForApproval
        case .notRegistered, .notFound: state = .off
        @unknown default: state = .off
        }
    }

    func set(_ wanted: Bool) {
        guard let service else { return }
        problem = nil
        do {
            if wanted {
                try service.register()
            } else {
                // `unregister` throws when there is nothing registered, which is the state the
                // caller is asking for — not a failure worth showing.
                if service.status != .notRegistered { try service.unregister() }
            }
        } catch {
            problem = error.localizedDescription
        }
        refresh()
    }
}

/// The control, in the one place that draws it: one line of the checkup in the settings
/// window, where it stands as both what the state is and the way to change it.
struct LoginItemToggle: View {
    @ObservedObject var loginItem: LoginItem

    @EnvironmentObject private var interface: InterfaceLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            switch loginItem.state {
            case .unavailable(let why):
                note(interface.say(CheckupPhrasing.openAtLoginUnavailable(why)))
            case .on, .off, .waitingForApproval:
                Toggle(interface.say(CheckupPhrasing.openAtLogin), isOn: Binding(
                    get: { loginItem.state != .off },
                    set: { loginItem.set($0) }
                ))
                .toggleStyle(.checkbox)
                if loginItem.state == .waitingForApproval {
                    note("Waiting to be allowed in System Settings › General › Login Items.")
                }
            }
            if let problem = loginItem.problem {
                note(problem)
            }
        }
        // Login Items can be changed in System Settings while this app runs, so the system is
        // asked again every time this appears rather than trusted from last time.
        .onAppear { loginItem.refresh() }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
