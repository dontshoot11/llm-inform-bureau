import Foundation
import SessionHealthCore

/// The config is data the app trusts, so these cases check the shipped file itself as much as
/// the code that reads it — and, above all, that a broken file degrades to working defaults
/// with an explanation instead of taking the menu bar down.
func runThresholdConfigTests(_ suite: TestSuite, config: ThresholdConfig) {
    suite.test("the bundled config is the format this app reads") {
        suite.expectEqual(config.version, ThresholdConfig.currentVersion, "version")
    }

    suite.test("the bundled config and the built-in values have not drifted apart") {
        suite.expectEqual(config, ThresholdConfig.builtIn, "bundled config")
    }

    suite.test("every number explains itself, and every measured one names a dated source") {
        let measured: [(String, ThresholdProvenance?, String)] = [
            ("context.window_fill_percent", config.windowFill.provenance, config.windowFill.rationale),
            ("limits.percent", config.limitUsage.provenance, config.limitUsage.rationale),
            ("limits.quiet_when_window_remaining_percent", config.limitWindowNearlyReset.provenance, config.limitWindowNearlyReset.rationale),
            ("sessions.active_within_minutes", config.sessionActivity.provenance, config.sessionActivity.rationale),
            ("sessions.abandoned_wait_after_minutes", config.abandonedWait.provenance, config.abandonedWait.rationale),
            ("sessions.attention_notice_after_minutes", config.attentionNotice.provenance, config.attentionNotice.rationale)
        ]
        for (path, provenance, rationale) in measured {
            suite.expect(!rationale.isEmpty, "\(path): a number without a rationale is a guess")
            guard let provenance else { continue }
            suite.expectEqual(provenance.measuredAt.count, 10, "\(path): measured_at must be YYYY-MM-DD")
            suite.expectEqual(provenance.source.scheme, "https", "\(path): source scheme")
        }
    }

    // Every mark in this config is ours. Nothing published says where a context stops being
    // workable, so a `measurement` on any of them would be an invented source — the one lie
    // nothing downstream could catch.
    suite.test("no mark claims a source, because no vendor published one") {
        suite.expectEqual(config.windowFill.isMeasured, false, "the window-fill marks")
        suite.expectEqual(config.limitUsage.isMeasured, false, "the limit marks")
        suite.expectEqual(config.limitWindowNearlyReset.isMeasured, false, "the reset mark")
        suite.expectEqual(config.sessionActivity.isMeasured, false, "the session-activity window")
        // Waits were counted here to place this one, and counting them here is exactly why it
        // ships unmeasured: one machine's sessions are not the sessions it will be read on.
        suite.expectEqual(config.abandonedWait.isMeasured, false, "the abandoned-wait fuse")
        // Waits on the *person* were counted here too — a median of 64 seconds over 215 of
        // them — and for the same reason that count is in the research and not in the file.
        suite.expectEqual(config.attentionNotice.isMeasured, false, "the notice delay")
    }

    // The red mark is the one number placed against something published, and the rationale is
    // where that fact lives. A mark whose reasoning stops at "it seemed right" is the thing
    // this project keeps trying to avoid.
    suite.test("the red context mark says what published fact it was placed against") {
        suite.expect(
            config.windowFill.rationale.contains("967K"),
            "the window-fill rationale must name the compaction point it sits below: \(config.windowFill.rationale)"
        )
    }

    suite.test("both scales run 0-100 in order, and they are the same scale") {
        for (path, marks) in [("context.window_fill_percent", config.windowFill), ("limits.percent", config.limitUsage)] {
            suite.expect(marks.notice > 0, "\(path): the lowest mark must be positive")
            suite.expect(marks.elevated > marks.notice, "\(path): \(marks.elevated) must be above \(marks.notice)")
            suite.expect(marks.high > marks.elevated, "\(path): \(marks.high) must be above \(marks.elevated)")
            suite.expect(marks.high <= 100, "\(path): \(marks.high) must be a percentage")
        }
        suite.expectEqual(config.limitUsage.notice, config.windowFill.notice, "the notice mark of both lights")
        suite.expectEqual(config.limitUsage.elevated, config.windowFill.elevated, "the elevated mark of both lights")
        suite.expectEqual(config.limitUsage.high, config.windowFill.high, "the high mark of both lights")
    }

    suite.test("the marks are exclusive: sitting exactly on one has not crossed it") {
        let fill = config.windowFill
        suite.expectEqual(fill.level(for: fill.notice), .normal, "at the notice mark")
        suite.expectEqual(fill.level(for: fill.notice + 0.1), .notice, "just past it")
        suite.expectEqual(fill.level(for: fill.elevated), .notice, "at the elevated mark")
        suite.expectEqual(fill.level(for: fill.elevated + 0.1), .elevated, "just past it")
        suite.expectEqual(fill.level(for: fill.high), .elevated, "at the high mark")
        suite.expectEqual(fill.level(for: fill.high + 0.1), .high, "just past it")
    }

    // The notice mark colours a light and never speaks. It is the only mark with that shape,
    // so it is the only one that can be lost silently in a later edit.
    suite.test("the notice mark colours a light and never notifies") {
        let fill = config.windowFill
        suite.expectEqual(fill.crossed(by: fill.notice + 1).count, 0, "nothing to say yet")
        suite.expectEqual(fill.crossed(by: fill.elevated + 1), [fill.elevated], "the elevated mark alone")
        suite.expectEqual(fill.crossed(by: fill.high + 1), [fill.elevated, fill.high], "both speaking marks")
        suite.expectEqual(fill.mark(for: .notice), fill.notice, "the notice level names its own mark")
    }

    // The marks are the app's own: nothing outside it is read unless a run says so in so many
    // words. A machine set up by an older release still has a thresholds.json in Application
    // Support, and this is what makes it a leftover rather than a config.
    suite.test("nothing outside the app is read unless an override names it") {
        suite.expect(
            ThresholdConfigLoader.overrideConfigURL(environment: [:]) == nil,
            "an ordinary run reads no file of its own"
        )
        suite.expect(
            ThresholdConfigLoader.overrideConfigURL(
                environment: [ThresholdConfigLoader.environmentOverrideKey: ""]
            ) == nil,
            "an empty override is no override"
        )
        suite.expectEqual(
            ThresholdConfigLoader.overrideConfigURL(
                environment: [ThresholdConfigLoader.environmentOverrideKey: "/tmp/elsewhere.json"]
            )?.path,
            "/tmp/elsewhere.json",
            "override"
        )
    }

    // And so a copy in Application Support, left behind by the release that had an installer,
    // is a leftover rather than a config: there is no path from here to it to take.
    suite.test("an ordinary run reads the copy the app ships and nothing else") {
        let load = ThresholdConfigLoader.load()
        suite.expectEqual(load.source, .bundled, "source")
        suite.expectEqual(load.config, config, "the marks the app ships with")
        suite.expectEqual(load.problems.count, 0, "problems: \(load.problems)")
    }

    // MARK: Reading it from disk

    withTemporaryDirectory(suite, named: "threshold-config") { directory in
        let external = directory.appendingPathComponent("thresholds.json")

        suite.test("an installed config outside the bundle wins over the bundled copy") {
            write(configJSON(activeMinutes: 11), to: external, suite)
            let load = ThresholdConfigLoader.load(at: external)
            suite.expectEqual(load.source, .external(external), "source")
            suite.expectEqual(load.config.sessionActivity.minutes, 11, "value from the file")
            suite.expectEqual(load.problems.count, 0, "problems: \(load.problems)")
            suite.expectEqual(load.usesFallbackValues, false, "usesFallbackValues")
        }

        suite.test("no installed config means the bundled copy, and that is not a problem") {
            let load = ThresholdConfigLoader.load(at: directory.appendingPathComponent("absent.json"))
            suite.expectEqual(load.source, .bundled, "source")
            suite.expectEqual(load.config, config, "bundled values")
            suite.expectEqual(load.problems.count, 0, "problems: \(load.problems)")
        }

        suite.test("a file that is not JSON leaves the app running on the defaults, and says so") {
            write("not json at all {{{", to: external, suite)
            let load = ThresholdConfigLoader.load(at: external)
            suite.expectEqual(load.config, config, "values")
            suite.expectEqual(load.usesFallbackValues, true, "usesFallbackValues")
            suite.expectEqual(load.problems.count, 1, "problems: \(load.problems)")
        }

        // Silently, and that is the decision: the app installs this file itself, so a release
        // that moves the format would otherwise put a complaint in front of everybody who has
        // never opened it — about marks they have no reason to have an opinion on.
        suite.test("a config in a format this app does not read is ignored whole, and quietly") {
            write(configJSON(version: 99), to: external, suite)
            let load = ThresholdConfigLoader.load(at: external)
            suite.expectEqual(load.config, config, "values")
            suite.expectEqual(load.problems.count, 0, "problems: \(load.problems)")
        }

        suite.test("an incomplete config keeps the values it does have") {
            write(configJSON(activeMinutes: 11, includeWindowFill: false), to: external, suite)
            let load = ThresholdConfigLoader.load(at: external)
            suite.expectEqual(load.config.sessionActivity.minutes, 11, "the value that was there")
            suite.expectEqual(load.config.windowFill, config.windowFill, "the missing one falls back")
            suite.expectEqual(load.problems.count, 1, "problems: \(load.problems)")
            suite.expect(
                load.problems.first?.contains("window_fill_percent") == true,
                "the report must name what was missing: \(load.problems)"
            )
        }

        suite.test("a scale in the wrong order is refused rather than applied backwards") {
            write(configJSON(windowFill: (notice: 30, elevated: 80, high: 20)), to: external, suite)
            let load = ThresholdConfigLoader.load(at: external)
            suite.expectEqual(load.config.windowFill, config.windowFill, "values")
            suite.expect(
                load.problems.first?.contains("window_fill_percent") == true,
                "problems: \(load.problems)"
            )
        }

        suite.test("a number with a broken measurement counts as unmeasured, and says so") {
            write(configJSON(brokenMeasurement: true), to: external, suite)
            let load = ThresholdConfigLoader.load(at: external)
            suite.expectEqual(load.config.windowFill.high, 75, "the numbers are still used")
            suite.expectEqual(load.config.windowFill.isMeasured, false, "isMeasured")
            suite.expectEqual(load.problems.count, 1, "problems: \(load.problems)")
        }

        suite.test("a number without a rationale is used and reported") {
            write(configJSON(includeRationale: false), to: external, suite)
            let load = ThresholdConfigLoader.load(at: external)
            suite.expectEqual(load.config.windowFill.high, 75, "the numbers are still used")
            suite.expect(load.problems.count >= 1, "problems: \(load.problems)")
        }

        // The whole point of the version field: a v3 file read as v4 would silently apply a
        // two-mark scale as a three-mark one. Falling back is what must happen; saying so is
        // not, for the reason above.
        suite.test("the schema this replaces is refused whole, not read in part") {
            write(previousSchemaJSON(), to: external, suite)
            let load = ThresholdConfigLoader.load(at: external)
            suite.expectEqual(load.config, config, "every value falls back")
            suite.expectEqual(load.problems.count, 0, "problems: \(load.problems)")
        }

        // The other half of that decision, and the line between them: a file somebody is
        // editing right now is still reported. Silence there would be the app running on marks
        // other than the ones in front of them.
        suite.test("a file being edited is still reported when it cannot be used as written") {
            write(configJSON(windowFill: (notice: 30, elevated: 80, high: 20)), to: external, suite)
            let load = ThresholdConfigLoader.load(at: external)
            suite.expectEqual(load.usesFallbackValues, true, "usesFallbackValues")
            suite.expect(
                load.problems.first?.contains("window_fill_percent") == true,
                "problems: \(load.problems)"
            )
        }
    }

}

