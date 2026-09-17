import SwiftUI
import Phrasing
import SessionHealthCore

/// A mark that is one number of minutes, as a person sets it: the number in a field, a stepper
/// beside it for a step at a time, and the unit after them both.
///
/// A field rather than a bar because there is nothing to draw: a scale is a picture of three
/// marks dividing a range, and this is one number with no range to divide. Typing it is also
/// the only honest way to reach an exact one — these marks run to twelve hours, and a bar that
/// long would move in leaps of a quarter of an hour.
///
/// The rule the number is held to lives in `MinuteMark`, not here. A field that let somebody
/// type nought would silence a mark, and the same value read back off disk on the next launch
/// would be refused there — two rules, one of which loses.
struct MinuteMarkField: View {
    /// What this mark is called. Not drawn — the row carries the title — but read out beside
    /// the field, where a bare number says nothing about what it sets.
    let title: String

    @Binding var minutes: Int

    /// A number that is now the mark: typed and committed, or stepped. Every change is one,
    /// unlike a drag along a bar: a step is a click and a typed number arrives once, when the
    /// field gives up the focus.
    let settled: (Int) -> Void

    var body: some View {
        HStack(spacing: 4) {
            TextField("", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .font(WindowType.number)
                .multilineTextAlignment(.trailing)
                .frame(width: 54)
                .accessibilityLabel(Text(Briefing.minuteFieldLabel(of: title)))
            Stepper("", value: value, in: MinuteMark.allowed)
                .labelsHidden()
                .accessibilityLabel(Text(Briefing.minuteFieldLabel(of: title)))
            Text(Briefing.minuteUnit)
                .font(WindowType.detail)
                .foregroundStyle(.secondary)
        }
    }

    /// The number on its way in: walked back into what a mark may be, and written down as the
    /// choice it now is. Both controls go through it, so a mark cannot be set one way by the
    /// stepper and another way by the keyboard.
    private var value: Binding<Int> {
        Binding(
            get: { minutes },
            set: { typed in
                let allowed = MinuteMark.clamped(typed)
                minutes = allowed
                settled(allowed)
            }
        )
    }
}
