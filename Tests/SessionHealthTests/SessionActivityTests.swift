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

    // The fuse under the blinking light. Nothing on disk says a session died, so a wait that
    // has gone this long without a word stops being one an answer is expected out of — it is
    // drawn as a stall instead, and the session goes on being listed for its own, much longer,
    // window: quiet is not the same as finished.
    suite.test("a wait that has just started is one somebody is waiting on") {
        suite.expectEqual(activity.replyWait(since: now.addingTimeInterval(-5), now: now), .waiting, "5 seconds in")
    }

    suite.test("the edge of the fuse still waits, just past it stalls") {
        let fuse = config.abandonedWait.seconds
        suite.expectEqual(
            activity.replyWait(since: now.addingTimeInterval(-fuse), now: now), .waiting, "exactly at the mark"
        )
        suite.expectEqual(
            activity.replyWait(since: now.addingTimeInterval(-fuse - 1), now: now), .stalled, "a second past it"
        )
        suite.expect(fuse < window, "the fuse must be shorter than the window the session itself gets")
    }

    // A stall is still an answer owed, which is what the sign says and what separates it from
    // a session that has simply gone quiet.
    suite.test("a stall says an answer is owed, an idle session says nothing is") {
        suite.expect(activity.replyWait(since: now.addingTimeInterval(-86_400), now: now).isOwed, "still owed")
        suite.expect(!activity.replyWait(since: nil, now: now).isOwed, "nothing owed")
    }

    suite.test("nothing owed is not a wait at all") {
        suite.expectEqual(activity.replyWait(since: nil, now: now), .none, "no answer owed")
    }

    suite.test("an entry written in the future is a wait rather than a stalled one") {
        suite.expectEqual(activity.replyWait(since: now.addingTimeInterval(600), now: now), .waiting, "ahead of now")
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