// MARK: Fixtures

/// A valid config of the current version, with one thing at a time knocked out of it.
private func configJSON(
    version: Int = ThresholdConfig.currentVersion,
    activeMinutes: Int = 30,
    windowFill: (notice: Int, elevated: Int, high: Int) = (25, 50, 75),
    includeWindowFill: Bool = true,
    includeRationale: Bool = true,
    brokenMeasurement: Bool = false
) -> String {
    let rationale = includeRationale ? "\"rationale\": \"Test fixture.\"," : ""
    let goodMeasurement = "\"measurement\": {\"measured_at\": \"2026-09-15\", \"source\": \"https://example.org/measurement\"}"
    // Knocked out in one entry only, so the report is expected to name exactly one problem.
    let measurement = brokenMeasurement ? "\"measurement\": {\"measured_at\": \"2026-09-15\"}" : goodMeasurement
    let fill = includeWindowFill
        ? """
          "window_fill_percent": {
            "notice": \(windowFill.notice),
            "elevated": \(windowFill.elevated),
            "high": \(windowFill.high),
            \(rationale)
            \(measurement)
          }
        """
        : ""
    return """
    {
      "version": \(version),
      "context": {
        \(fill)
      },
      "limits": {
        "percent": {
          "notice": 25,
          "elevated": 50,
          "high": 75,
          \(rationale)
          "measurement": null
        },
        "quiet_when_window_remaining_percent": {
          "remaining_percent": 5,
          \(rationale)
          "measurement": null
        }
      },
      "sessions": {
        "active_within_minutes": {
          "minutes": \(activeMinutes),
          \(rationale)
          "measurement": null
        },
        "abandoned_wait_after_minutes": {
          "minutes": 10,
          \(rationale)
          "measurement": null
        },
        "attention_notice_after_minutes": {
          "minutes": 2,
          \(rationale)
          "measurement": null
        }
      }
    }
    """
}

/// The schema this release replaces, kept verbatim: two marks per light and a Claude token
/// mark that no longer exists. Reading it as if it were the current format is the failure the
/// version field is there to prevent.
private func previousSchemaJSON() -> String {
    """
    {
      "version": 3,
      "context": {
        "claude_recommended_tokens": { "tokens": 150000, "rationale": "Old schema." },
        "window_fill_percent": { "elevated": 64, "high": 80, "rationale": "Old schema." },
        "expensive_turn": { "window_share_percent": 10, "tokens_without_window": 20000, "rationale": "Old schema." }
      },
      "limits": {
        "percent": { "elevated": 60, "high": 80, "rationale": "Old schema." }
      },
      "sessions": {
        "active_within_minutes": { "minutes": 30, "rationale": "Old schema." }
      }
    }
    """
}

private func write(_ contents: String, to url: URL, _ suite: TestSuite) {
    do {
        try Data(contents.utf8).write(to: url)
    } catch {
        suite.expect(false, "could not write the fixture: \(error)")
    }
}
