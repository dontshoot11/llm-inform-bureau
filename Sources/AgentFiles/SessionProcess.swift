import Darwin
import Foundation

/// What a running process says about itself: when it started, which terminal it is attached
/// to, and which processes are above it.
///
/// **Why a process is read at all in a module about files.** Everything else here answers a
/// question by opening a file an agent wrote. This one answers the question a file cannot:
/// the session record names a pid, and a pid on its own leads nowhere — the window a person
/// has to be taken to belongs to whatever application started that process, and which
/// terminal it sits in is a property of the process, not of anything on disk.
///
/// **Read from the kernel, not from `ps`.** `proc_pidinfo` is one call and no subprocess,
/// which matters for something a pass over every session may do several times a second; and a
/// shelled-out `ps` would have to be parsed, which is a format to get wrong for no gain.
/// Nothing here goes near the network — `OfflineTests` is watching, and rightly.
///
/// Usage:
/// ```swift
/// let tty = SessionProcess.terminalName(69623)          // "ttys001"
/// let live = SessionProcess.isTheOne(69623, startedAt: recorded)
/// ```
public enum SessionProcess {
    /// How far apart the moment a session record claims and the moment its process actually
    /// started are allowed to be.
    ///
    /// Not a mark: nothing is compared to a reading here and nothing in the interface depends
    /// on it. It is the width of one known lag — the CLI boots and *then* writes its record —
    /// measured at 0.43 s and 0.64 s on the two live sessions of this machine (research,
    /// "Чем поднимается терминал сессии"). Five seconds is that lag with room to spare, and
    /// still far too narrow for the thing it guards against: a pid handed out again later to
    /// some other process, which would have to have started within five seconds of the
    /// session's own start to be mistaken for it.
    static let startTolerance: TimeInterval = 5

    /// Whether this pid is still the process the record was written about.
    ///
    /// Two ways it can be false, and both matter. The process may be gone — then there is no
    /// window to raise and the row must not promise one. Or the number may have been handed
    /// out again to something else entirely, and *that* is the case worth a check rather than
    /// a shrug: raising a window because a pid matched would raise a stranger's.
    public static func isTheOne(_ pid: Int32, startedAt claimed: Date) -> Bool {
        guard let actual = startedAt(pid) else { return false }
        return abs(actual.timeIntervalSince(claimed)) <= startTolerance
    }

    /// When the process behind this pid started, or `nil` when there is no such process.
    public static func startedAt(_ pid: Int32) -> Date? {
        guard let info = info(pid) else { return nil }
        let seconds = Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1_000_000
        return Date(timeIntervalSince1970: seconds)
    }

    /// The name of the terminal device the process is attached to — `ttys001` — or `nil` when
    /// it has none.
    ///
    /// Without the `/dev/` in front, which is how the kernel names it. Terminal.app's
    /// AppleScript compares against the full path, so the prefix belongs to whoever writes
    /// that comparison and not here.
    ///
    /// `nil` is an ordinary answer, not a fault: a process started by something other than a
    /// terminal has no controlling terminal at all, and then there is no tab to look for.
    public static func terminalName(_ pid: Int32) -> String? {
        guard let info = info(pid) else { return nil }
        let device = dev_t(info.e_tdev)
        guard device != 0, device != dev_t.max, let name = devname(device, S_IFCHR) else {
            return nil
        }
        return String(cString: name)
    }

    /// The process and everything that started it, nearest first, up to the top.
    ///
    /// The chain and not just the parent, because the parent is never the answer: measured on
    /// this machine, a session in the terminal of VS Code sits under `zsh`, which sits under
    /// `Code Helper`, which is *not* an application as far as the system is concerned — the
    /// application is one step further up. Whoever walks this list decides where to stop; all
    /// this does is refuse to guess.
    ///
    /// Bounded, because a cycle in the table this reads would otherwise hang a pass: a dozen
    /// steps is several times deeper than any terminal nests.
    public static func ancestors(of pid: Int32, limit: Int = 12) -> [Int32] {
        var walked: [Int32] = []
        var current = pid
        while current > 1, walked.count < limit {
            walked.append(current)
            guard let parent = parent(of: current) else { break }
            current = parent
        }
        return walked
    }

    /// Who started this process, asked in the one form the kernel answers about somebody
    /// else's.
    ///
    /// The short form rather than the full one, and this is not an optimisation — it is the
    /// difference between the walk working and not. A session in Terminal.app sits under
    /// `login`, which belongs to root, and the full `proc_bsdinfo` of a process this app does
    /// not own is refused: the walk stopped one step short of the application and every
    /// Terminal.app session looked like a session nothing owns. Measured on this machine —
    /// `zsh` → `login` → `Terminal` comes back whole in the short form and breaks at `login`
    /// in the long one.
    private static func parent(of pid: Int32) -> Int32? {
        var info = proc_bsdshortinfo()
        let size = Int32(MemoryLayout<proc_bsdshortinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &info, size) == size else { return nil }
        return Int32(info.pbsi_ppid)
    }

    /// The full account of a process, which the kernel gives only for one this app's own user
    /// owns — enough for a session of theirs, which is the only kind there is here.
    private static func info(_ pid: Int32) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        // A short answer means the process went away between the call and the reply, which is
        // the same thing as not being there at all.
        return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size ? info : nil
    }
}
