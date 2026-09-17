import Foundation

/// The three marks of one scale, as a person moves them: where a mark sits on the bar, how far
/// it may go, and what a drag or an arrow key turns into.
///
/// A type of its own rather than arithmetic inside the control that draws the bar. The rule it
/// keeps — marks stay in order, inside 0-100, and never on top of one another — is the whole
/// reason the scale can be read at a glance, and it is the one thing a drag handler can break
/// silently: a yellow mark dragged past the red one leaves three colours in no order and a
/// widget that means nothing. Here it is a rule with tests under it, and the view only draws.
///
/// The same rule the config file is read by: `ThresholdConfigParser` refuses a scale this type
/// refuses, so a scale that arrives from the person and one that arrives from a file are held
/// to one standard rather than two that can drift.
///
/// Usage:
/// ```swift
/// var scale = MarkScale(of: config.limitUsage)
/// scale = scale.moving(.elevated, to: MarkScale.percent(atOffset: drag.x, width: barWidth))
/// scale = scale.nudging(.elevated, by: 1)   // an arrow key
/// ```
public struct MarkScale: Equatable, Sendable {
    /// Which of the three marks is being moved. Named after the levels they turn on, so a
    /// handle and the light it produces cannot come to be called different things.
    public enum Handle: String, CaseIterable, Sendable {
        case notice
        case elevated
        case high
    }

    /// The top of the scale. A percentage of a window, so there is nothing above it.
    public static let highest: Double = 100

    /// How far apart two marks stay, and how far the lowest one stays from zero.
    ///
    /// One percentage point: the numbers are shown as whole percentages, so marks any closer
    /// would be two handles reading the same number — a scale nobody can tell apart by looking,
    /// which is what the bar exists to prevent. It is also the step an arrow key takes.
    public static let gap: Double = 1

    /// Colours the light and never notifies.
    public let notice: Double
    public let elevated: Double
    public let high: Double

    /// A scale, or `nil` for three numbers that are not one: out of order, at zero or below, or
    /// past 100. This is the rule — the config file, the choice read back off disk and the
    /// control on screen all meet it here.
    public init?(notice: Double, elevated: Double, high: Double) {
        guard notice > 0, elevated > notice, high > elevated, high <= Self.highest else { return nil }
        self.notice = notice
        self.elevated = elevated
        self.high = high
    }

    /// The marks of a loaded config as a bar can draw them.
    ///
    /// Not failable, and not because the numbers are trusted: the parser has already refused
    /// anything out of order, but it accepts two marks a hair apart — 40 and 40.4 are an
    /// ordered scale — and two handles on top of each other cannot be told apart, let alone
    /// moved. So anything the drawing rule cannot hold is pushed apart here rather than
    /// refused: the alternative is a window that shows nothing where the config is.
    public init(of marks: PercentMarks) {
        let notice = Self.clamped(marks.notice, Self.gap, Self.highest - 2 * Self.gap)
        let elevated = Self.clamped(marks.elevated, notice + Self.gap, Self.highest - Self.gap)
        let high = Self.clamped(marks.high, elevated + Self.gap, Self.highest)
        self.notice = notice
        self.elevated = elevated
        self.high = high
    }

    public func value(of handle: Handle) -> Double {
        switch handle {
        case .notice: notice
        case .elevated: elevated
        case .high: high
        }
    }

    /// How far a mark may be moved: up to its neighbours, and up to the ends of the bar.
    ///
    /// The neighbours stand still. A mark that pushed the next one along would let a single
    /// drag rewrite two marks a person never touched — and the one they were dragging would
    /// stop where the bar ends rather than where they let go, which is not what a bar full of
    /// handles promises.
    public func bounds(of handle: Handle) -> ClosedRange<Double> {
        switch handle {
        case .notice: Self.gap...(elevated - Self.gap)
        case .elevated: (notice + Self.gap)...(high - Self.gap)
        case .high: (elevated + Self.gap)...Self.highest
        }
    }

    /// This scale with one mark moved as far towards `percent` as its bounds allow, on a whole
    /// percentage point.
    ///
    /// Rounded because the number beside the handle is shown as a whole percentage: a mark
    /// held at 42.7 and shown as 43% would make the number a description of the mark rather
    /// than the mark itself, and there would be no way to land on exactly 43.
    public func moving(_ handle: Handle, to percent: Double) -> MarkScale {
        let range = bounds(of: handle)
        let wanted = Self.clamped(percent.rounded(), range.lowerBound, range.upperBound)
        switch handle {
        case .notice: return MarkScale(exactly: wanted, elevated, high)
        case .elevated: return MarkScale(exactly: notice, wanted, high)
        case .high: return MarkScale(exactly: notice, elevated, wanted)
        }
    }

    /// This scale with one mark moved by whole percentage points — what an arrow key does, and
    /// how an exact number is reached when a pointer cannot be trusted to land on one.
    public func nudging(_ handle: Handle, by steps: Double) -> MarkScale {
        moving(handle, to: value(of: handle) + steps)
    }

    // MARK: The bar

    /// The percentage a point along a bar of this width stands for, rounded to the whole
    /// percentage the handle will take. Off either end of the bar it is the end.
    public static func percent(atOffset offset: Double, width: Double) -> Double {
        guard width > 0 else { return 0 }
        return clamped((offset / width * highest).rounded(), 0, highest)
    }

    /// Where along a bar of this width a percentage sits.
    public static func offset(ofPercent percent: Double, width: Double) -> Double {
        guard width > 0 else { return 0 }
        return clamped(percent, 0, highest) / highest * width
    }

    /// Where along a bar of this width one of the marks sits.
    public func offset(of handle: Handle, width: Double) -> Double {
        Self.offset(ofPercent: value(of: handle), width: width)
    }

    // MARK: Building one that is known to hold

    /// The memberwise initialiser without the rule, for values this type has just produced
    /// itself. Everything from outside goes through `init?`.
    private init(exactly notice: Double, _ elevated: Double, _ high: Double) {
        self.notice = notice
        self.elevated = elevated
        self.high = high
    }

    private static func clamped(_ value: Double, _ lowest: Double, _ highest: Double) -> Double {
        guard lowest <= highest else { return lowest }
        return min(max(value, lowest), highest)
    }
}
