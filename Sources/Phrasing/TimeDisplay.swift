import Foundation

/// Durations as the panel says them: short, and never rounded into a lie.
///
/// A reading from eleven seconds ago is "just now"; one from yesterday says the day, because
/// the age of a limit reading is the difference between "this is current" and "this is what
/// Codex thought before lunch".
///
/// Both sides are short, and they are short in their own ways. English writes a gap as `2h 5m`;
/// Russian abbreviates the same way — `2 ч 5 мин` — because this sits in a panel row next to a
/// percentage and a name, and there is no room for the words in full. Where a duration is read
/// out in a sentence rather than in a row, it *is* said in full, and then the noun agrees with
/// the number (`RussianCount`): a window is «5 часов» and «7 дней», never «7 день».
///
/// A date is the one thing here that is not built out of parts: each side is formatted in its
/// own locale, so the Russian side says «14 сент. 2026 г. в 15:30» rather than an English month
/// standing in a Russian sentence.
public enum TimeDisplay {
    public static func age(of date: Date, now: Date = Date()) -> Phrase {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return Phrase("just now", "только что") }
        if seconds < 60 * 60 * 12 {
            let gap = compact(seconds)
            return Phrase("\(gap.english) ago", "\(gap.russian) назад")
        }
        let when = moment(date)
        return Phrase("on \(when.english)", when.russian)
    }

    public static func until(_ date: Date, now: Date = Date()) -> Phrase {
        let seconds = date.timeIntervalSince(now)
        if seconds <= 0 { return Phrase("any moment", "вот-вот") }
        if seconds < 60 * 60 * 24 {
            let gap = compact(seconds)
            return Phrase("in \(gap.english)", "через \(gap.russian)")
        }
        let when = moment(date)
        return Phrase("on \(when.english)", when.russian)
    }

    /// A moment named outright rather than measured against now.
    ///
    /// For the one date in the app that is not an age: when the running copy was built. "Two
    /// hours ago" is the wrong shape for it — the question it answers is which of the bundles
    /// on this disk is in the menu bar, and that is settled by a date and a time, not by a gap.
    public static func moment(_ date: Date) -> Phrase {
        Phrase(spelled(date, by: englishDates), spelled(date, by: russianDates))
    }

    /// The length of a limit window, as the service reports it in minutes.
    ///
    /// Said in a sentence rather than in a row — "5-hour window", «окно 5 часов» — so the
    /// Russian side spells the unit out and agrees it with the number.
    public static func windowLength(_ minutes: Int) -> Phrase {
        if minutes % (60 * 24) == 0 {
            let days = minutes / (60 * 24)
            return Phrase("\(days)d", RussianCount.of(days, "день", "дня", "дней"))
        }
        if minutes % 60 == 0 {
            let hours = minutes / 60
            return Phrase("\(hours)h", RussianCount.of(hours, "час", "часа", "часов"))
        }
        return Phrase("\(minutes)m", RussianCount.of(minutes, "минута", "минуты", "минут"))
    }

    /// A gap as a row has room for it: the numbers with a letter after each, on both sides.
    private static func compact(_ seconds: TimeInterval) -> Phrase {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours == 0 {
            let shown = max(minutes, 1)
            return Phrase("\(shown)m", "\(shown) мин")
        }
        if minutes == 0 { return Phrase("\(hours)h", "\(hours) ч") }
        return Phrase("\(hours)h \(minutes)m", "\(hours) ч \(minutes) мин")
    }

    /// The two ways of writing a date this app has to be able to produce, named rather than
    /// asked for at the point of use: the locale of the Mac is not one of them, and a side of a
    /// phrase written in whatever the machine is set to is how an English month ends up in the
    /// middle of a Russian sentence.
    private static let englishDates = Locale(identifier: "en_US")
    private static let russianDates = Locale(identifier: "ru_RU")

    /// A date in one language's own way of writing dates.
    private static func spelled(_ date: Date, by locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
