import Foundation
import SessionHealthCore

/// What counts as a session being worked on right now.
///
/// The rule decides what the menu shows, so it is written down here rather than left to
/// whichever reader happens to filter first.
func runSessionActivityTests(_ suite: TestSuite, config: ThresholdConfig) {
    let activity = SessionActivity(config: config)
    let window = config.sessionActivity.seconds
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    suite.test("the window comes from the config, not from the rule") {
        suite.expectEqual(activity.window, config.sessionActivity, "window")
        suite.expectEqual(config.sessionActivity.seconds, Double(config.sessionActivity.minutes) * 60, "minutes to seconds")
    }

    suite.test("a session written to a moment ago is active") {
        suite.expectEqual(activity.isActive(lastActivityAt: now.addingTimeInterval(-30), now: now), true, "30 seconds old")
    }

    suite.test("the edge of the window is still active, just past it is not") {
        suite.expectEqual(activity.isActive(lastActivityAt: now.addingTimeInterval(-window), now: now), true, "exactly at the mark")
        suite.expectEqual(activity.isActive(lastActivityAt: now.addingTimeInterval(-window - 1), now: now), false, "a second past it")
    }

    suite.test("a session from yesterday is not active") {
        suite.expectEqual(activity.isActive(lastActivityAt: now.addingTimeInterval(-86_400), now: now), false, "a day old")
    }

    suite.test("a file written in the future counts as active rather than as stale") {
        // A clock that moved or a copied file; treating it as long gone would hide a session
        // that is running.
        suite.expectEqual(activity.isActive(lastActivityAt: now.addingTimeInterval(600), now: now), true, "ahead of now")
    }

    suite.test("filtering keeps the active sessions and puts the freshest first") {
        let sessions = [
            session("old", ago: 86_400, from: now),
            session("stale", ago: window + 60, from: now),
            session("middle", ago: window / 2, from: now),
            session("freshest", ago: 10, from: now)
        ]
        let active = activity.active(sessions, now: now)
        suite.expectEqual(active.map(\.sessionID), ["freshest", "middle"], "active sessions, freshest first")
    }

    suite.test("nothing active is an empty list, which is a fact and not an error") {
        let active = activity.active([session("old", ago: 86_400, from: now)], now: now)
        suite.expectEqual(active.count, 0, "active sessions")
    }
}

private func session(_ id: String, ago: TimeInterval, from now: Date) -> SessionSnapshot {
    SessionSnapshot(
        sessionID: id,
        service: .claude,
        contextTokens: 1000,
        contextWindowTokens: nil,
        lastActivityAt: now.addingTimeInterval(-ago)
    )
}
