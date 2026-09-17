import Foundation
import SessionHealthCore
import Phrasing

/// Telling the person out loud that an agent is waiting on them.
///
/// The sign in the bar is immediate and these are not: a notification interrupts whatever the
/// person is doing, and a question they were about to answer themselves is not worth being
/// interrupted over. So every case here is about one of the two halves of that — the delay
/// before anything is said, and saying it exactly once per wait.
func runAttentionNoticeTests(_ suite: TestSuite, config: ThresholdConfig) {
    let rules = BudgetRules(config: config)
    let delay = config.attentionNotice.seconds
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// A session whose agent asked something at `since` — or one that is asking nothing, which
    /// is what the warm-up pass of every case is made of.
    func session(
        _ id: String = "a",
        asking since: Date? = nil,
        asked: Asking = .question,
        about: String? = "Which approach should I take?",
        project: String? = "llm-inform-bureau",
        subagentOf parent: String? = nil
    ) -> SessionSnapshot {
        SessionSnapshot(
            sessionID: id,
            service: .claude,
            contextTokens: 40_000,
            contextWindowTokens: 200_000,
            project: project,
            lastActivityAt: since ?? now,
            replyWait: since.map { .asking(since: $0, for: asked) } ?? .waiting,
            request: since == nil ? nil : about,
            subagent: parent.map {
                SubagentOrigin(parentSessionID: $0, type: "Explore", task: "look around", inheritsParentWindow: true)
            }
        )
    }

    /// One pass of the app: the rules read every session against the clock, the dispatcher
    /// decides what is news.
    func pass(_ dispatch: inout AlertDispatch, _ sessions: [SessionSnapshot], at moment: Date) -> [BudgetAlert] {
        dispatch.pending(limits: [], sessions: sessions.map { rules.assess($0, now: moment) })
    }

    /// A dispatcher past its first pass, which is silent by design.
    func warmedUp(_ sessions: [SessionSnapshot] = [session()], at moment: Date = now) -> AlertDispatch {
        var dispatch = AlertDispatch()
        _ = pass(&dispatch, sessions, at: moment)
        return dispatch
    }

    suite.test("a request younger than the mark is not announced") {
        var dispatch = warmedUp()
        let asked = session(asking: now)
        let early = pass(&dispatch, [asked], at: now.addingTimeInterval(delay - 1))
        suite.expectEqual(early.count, 0, "notifications before the mark")
    }

    suite.test("a request exactly at the mark has not passed it") {
        var dispatch = warmedUp()
        let atTheMark = pass(&dispatch, [session(asking: now)], at: now.addingTimeInterval(delay))
        suite.expectEqual(atTheMark.count, 0, "notifications at the mark")
    }

    // The point of the whole feature: the person is somewhere else, and this is what reaches
    // them there. Once, and not again however long they stay away.
    suite.test("a request past the mark is announced once, however long it stands") {
        var dispatch = warmedUp()
        let asked = session(asking: now)

        let announced = pass(&dispatch, [asked], at: now.addingTimeInterval(delay + 1))
        suite.expectEqual(announced.count, 1, "the notification at the mark")
        suite.expect(announced.first?.kind == .attention, "got \(String(describing: announced.first?.kind))")

        for minutes in [5.0, 30.0, 120.0] {
            let later = pass(&dispatch, [asked], at: now.addingTimeInterval(minutes * 60))
            suite.expectEqual(later.count, 0, "a second notification \(Int(minutes)) minutes in")
        }
    }

    // A wait is scoped by the moment it began, so the next one is a scope of its own and
    // nothing has to notice the answer for the memory to reset.
    suite.test("the person answered and the agent asked again: the second wait is announced too") {
        var dispatch = warmedUp()
        let first = now
        _ = pass(&dispatch, [session(asking: first)], at: first.addingTimeInterval(delay + 1))

        // Answered: nobody is waiting on the person, and the agent is at work again.
        let working = now.addingTimeInterval(600)
        suite.expectEqual(pass(&dispatch, [session()], at: working).count, 0, "the answer itself")

        let second = working.addingTimeInterval(60)
        let again = pass(&dispatch, [session(asking: second)], at: second.addingTimeInterval(delay + 1))
        suite.expectEqual(again.count, 1, "the second wait")
    }

    // The bar says the turn ended by going steady, and that is all it is worth. This is the
    // line between "the agent finished" and "the agent is waiting on you", and the whole
    // reason the state is read from the session record rather than guessed from a transcript.
    suite.test("the end of a turn without a request never notifies") {
        for wait in [ReplyWait.none, .waiting, .stalled] {
            var dispatch = AlertDispatch()
            let idle = SessionSnapshot(
                sessionID: "a",
                service: .claude,
                contextTokens: 40_000,
                contextWindowTokens: 200_000,
                project: "llm-inform-bureau",
                lastActivityAt: now,
                replyWait: wait
            )
            _ = pass(&dispatch, [idle], at: now)
            let later = pass(&dispatch, [idle], at: now.addingTimeInterval(3600))
            suite.expectEqual(later.count, 0, "notifications for \(wait)")
        }
    }

    // The same rule every other mark of an agent's follows: it runs for minutes and ends by
    // itself, and an agent asks the person nothing that outlives it.
    suite.test("a subagent's request is not announced") {
        var dispatch = warmedUp([session(), session("agent", subagentOf: "a")])
        let asked = pass(
            &dispatch,
            [session(), session("agent", asking: now, subagentOf: "a")],
            at: now.addingTimeInterval(delay + 1)
        )
        suite.expectEqual(asked.count, 0, "notifications on behalf of a subagent")
    }

    // The app is started at login and finds whatever is already on screen. A question asked
    // before it was watching is one the person is already looking at.
    suite.test("a request found on the first pass is recorded rather than announced") {
        var dispatch = AlertDispatch()
        let asked = session(asking: now)
        let first = pass(&dispatch, [asked], at: now.addingTimeInterval(delay + 1))
        suite.expectEqual(first.count, 0, "notifications on the first pass")

        let second = pass(&dispatch, [asked], at: now.addingTimeInterval(delay + 2))
        suite.expectEqual(second.count, 0, "the same wait on the next pass")
    }

    /// What one wait is announced as, in the words the person reads.
    func announcement(
        about asked: String?,
        for what: Asking = .question,
        project: String? = "llm-inform-bureau"
    ) -> NotificationText? {
        var dispatch = warmedUp()
        let announced = pass(
            &dispatch,
            [session(asking: now, asked: what, about: asked, project: project)],
            at: now.addingTimeInterval(delay + 1)
        )
        guard let alert = announced.first else {
            suite.expect(false, "nothing was announced")
            return nil
        }
        return AlertPhrasing.text(for: alert, config: config, now: now)
    }

    // What the notification is for: the person is in another window and has to find the
    // session. The panel lists sessions by project, so the project is how it points at a row.
    suite.test("the text names the project and what was asked") {
        guard let said = announcement(about: "Which approach should I take?") else { return }
        suite.expect(
            said.title.holds { $0.contains("llm-inform-bureau") },
            "title without the project: \(said.title.shown)"
        )
        suite.expect(
            said.title.carries(Phrase("waiting on you", "ждёт вашего ответа")),
            "title: \(said.title.shown)"
        )
        // The question is the agent's own words and goes through untranslated, so both sides
        // carry it as it was written.
        suite.expect(
            said.body.holds { $0.contains("Which approach should I take?") },
            "body without the question: \(said.body.shown)"
        )
        // Every other notification ends with a slash command; this one has nothing to send
        // anybody to look up, and a command here would send them away from answering.
        suite.expect(said.body.holds { !$0.contains("/") }, "a command on a request: \(said.body.shown)")
    }

    suite.test("a request whose question was not readable still says who is waiting") {
        guard let said = announcement(about: nil) else { return }
        suite.expect(
            said.title.holds { $0.contains("llm-inform-bureau") },
            "title: \(said.title.shown)"
        )
        suite.expect(said.body.holds { !$0.isEmpty }, "an empty side of the body")
        suite.expect(
            said.body.carries(Phrase("question", "вопрос")),
            "a question unread is still a question: \(said.body.shown)"
        )
    }

    // The PRD's second reason, and the whole of what it asks of the text: a request is called a
    // request. The person reading this in another window has to know there is a yes or a no to
    // give, not merely that something stopped — nothing on disk carries the words of a
    // permission prompt, so naming what it is is all there is to say.
    suite.test("a permission prompt is announced as a request, not as a session that stopped") {
        guard let said = announcement(about: nil, for: .permission) else { return }
        suite.expect(
            said.title.holds { $0.contains("llm-inform-bureau") },
            "title: \(said.title.shown)"
        )
        suite.expect(
            said.body.carries(Phrase("tool", "инструмент")),
            "what is being asked for: \(said.body.shown)"
        )
        suite.expect(
            !said.body.carries(Phrase("has stopped", "остановился")),
            "a request read as a stoppage: \(said.body.shown)"
        )
        suite.expect(said.body.holds { !$0.contains("/") }, "a command on a request: \(said.body.shown)")
    }

    // A request the record did not name keeps the wording every request had before this app
    // could tell them apart: it is true of both and claims nothing that was not read.
    suite.test("a request the record did not name keeps the wording it always had") {
        guard let said = announcement(about: nil, for: .unnamed) else { return }
        suite.expectEqual(
            said.body,
            Phrase("The agent has stopped and is waiting for an answer.", "Агент остановился и ждёт ответа."),
            "the honest fallback"
        )
    }

    suite.test("a session whose project nobody named still says which agent is waiting") {
        guard let said = announcement(about: "Which approach?", project: nil) else { return }
        suite.expect(
            said.title.carries(Phrase("waiting on you", "ждёт вашего ответа")),
            "title: \(said.title.shown)"
        )
        suite.expect(
            said.title.holds { $0.contains(AgentService.claude.shortLabel) },
            "title: \(said.title.shown)"
        )
    }

    // A question is written for a terminal: it arrives with line breaks in it and it can run
    // for a paragraph. A banner shows neither.
    suite.test("a long question is cut to one line rather than shown whole") {
        guard let wrapped = announcement(about: "Which one?\nThe first\nor the second?") else { return }
        suite.expectEqual(wrapped.body, Phrase.name("Which one? The first or the second?"), "the line breaks")

        let long = "Should I " + String(repeating: "keep going and ", count: 40) + "stop?"
        guard let cut = announcement(about: long) else { return }
        suite.expect(cut.body.holds { $0.count < long.count }, "the whole paragraph went into a banner")
        suite.expect(
            cut.body.holds { $0.hasSuffix("…") },
            "a cut question must not read as the whole of it: \(cut.body.shown)"
        )
        suite.expect(cut.body.holds { !$0.contains("  ") }, "the words ran together: \(cut.body.shown)")
    }
}
