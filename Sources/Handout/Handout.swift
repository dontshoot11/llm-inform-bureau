import AppKit

/// The description that goes out with the release, rendered from the one source there is of it.
///
/// It is a target of its own, and not a few lines inside the release script, for one reason:
/// what a script writes is only ever checked by a person opening the file afterwards. A target
/// can be imported by the test suite, which renders the document and reads back what came
/// out — that the four things the app is for are all named in it, that the legend of the lights
/// is there, and that nothing in it grades a session (`HandoutTests`).
///
/// Nothing here ships. The app bundle does not depend on this target: it is built on the
/// author's machine, at release time, and what travels is the PDF.
public enum Handout {
    /// What the source writes where the version belongs. Filled in by whoever renders the
    /// document, so that the number on the page is the number in `Scripts/Info.plist` and
    /// there is no second place to remember.
    public static let versionMark = "{{version}}"

    /// The source of the description, with the version filled in.
    public static func source(version: String) throws -> String {
        guard let url = Bundle.module.url(forResource: "Description", withExtension: "html") else {
            throw HandoutFailure.sourceMissing
        }
        let html = try String(contentsOf: url, encoding: .utf8)
        return html.replacingOccurrences(of: versionMark, with: version)
    }

    /// Renders the description and writes it to `url` as a PDF.
    ///
    /// AppKit does the whole of it: the HTML becomes an attributed string, a text view lays it
    /// out at the width of an A4 page, and the print machinery paginates it and saves the job
    /// as a file instead of sending it anywhere. Nothing is installed for this — no `pandoc`,
    /// no `wkhtmltopdf` — which is the point: the release runs on the Command Line Tools this
    /// package already asks for. `cupsfilter`, the other thing already on the Mac, refuses HTML
    /// outright and turns plain text into a typewritten page with no fonts.
    ///
    /// The encoding is said three times over, and one of the three is enough. Measured all
    /// four ways on a character typed straight into the source: with neither the `<meta>` tag
    /// in the file nor `.characterEncoding` here, `NSAttributedString(html:)` reads the bytes
    /// as Latin-1 and a dot arrives as two accented letters; with either one, it arrives
    /// whole. The source writes its marks as numeric entities on top of that, which is why
    /// dropping this option today changes nothing — and why it stays: the day somebody types
    /// an em dash into the description rather than spelling it out, the file is still read the
    /// way it was written.
    @MainActor
    public static func write(version: String, to url: URL) throws {
        // Standardised, because a relative path arrives as a URL with a base rather than an
        // absolute one, and the print machinery says so twice on stderr — "passed a URL which
        // has no scheme" — before writing the file anyway.
        let url = url.standardizedFileURL
        let html = try source(version: version)
        guard let document = NSAttributedString(
            html: Data(html.utf8),
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        ) else {
            throw HandoutFailure.sourceNotReadable
        }

        let page = NSPrintInfo()
        page.paperSize = NSSize(width: 595, height: 842)   // A4, in points
        page.topMargin = 56
        page.bottomMargin = 56
        page.leftMargin = 56
        page.rightMargin = 56
        page.horizontalPagination = .fit
        page.verticalPagination = .automatic
        page.jobDisposition = .save
        page.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url

        let width = page.paperSize.width - page.leftMargin - page.rightMargin
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 0))
        text.isVerticallyResizable = true
        text.textContainer?.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        text.textContainer?.widthTracksTextView = true
        text.textStorage?.setAttributedString(document)

        // Laid out before printing, and the view grown to the height that came of it: the print
        // machinery paginates the view it is given, and one left at its initial height is one
        // page with the rest of the document below its edge.
        if let container = text.textContainer, let layout = text.layoutManager {
            layout.ensureLayout(for: container)
            text.setFrameSize(NSSize(width: width, height: ceil(layout.usedRect(for: container).height)))
        }

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: url)

        let job = NSPrintOperation(view: text, printInfo: page)
        job.showsPrintPanel = false
        job.showsProgressPanel = false
        guard job.run(), FileManager.default.fileExists(atPath: url.path) else {
            throw HandoutFailure.notWritten(url)
        }
    }
}

/// What can go wrong while rendering, said in a sentence rather than a code.
///
/// This one does throw, unlike the readers in `SessionHealthCore`: they degrade because a
/// reader's file being unreadable must never take the menu bar down, while this runs on the
/// author's machine at release time, where a document that did not come out has to stop the
/// release rather than ship as an empty page.
public enum HandoutFailure: Error, CustomStringConvertible {
    case sourceMissing
    case sourceNotReadable
    case notWritten(URL)

    public var description: String {
        switch self {
        case .sourceMissing:
            return "Description.html is not in the resource bundle of the Handout target"
        case .sourceNotReadable:
            return "Description.html did not parse as HTML"
        case .notWritten(let url):
            return "the print job finished without leaving a file at \(url.path)"
        }
    }
}
