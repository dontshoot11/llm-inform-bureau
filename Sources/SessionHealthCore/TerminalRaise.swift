import Foundation

/// How far a click on a session's row can go towards the window that session is running in.
///
/// **Why this is a rule and not just code at the border.** What a click can do depends on the
/// terminal: two of them can be asked which tab holds which terminal device, and the rest
/// cannot be asked anything at all. That is a fact worth stating in one place, with what it is
/// based on, rather than discovering it inside an `if` in the view — and stating it here is
/// what makes it testable, because the part that actually talks to the system cannot be.
///
/// **The ceiling, per terminal, measured on this machine**
/// (`TODO/session-needs-attention/research.md`, "Чем поднимается терминал сессии"):
///
/// | Terminal | What it gives |
/// | --- | --- |
/// | Terminal.app | the tab: `tty of every tab of every window` answers, measured |
/// | iTerm2 | the tab, by its dictionary — **not measured**, nothing to measure it on here |
/// | everything else — Ghostty, kitty, Alacritty, the terminal inside VS Code or Cursor | no tab API, so the window whose title names the session's project, and the application if none does |
///
/// **Why the third row is not simply "the application".** It was, and it was not enough: a
/// person with four VS Code windows open clicked a session and got whichever window they had
/// used last, which is the one place they already were. A window carries the name of its
/// project in its title, and the panel knows which project the session is in, so there is
/// something to match on — at the price of one permission. See `Permission.accessibility`.
public enum TerminalRaise {
    /// What to do about one session, in order of how close it gets the person to their session.
    public enum Plan: Equatable, Sendable {
        /// Ask the terminal for the tab this session is in, with the script that does it. A
        /// script rather than a terminal to be named again later: whoever runs this does not
        /// have to know which terminal it was written for, and this file stays the only place
        /// that writes AppleScript.
        case tab(script: String)
        /// Look through the application's windows for one whose title carries this text, and
        /// raise that one. The project's name, which is what a window is titled after in every
        /// editor and terminal that titles its windows at all.
        case window(titled: String)
        /// Raise the application and stop there — its own window is all it can offer.
        case app
        /// There is nothing to raise. No process, or a process nothing owns.
        case nothing
    }

    /// What the system may ask a person for on the way, and where the answer is kept.
    ///
    /// Both are asked for by the click and never in advance, and neither is needed for the
    /// floor: raising an application is not anybody's private business. A refusal of either
    /// costs the precision, not the click.
    public enum Permission: Equatable, Sendable {
        /// Controlling another application, which is what asking a terminal about its tabs is.
        /// The system asks with a dialog the first time, and the answer lives under Privacy &
        /// Security → Automation.
        case automation
        /// Looking through another application's windows, which is what matching a title
        /// means. A heavier answer than the one above — it is given by hand in Privacy &
        /// Security → Accessibility, and a dialog can only offer to open that pane. Measured:
        /// without it the attempt comes back "not allowed assistive access".
        case accessibility
    }

    /// The terminals that can be asked which tab a terminal device belongs to, by bundle
    /// identifier.
    ///
    /// Two, and adding a third means finding out that it answers rather than hoping: a
    /// terminal listed here that cannot answer costs a person a permission dialog and gives
    /// them the application they would have got anyway.
    static let terminalApp = "com.apple.Terminal"
    static let iTerm = "com.googlecode.iterm2"

    /// What a click on this session can do.
    ///
    /// - Parameters:
    ///   - owner: bundle identifier of the application that started the session's process, or
    ///     `nil` when the process has no application above it at all.
    ///   - tty: the name of its terminal device, as the kernel gives it — `ttys001`, no
    ///     `/dev/`. `nil` for a process with no controlling terminal, which has no tab to look
    ///     for however capable its terminal is.
    ///   - project: the session's project, as the panel names it. `nil` when the source never
    ///     said, and then there is nothing to recognise a window by.
    public static func plan(owner: String?, tty: String?, project: String? = nil) -> Plan {
        guard let owner else { return .nothing }
        if let tty, let script = script(owner: owner, tty: tty) { return .tab(script: script) }
        // A blank project name is the same as none: every title contains an empty string, so
        // matching on one would raise whichever window came back first and call it the answer.
        if let project, !project.trimmingCharacters(in: .whitespaces).isEmpty {
            return .window(titled: project)
        }
        return .app
    }

    /// The AppleScript that selects the tab holding `tty` and brings it forward, or `nil` for
    /// a terminal that cannot be asked.
    ///
    /// Both scripts end in `activate` rather than starting with it: selecting the tab first
    /// and raising the window after means a refused permission leaves the screen exactly as it
    /// was instead of a raised window on the wrong tab.
    static func script(owner: String, tty: String) -> String? {
        let device = "/dev/\(tty)"
        switch owner {
        case terminalApp:
            // Measured: this is the script that raised a live tab of Terminal.app by its tty.
            return """
                tell application id "\(terminalApp)"
                  repeat with w in windows
                    repeat with t in tabs of w
                      if tty of t is "\(device)" then
                        set selected of t to true
                        set frontmost of w to true
                        activate
                        return "raised"
                      end if
                    end repeat
                  end repeat
                  return "no tab"
                end tell
                """
        case iTerm:
            // From iTerm2's dictionary, where a `session` is the thing with a `tty` and the
            // three `select`s are how one is brought forward. Not measured — iTerm2 is not on
            // the machine this was written on — and written so that being wrong costs nothing:
            // a script that fails is a script that raised no tab, and the caller falls back to
            // the application either way.
            return """
                tell application id "\(iTerm)"
                  repeat with w in windows
                    repeat with t in tabs of w
                      repeat with s in sessions of t
                        if tty of s is "\(device)" then
                          select w
                          select t
                          select s
                          activate
                          return "raised"
                        end if
                      end repeat
                    end repeat
                  end repeat
                  return "no tab"
                end tell
                """
        default:
            return nil
        }
    }
}
