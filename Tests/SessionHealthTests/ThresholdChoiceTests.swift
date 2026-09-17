import Foundation
import Phrasing
import SessionHealthCore

/// Moving a mark: the arithmetic of the bar, what is kept when somebody moves one, and what
/// the app runs on afterwards.
///
/// The bar is drawn by a view nothing here can see, which is exactly why the rule it obeys
/// lives in a type: a mark that slips past its neighbour, or a choice that turns out to be a
/// copy of the whole config, are both failures nobody would notice by looking at the window.
func runThresholdChoiceTests(_ suite: TestSuite, config: ThresholdConfig) {
    let shipped = MarkScale(of: config.limitUsage)

    // MARK: Where a mark is, and where it goes

    suite.test("a point along the bar is the percentage under it") {
        suite.expectClose(MarkScale.percent(atOffset: 0, width: 200), 0, "the left end")
        suite.expectClose(MarkScale.percent(atOffset: 100, width: 200), 50, "the middle")
        suite.expectClose(MarkScale.percent(atOffset: 200, width: 200), 100, "the right end")
        // Off the ends of the bar is the end of the scale: a drag does not stop at the frame.
        suite.expectClose(MarkScale.percent(atOffset: -40, width: 200), 0, "past the left end")
        suite.expectClose(MarkScale.percent(atOffset: 900, width: 200), 100, "past the right end")
        // Whole percentages only, because that is what the number beside the handle says.
        suite.expectClose(MarkScale.percent(atOffset: 101, width: 200), 51, "rounded to a whole percentage")
        // A bar of no width is a window mid-layout, not a reason to divide by zero.
        suite.expectClose(MarkScale.percent(atOffset: 40, width: 0), 0, "a bar with no width")
    }

    suite.test("a percentage is a point along the bar") {
        suite.expectClose(MarkScale.offset(ofPercent: 0, width: 200), 0, "the bottom of the scale")
        suite.expectClose(MarkScale.offset(ofPercent: 50, width: 200), 100, "the middle")
        suite.expectClose(MarkScale.offset(ofPercent: 100, width: 200), 200, "the top")
        suite.expectClose(shipped.offset(of: .high, width: 200), shipped.high * 2, "the red mark")
        suite.expectClose(MarkScale.offset(ofPercent: 50, width: 0), 0, "a bar with no width")
    }

    suite.test("a mark stops at its neighbour instead of passing through it") {
        let up = shipped.moving(.notice, to: 99)
        suite.expectClose(up.notice, shipped.elevated - MarkScale.gap, "the yellow mark under the orange one")
        suite.expectClose(up.elevated, shipped.elevated, "the orange mark did not move")
        suite.expectClose(up.high, shipped.high, "the red mark did not move")

        let down = shipped.moving(.high, to: 2)
        suite.expectClose(down.high, shipped.elevated + MarkScale.gap, "the red mark over the orange one")
        suite.expectClose(down.elevated, shipped.elevated, "the orange mark did not move")

        let middle = shipped.moving(.elevated, to: 0)
        suite.expectClose(middle.elevated, shipped.notice + MarkScale.gap, "the orange mark over the yellow one")
    }

    suite.test("a mark stops at the ends of the bar") {
        suite.expectClose(shipped.moving(.notice, to: -80).notice, MarkScale.gap, "below the bottom")
        suite.expectClose(shipped.moving(.high, to: 400).high, MarkScale.highest, "above the top")
    }

    suite.test("the arrow keys land a mark on an exact whole number") {
        let nudged = shipped.nudging(.elevated, by: 1)
        suite.expectClose(nudged.elevated, shipped.elevated + 1, "one step up")
        suite.expectClose(nudged.nudging(.elevated, by: -1).elevated, shipped.elevated, "and back")
        // From anywhere: a mark left on a fraction by an older file walks onto whole numbers.
        let odd = MarkScale(notice: 20.4, elevated: 60, high: 90)
        suite.expectClose(odd?.nudging(.notice, by: 1).notice, 21, "from a fraction to a whole number")
    }

    suite.test("three numbers that are not a scale do not make one") {
        suite.expect(MarkScale(notice: 60, elevated: 40, high: 90) == nil, "out of order")
        suite.expect(MarkScale(notice: 0, elevated: 40, high: 90) == nil, "a mark at zero")
        suite.expect(MarkScale(notice: 40, elevated: 60, high: 140) == nil, "a mark past 100")
        suite.expect(MarkScale(notice: 40, elevated: 40, high: 90) == nil, "two marks on one number")
        suite.expect(
            MarkScale(notice: config.limitUsage.notice, elevated: config.limitUsage.elevated, high: config.limitUsage.high) != nil,
            "the marks the app ships with are a scale"
        )
    }

    // The parser lets an ordered pair a fraction apart through, and two handles on one point
    // cannot be told apart, let alone taken hold of. Drawing them apart beats refusing to draw.
    suite.test("marks too close together to draw are pushed apart rather than refused") {
        let tight = MarkScale(of: PercentMarks(
            notice: 40, elevated: 40.4, high: 40.6, rationale: "Test fixture.", provenance: nil
        ))
        suite.expect(tight.elevated >= tight.notice + MarkScale.gap, "the orange mark: \(tight)")
        suite.expect(tight.high >= tight.elevated + MarkScale.gap, "the red mark: \(tight)")
        suite.expect(tight.high <= MarkScale.highest, "still inside the scale: \(tight)")
    }

    // MARK: What is kept

    suite.test("what is kept is the choice, not a copy of what the app shipped") {
        guard let chosen = MarkScale(notice: 25, elevated: 45, high: 85) else {
            suite.expect(false, "the fixture is not a scale")
            return
        }
        let choices = ThresholdChoices().choosing(.limitUsage, chosen)

        let overShipped = choices.applied(to: config)
        suite.expectClose(overShipped.limitUsage.notice, 25, "the chosen yellow mark")
        suite.expectClose(overShipped.limitUsage.elevated, 45, "the chosen orange mark")
        suite.expectClose(overShipped.limitUsage.high, 85, "the chosen red mark")

        // The same choice against a later release of the app: everything nobody moved arrives
        // new, and the one mark they did moved nowhere. This is the whole reason a choice is
        // stored rather than a copy of the file.
        let later = ThresholdConfig(
            version: config.version,
            windowFill: PercentMarks(notice: 11, elevated: 22, high: 33, rationale: "A later release.", provenance: nil),
            limitUsage: PercentMarks(notice: 12, elevated: 24, high: 36, rationale: "A later release.", provenance: nil),
            limitWindowNearlyReset: WindowResetThreshold(remainingSharePercent: 7, rationale: "A later release.", provenance: nil),
            sessionActivity: DurationThreshold(minutes: 45, rationale: "A later release.", provenance: nil),
            abandonedWait: DurationThreshold(minutes: 15, rationale: "A later release.", provenance: nil),
            attentionNotice: DurationThreshold(minutes: 3, rationale: "A later release.", provenance: nil)
        )
        let overLater = choices.applied(to: later)
        suite.expectClose(overLater.limitUsage.notice, 25, "the chosen mark is still theirs")
        suite.expectEqual(overLater.windowFill, later.windowFill, "the context marks came with the release")
        suite.expectEqual(overLater.sessionActivity, later.sessionActivity, "the session window came with the release")
        suite.expectEqual(overLater.limitWindowNearlyReset, later.limitWindowNearlyReset, "the reset mark came with the release")
    }

    suite.test("a moved mark loses the rationale that was written about another number") {
        guard let chosen = MarkScale(notice: 25, elevated: 45, high: 85) else {
            suite.expect(false, "the fixture is not a scale")
            return
        }
        let applied = ThresholdChoices().choosing(.limitUsage, chosen).applied(to: config)
        suite.expectEqual(applied.limitUsage.isChosen, true, "isChosen")
        suite.expectEqual(applied.limitUsage.isMeasured, false, "a chosen mark is not a measured one")
        suite.expect(
            applied.limitUsage.rationale != config.limitUsage.rationale,
            "the shipped sentence must not stand under somebody else's number"
        )
        suite.expectEqual(applied.windowFill, config.windowFill, "a mark nobody touched keeps everything")

        // And the window says so rather than repeating what the app measured for a mark that
        // is no longer there.
        guard let note = Briefing.marks(of: applied).first(where: { $0.mark == .limitUsage }) else {
            suite.expect(false, "the limit mark is missing from the window")
            return
        }
        // Nothing is said under it, and that is the point: the sentence that shipped was about
        // the number the app chose, and the reader's own number needs no defending.
        suite.expectEqual(note.note, "", "nothing may stand under a moved mark")
        suite.expect(note.source == nil, "a moved mark has no published source to link to")
    }

    // MARK: Marks that are one number

    suite.test("a number of minutes outside what a mark may be is not a mark") {
        suite.expect(MinuteMark.value(0) == nil, "a mark of no minutes at all")
        suite.expect(MinuteMark.value(-5) == nil, "a mark of less than none")
        suite.expect(MinuteMark.value(MinuteMark.allowed.upperBound + 1) == nil, "past the ceiling")
        suite.expectEqual(MinuteMark.value(10), 10, "an ordinary mark")
        suite.expectEqual(MinuteMark.clamped(0), MinuteMark.allowed.lowerBound, "walked up to the floor")
        suite.expectEqual(MinuteMark.clamped(99999), MinuteMark.allowed.upperBound, "walked back to the ceiling")
        for mark in ThresholdMark.minutes {
            guard let shipped = config.duration(of: mark) else {
                suite.expect(false, "\(mark.rawValue) is not a duration in the config")
                continue
            }
            suite.expect(
                MinuteMark.value(shipped.minutes) != nil,
                "\(mark.rawValue): the app ships a number its own field would refuse — \(shipped.minutes)"
            )
        }
    }

    suite.test("a number nobody may choose is not written down as a choice") {
        let refused = ThresholdChoices().choosing(.abandonedWait, minutes: 0)
        suite.expect(refused.isEmpty, "nought minutes is not a mark")
        suite.expect(
            ThresholdChoices().choosing(.attentionNotice, minutes: 100_000).isEmpty,
            "a number past the ceiling is not a mark"
        )
        suite.expectEqual(
            ThresholdChoices().choosing(.abandonedWait, minutes: 25).minutes(of: .abandonedWait),
            25,
            "an ordinary number is"
        )
    }

    suite.test("a chosen number of minutes is what the rules compare against") {
        let applied = ThresholdChoices()
            .choosing(.abandonedWait, minutes: 25)
            .applied(to: config)
        suite.expectEqual(applied.abandonedWait.minutes, 25, "the chosen wait")
        suite.expectEqual(applied.abandonedWait.isChosen, true, "the window can say who chose it")
        suite.expectEqual(applied.abandonedWait.isMeasured, false, "a chosen number is not a measured one")
        suite.expect(
            applied.abandonedWait.rationale != config.abandonedWait.rationale,
            "the shipped sentence must not stand under somebody else's number"
        )
        suite.expectEqual(applied.attentionNotice, config.attentionNotice, "a mark nobody touched keeps everything")
        suite.expectEqual(applied.sessionActivity, config.sessionActivity, "and so does the other one")

        // The window says nothing under it either, the same as for a moved scale.
        guard let note = Briefing.marks(of: applied).first(where: { $0.mark == .abandonedWait }) else {
            suite.expect(false, "the wait is missing from the window")
            return
        }
        suite.expectEqual(note.note, "", "nothing may stand under a chosen number")
    }

    suite.test("one number chosen leaves the rest to arrive with the next release") {
        let choices = ThresholdChoices()
            .choosing(.attentionNotice, minutes: 5)
            .choosing(.windowFill, MarkScale(notice: 25, elevated: 45, high: 85) ?? MarkScale(of: config.windowFill))
        let later = ThresholdConfig(
            version: config.version,
            windowFill: PercentMarks(notice: 11, elevated: 22, high: 33, rationale: "A later release.", provenance: nil),
            limitUsage: PercentMarks(notice: 12, elevated: 24, high: 36, rationale: "A later release.", provenance: nil),
            limitWindowNearlyReset: WindowResetThreshold(remainingSharePercent: 7, rationale: "A later release.", provenance: nil),
            sessionActivity: DurationThreshold(minutes: 45, rationale: "A later release.", provenance: nil),
            abandonedWait: DurationThreshold(minutes: 15, rationale: "A later release.", provenance: nil),
            attentionNotice: DurationThreshold(minutes: 3, rationale: "A later release.", provenance: nil)
        )
        let applied = choices.applied(to: later)
        suite.expectEqual(applied.attentionNotice.minutes, 5, "the number they chose is still theirs")
        suite.expectClose(applied.windowFill.notice, 25, "and so is the scale they moved")
        suite.expectEqual(applied.abandonedWait, later.abandonedWait, "the wait came with the release")
        suite.expectEqual(applied.sessionActivity, later.sessionActivity, "the session window came with the release")
        suite.expectEqual(applied.limitUsage, later.limitUsage, "the limit scale came with the release")
    }

    // MARK: On disk

    withTemporaryDirectory(suite, named: "threshold-choices") { directory in
        let url = ThresholdChoicesStore.url(in: directory)

        suite.test("a choice comes back the way it was written") {
            guard let chosen = MarkScale(notice: 30, elevated: 55, high: 80) else {
                suite.expect(false, "the fixture is not a scale")
                return
            }
            suite.expect(ThresholdChoicesStore.write(ThresholdChoices().choosing(.limitUsage, chosen), to: url), "written")
            suite.expectEqual(ThresholdChoicesStore.read(at: url).scale(of: .limitUsage), chosen, "read back")
            suite.expect(ThresholdChoicesStore.read(at: url).scale(of: .windowFill) == nil, "nothing was chosen for the context")
        }

        suite.test("choosing a second mark leaves the first one alone") {
            guard
                let limits = MarkScale(notice: 30, elevated: 55, high: 80),
                let context = MarkScale(notice: 20, elevated: 50, high: 70)
            else {
                suite.expect(false, "the fixtures are not scales")
                return
            }
            ThresholdChoicesStore.write(ThresholdChoices().choosing(.limitUsage, limits), to: url)
            let both = ThresholdChoicesStore.read(at: url).choosing(.windowFill, context)
            ThresholdChoicesStore.write(both, to: url)
            let readBack = ThresholdChoicesStore.read(at: url)
            suite.expectEqual(readBack.scale(of: .limitUsage), limits, "the limit marks")
            suite.expectEqual(readBack.scale(of: .windowFill), context, "the context marks")
        }

        suite.test("nothing chosen leaves no file behind") {
            guard let chosen = MarkScale(notice: 30, elevated: 55, high: 80) else {
                suite.expect(false, "the fixture is not a scale")
                return
            }
            ThresholdChoicesStore.write(ThresholdChoices().choosing(.limitUsage, chosen), to: url)
            suite.expect(ThresholdChoicesStore.write(ThresholdChoices(), to: url), "written")
            suite.expect(
                !FileManager.default.fileExists(atPath: url.path),
                "a file with no choices in it would be read by a later release"
            )
            suite.expect(ThresholdChoicesStore.read(at: url).isEmpty, "nothing chosen")
        }

        suite.test("a file this release cannot read means the marks the app ships with") {
            for (name, contents) in [
                ("not JSON at all", "{{{ not json"),
                ("a format from another release", "{\"version\": 99, \"scales\": {\"limits.percent\": {\"notice\": 30, \"elevated\": 55, \"high\": 80}}}"),
                ("no version at all", "{\"scales\": {\"limits.percent\": {\"notice\": 30, \"elevated\": 55, \"high\": 80}}}"),
                ("a mark that is not a number", "{\"version\": 1, \"scales\": {\"limits.percent\": {\"notice\": \"thirty\", \"elevated\": 55, \"high\": 80}}}")
            ] {
                writeText(contents, to: url, suite)
                suite.expect(ThresholdChoicesStore.read(at: url).isEmpty, "\(name): nothing should be chosen")
            }
            removeFile(url, suite)
            suite.expect(ThresholdChoicesStore.read(at: url).isEmpty, "no file at all: nothing chosen")
        }

        // The same rule the config file is held to. A record out of order is not applied
        // backwards and not repaired into something nobody chose: the mark goes back to where
        // the app put it, which is a state the window shows plainly.
        suite.test("a record that is not a scale gives way to the marks the app ships with") {
            writeText(
                "{\"version\": 1, \"scales\": {\"limits.percent\": {\"notice\": 80, \"elevated\": 55, \"high\": 30}}}",
                to: url,
                suite
            )
            suite.expect(ThresholdChoicesStore.read(at: url).isEmpty, "an unordered scale is no choice")
        }

        suite.test("a chosen number comes back the way it was written") {
            let choices = ThresholdChoices()
                .choosing(.abandonedWait, minutes: 25)
                .choosing(.sessionActivity, minutes: 60)
            suite.expect(ThresholdChoicesStore.write(choices, to: url), "written")
            let readBack = ThresholdChoicesStore.read(at: url)
            suite.expectEqual(readBack.minutes(of: .abandonedWait), 25, "the wait")
            suite.expectEqual(readBack.minutes(of: .sessionActivity), 60, "the session window")
            suite.expect(readBack.minutes(of: .attentionNotice) == nil, "nothing was chosen for the notice")
            suite.expect(readBack.scale(of: .limitUsage) == nil, "and no scale was moved")
        }

        // Both kinds live in one file, and a person moving a scale must not cost themselves the
        // number they typed an hour earlier.
        suite.test("a moved scale and a typed number keep each other's company") {
            guard let scale = MarkScale(notice: 30, elevated: 55, high: 80) else {
                suite.expect(false, "the fixture is not a scale")
                return
            }
            ThresholdChoicesStore.write(ThresholdChoices().choosing(.abandonedWait, minutes: 25), to: url)
            ThresholdChoicesStore.write(ThresholdChoicesStore.read(at: url).choosing(.limitUsage, scale), to: url)
            let readBack = ThresholdChoicesStore.read(at: url)
            suite.expectEqual(readBack.minutes(of: .abandonedWait), 25, "the number")
            suite.expectEqual(readBack.scale(of: .limitUsage), scale, "the scale")
        }

        // The same rule the field in the window is held to, held on the way back in: a record
        // the app could never have written is no choice at all.
        suite.test("a number of minutes no mark may take gives way to the one the app ships") {
            for (name, contents) in [
                ("nought minutes", "{\"version\": 1, \"minutes\": {\"sessions.abandoned_wait_after_minutes\": 0}}"),
                ("a negative number", "{\"version\": 1, \"minutes\": {\"sessions.abandoned_wait_after_minutes\": -10}}"),
                ("past the ceiling", "{\"version\": 1, \"minutes\": {\"sessions.abandoned_wait_after_minutes\": 100000}}"),
                ("half a minute", "{\"version\": 1, \"minutes\": {\"sessions.abandoned_wait_after_minutes\": 10.5}}"),
                ("not a number", "{\"version\": 1, \"minutes\": {\"sessions.abandoned_wait_after_minutes\": \"ten\"}}")
            ] {
                writeText(contents, to: url, suite)
                suite.expect(ThresholdChoicesStore.read(at: url).isEmpty, "\(name): nothing should be chosen")
                suite.expectEqual(
                    ThresholdConfigLoader.load(choicesAt: url).config.abandonedWait,
                    config.abandonedWait,
                    "\(name): the app runs on its own number"
                )
            }
        }

        // A file written before the one-number marks existed. The version says what a record
        // means, and nothing about the scales changed when the minutes arrived beside them.
        suite.test("a file written before there were numbers in it still carries its scale") {
            writeText(
                "{\"version\": 1, \"scales\": {\"limits.percent\": {\"notice\": 30, \"elevated\": 55, \"high\": 80}}}",
                to: url,
                suite
            )
            let readBack = ThresholdChoicesStore.read(at: url)
            suite.expectEqual(readBack.scale(of: .limitUsage)?.elevated, 55, "the scale that was chosen then")
            suite.expect(readBack.minutes.isEmpty, "and nothing was chosen that could not be")
        }

        suite.test("a chosen number on disk is what the app runs on") {
            ThresholdChoicesStore.write(ThresholdChoices().choosing(.attentionNotice, minutes: 5), to: url)
            let load = ThresholdConfigLoader.load(choicesAt: url)
            suite.expectEqual(load.config.attentionNotice.minutes, 5, "the chosen delay")
            suite.expectEqual(load.config.attentionNotice.isChosen, true, "the window can say who chose it")
            suite.expectEqual(load.config.abandonedWait, config.abandonedWait, "the marks nobody touched")
            suite.expectEqual(load.shipped, config, "what putting it back goes back to")
        }

        suite.test("putting a number back leaves no choice behind either") {
            ThresholdChoicesStore.write(ThresholdChoices().choosing(.abandonedWait, minutes: 25), to: url)
            let back = ThresholdChoicesStore.read(at: url).forgetting(.abandonedWait)
            ThresholdChoicesStore.write(back, to: url)
            suite.expect(ThresholdChoicesStore.read(at: url).isEmpty, "nothing is chosen any more")
            suite.expect(
                !FileManager.default.fileExists(atPath: url.path),
                "the shipped number must not be written down as a choice of its own"
            )
            suite.expectEqual(
                ThresholdConfigLoader.load(choicesAt: url).config,
                config,
                "the app is back on its own marks"
            )
        }

        suite.test("putting a mark back leaves no choice behind, on disk or in the marks") {
            guard let chosen = MarkScale(notice: 30, elevated: 55, high: 80) else {
                suite.expect(false, "the fixture is not a scale")
                return
            }
            ThresholdChoicesStore.write(ThresholdChoices().choosing(.limitUsage, chosen), to: url)
            let back = ThresholdChoicesStore.read(at: url).forgetting(.limitUsage)
            ThresholdChoicesStore.write(back, to: url)
            suite.expect(ThresholdChoicesStore.read(at: url).isEmpty, "nothing is chosen any more")
            suite.expect(
                !FileManager.default.fileExists(atPath: url.path),
                "the shipped numbers must not be written down as a choice of their own"
            )
            suite.expectEqual(
                ThresholdConfigLoader.load(choicesAt: url).config,
                config,
                "the app is back on its own marks"
            )
        }

        // MARK: What the app runs on

        suite.test("a choice on disk is what the app runs on, over the marks it ships with") {
            guard let chosen = MarkScale(notice: 30, elevated: 55, high: 80) else {
                suite.expect(false, "the fixture is not a scale")
                return
            }
            ThresholdChoicesStore.write(ThresholdChoices().choosing(.limitUsage, chosen), to: url)
            let load = ThresholdConfigLoader.load(choicesAt: url)
            suite.expectClose(load.config.limitUsage.elevated, 55, "the chosen orange mark")
            suite.expectEqual(load.config.limitUsage.isChosen, true, "the window can say who chose it")
            suite.expectEqual(load.config.windowFill, config.windowFill, "the marks nobody moved")
            suite.expectEqual(load.source, .bundled, "the file the numbers came from is still the app's")
            suite.expectEqual(load.problems.count, 0, "problems: \(load.problems)")
            // What "Reset to default" needs, and what a window holding the merged config
            // cannot work out for itself.
            suite.expectEqual(load.shipped, config, "the marks the app would run on by itself")
        }

        suite.test("with nothing chosen the app runs on the marks it ships with") {
            ThresholdChoicesStore.write(ThresholdChoices(), to: url)
            let load = ThresholdConfigLoader.load(choicesAt: url)
            suite.expectEqual(load.config, config, "the shipped marks")
        }

        // An override is for the tests and for a working copy: half a config from a named file
        // and half from whatever this Mac's owner once moved is not a run anybody asked for.
        suite.test("a run that names a config file reads that file and no choices") {
            guard let chosen = MarkScale(notice: 30, elevated: 55, high: 80) else {
                suite.expect(false, "the fixture is not a scale")
                return
            }
            ThresholdChoicesStore.write(ThresholdChoices().choosing(.limitUsage, chosen), to: url)
            let external = directory.appendingPathComponent("thresholds.json")
            writeText(overrideConfigJSON(), to: external, suite)
            let load = ThresholdConfigLoader.load(at: external, choicesAt: url)
            suite.expectClose(load.config.limitUsage.elevated, 50, "the orange mark from the named file")
            suite.expectEqual(load.config.limitUsage.isChosen, false, "nothing here was chosen")
        }
    }
}

// MARK: Fixtures

/// A whole config of the current version, so a run that names a file gets one.
private func overrideConfigJSON() -> String {
    """
    {
      "version": \(ThresholdConfig.currentVersion),
      "context": {
        "window_fill_percent": {
          "notice": 25, "elevated": 50, "high": 75,
          "rationale": "Test fixture.", "measurement": null
        }
      },
      "limits": {
        "percent": {
          "notice": 25, "elevated": 50, "high": 75,
          "rationale": "Test fixture.", "measurement": null
        },
        "quiet_when_window_remaining_percent": {
          "remaining_percent": 5, "rationale": "Test fixture.", "measurement": null
        }
      },
      "sessions": {
        "active_within_minutes": { "minutes": 30, "rationale": "Test fixture.", "measurement": null },
        "abandoned_wait_after_minutes": { "minutes": 10, "rationale": "Test fixture.", "measurement": null },
        "attention_notice_after_minutes": { "minutes": 2, "rationale": "Test fixture.", "measurement": null }
      }
    }
    """
}

private func writeText(_ contents: String, to url: URL, _ suite: TestSuite) {
    do {
        try Data(contents.utf8).write(to: url)
    } catch {
        suite.expect(false, "could not write the fixture: \(error)")
    }
}
