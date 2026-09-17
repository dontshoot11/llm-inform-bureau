import SwiftUI
import Phrasing
import SessionHealthCore

/// A scale the person moves: the bar painted in the colours its marks produce, a handle on each
/// mark, and the number under it.
///
/// Three numbers in three fields would have been less work and would have asked the reader to
/// imagine what they add up to. The scale *is* the thing being set — where yellow gives way to
/// orange, where orange gives way to red — so it is set on a picture of itself, and the colours
/// under the handles are the same ones the lights in the menu bar are drawn with.
///
/// The arithmetic is not here. `MarkScale` holds it, with tests under it, and this view does
/// what a view should: draw where the marks are and say where a gesture landed.
///
/// Every handle is its own focusable control, so a mark can be taken to an exact number with
/// the arrow keys — a pointer cannot be trusted to land on 35 rather than 34 — and so that
/// something that is a row of coloured dots to look at is three named, adjustable values to a
/// screen reader.
struct MarkScaleBar: View {
    /// What this scale is called. Not drawn — the row above it carries the title — but read out
    /// beside each handle, where "the yellow mark" alone would not say of what.
    let title: Phrase

    @Binding var scale: MarkScale

    /// A move that is over: the pointer let go, or a key pressed. Separate from every step of a
    /// drag so that a mark dragged across the bar is written down once rather than a hundred
    /// times.
    let settled: (MarkScale) -> Void

    @EnvironmentObject private var interface: InterfaceLanguage

    @FocusState private var focused: MarkScale.Handle?

    private static let coordinates = "mark-scale-bar"
    private static let trackHeight: Double = 10
    private static let handleDiameter: Double = 15
    /// Wide enough for "100%" at the window's number size, so a mark at either end still has
    /// its number under it rather than beside it.
    private static let labelWidth: Double = 48
    /// The track and the handles share a centre line; the numbers sit under it.
    private static let markCentre: Double = handleDiameter / 2
    private static let labelCentre: Double = handleDiameter + 11
    private static let height: Double = handleDiameter + 24

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .topLeading) {
                track(width: width)
                ForEach(MarkScale.Handle.allCases, id: \.self) { handle in
                    knob(handle, width: width)
                    label(handle, width: width)
                }
            }
            .frame(width: width, height: Self.height, alignment: .topLeading)
            .coordinateSpace(name: Self.coordinates)
        }
        .frame(height: Self.height)
    }

    /// The bar itself: one band per level, each as wide as the share of the scale that level
    /// covers. Reading it left to right is reading what the marks do.
    private func track(width: Double) -> some View {
        HStack(spacing: 0) {
            band(.normal, from: 0, to: scale.notice, width: width)
            band(.notice, from: scale.notice, to: scale.elevated, width: width)
            band(.elevated, from: scale.elevated, to: scale.high, width: width)
            band(.high, from: scale.high, to: MarkScale.highest, width: width)
        }
        .frame(width: width, height: Self.trackHeight)
        .clipShape(Capsule())
        .position(x: width / 2, y: Self.markCentre)
    }

    private func band(_ level: BudgetLevel, from: Double, to: Double, width: Double) -> some View {
        Rectangle()
            .fill(Palette.colour(of: level).opacity(0.75))
            .frame(width: max(MarkScale.offset(ofPercent: to - from, width: width), 0))
    }

    /// One mark, as something to take hold of. Ringed in the colour it turns on, so the handle
    /// and the light it is about are the same colour rather than two things to connect.
    private func knob(_ handle: MarkScale.Handle, width: Double) -> some View {
        Circle()
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay(
                Circle().strokeBorder(
                    Palette.colour(of: level(of: handle)),
                    lineWidth: focused == handle ? 4 : 2.5
                )
            )
            .frame(width: Self.handleDiameter, height: Self.handleDiameter)
            .contentShape(Circle())
            .focusable()
            .focused($focused, equals: handle)
            .onMoveCommand { direction in
                switch direction {
                case .left, .down: move(handle, by: -MarkScale.gap)
                case .right, .up: move(handle, by: MarkScale.gap)
                @unknown default: break
                }
            }
            .accessibilityElement()
            .accessibilityLabel(Text(interface.say(Briefing.handleLabel(handle, of: title))))
            .accessibilityValue(Text(TokenDisplay.percent(scale.value(of: handle))))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: move(handle, by: MarkScale.gap)
                case .decrement: move(handle, by: -MarkScale.gap)
                @unknown default: break
                }
            }
            .gesture(drag(handle, width: width))
            .position(x: scale.offset(of: handle, width: width), y: Self.markCentre)
    }

    /// The number under a handle. Kept whole inside the bar at either end: a mark at 100% with
    /// its number hanging off the edge is the one place the reader most wants to see it.
    private func label(_ handle: MarkScale.Handle, width: Double) -> some View {
        let offset = scale.offset(of: handle, width: width)
        let bounded = min(max(offset, Self.labelWidth / 2), max(width - Self.labelWidth / 2, Self.labelWidth / 2))
        return Text(TokenDisplay.percent(scale.value(of: handle)))
            .font(WindowType.number)
            .foregroundStyle(focused == handle ? Color.primary : Color.secondary)
            .frame(width: Self.labelWidth)
            .accessibilityHidden(true)
            .position(x: bounded, y: Self.labelCentre)
    }

    /// Taking hold of a mark: it goes where the pointer is, within what the scale allows. The
    /// gesture starts at no distance at all, so a click on a handle is a focus and a move of
    /// nought rather than nothing happening.
    private func drag(_ handle: MarkScale.Handle, width: Double) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.coordinates))
            .onChanged { value in
                focused = handle
                scale = scale.moving(handle, to: MarkScale.percent(atOffset: value.location.x, width: width))
            }
            .onEnded { _ in settled(scale) }
    }

    private func move(_ handle: MarkScale.Handle, by steps: Double) {
        scale = scale.nudging(handle, by: steps)
        settled(scale)
    }

    /// The light a mark turns on — what its colour is, in one place, so the bar cannot come to
    /// disagree with the dots in the panel.
    private func level(of handle: MarkScale.Handle) -> BudgetLevel {
        switch handle {
        case .notice: .notice
        case .elevated: .elevated
        case .high: .high
        }
    }
}
