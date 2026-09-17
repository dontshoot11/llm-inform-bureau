import AppKit
import SwiftUI
import Phrasing
import SessionHealthCore

/// The menu bar app: a title in the bar, a panel behind it, no windows.
///
/// `LSUIElement` in the bundle's Info.plist is what keeps it out of the Dock and out of the
/// app switcher; `Scripts/build-app.sh` is what turns the SwiftPM executable into that bundle.
///
/// Not the entry point: the same binary is also Claude Code's status line command, and which
/// of the two it is has to be decided before this scene starts anything. See `Entry.swift`.
struct LLMInformBureauApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = UsageModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            // One image for the whole bar, names included. Measured: a label of several views
            // renders only the first — the status item takes one image and one title, and
            // names and lights have to interleave, which that cannot express.
            Image(nsImage: BarLights.image(for: AgentService.allCases.map {
                (Wording.serviceInBar($0), model.lights(of: $0), model.pulse(of: $0), model.sign(of: $0))
            }))
        }
        // The panel style, because the panel shows readings and their age rather than a list
        // of things to click.
        .menuBarExtraStyle(.window)
    }
}

/// The launch hook a SwiftUI scene does not have.
///
/// The first-run explanation has to open before the user has clicked anything — that is the
/// point of it — and `MenuBarExtra` gives no callback until its panel is opened.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        ensureQuitShortcut()
        Welcome.showIfDue()
    }

    /// Makes sure ⌘Q exists.
    ///
    /// The panel has no Quit button — it was the widest thing in a panel that is otherwise all
    /// readings — so the keyboard is the way out, and an app whose only exit is `pkill` is not
    /// something to leave to chance. `LSUIElement` shows no menu bar, and a menu that is never
    /// drawn is easy to end up without; this adds one only when there is none, so whatever the
    /// framework already built is left alone.
    private func ensureQuitShortcut() {
        guard NSApp.mainMenu == nil else { return }

        let application = NSMenuItem()
        application.submenu = NSMenu()
        application.submenu?.addItem(
            NSMenuItem(
                title: "Quit \(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "App")",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )
        let main = NSMenu()
        main.addItem(application)
        NSApp.mainMenu = main
    }
}

/// The whole menu bar label, drawn: one badge per service, holding its name and its two
/// lights, stacked.
///
/// Everything is drawn rather than composed of views because a `MenuBarExtra` label renders
/// only its first view — the status item underneath takes one image and one title, and this
/// bar needs names and lights to alternate. The colour rules out a template image, which is
/// what would have let the system draw the text itself, so the text is drawn here too.
///
/// The bar carries no numbers: four dots answer "is anything worth looking at", and the panel
/// behind them answers "how much exactly". A percentage in the bar was the previous
/// arrangement, and it said nothing about the half of the picture that was fine.
///
/// Each pair is stacked rather than in a row for two reasons: it costs a third of the width,
/// and it puts the two in the order the panel puts its two sections in — limits above,
/// session context below — so the bar is read the same way round as what opens behind it.
///
/// **Name and lights share one badge**, so the bar is two objects rather than four. Width is
/// the whole reason: the bar is shared with every other app on this Mac, and when it runs out
/// of room macOS stops drawing status items, this one included. Measured against the previous
/// arrangement — names set in capitals beside their lights — the badges cost about a sixth
/// less, and that is on top of the third saved by shortening the names themselves.
///
/// The badge is also what makes a name this small readable: `cld` set at 9pt straight onto the
/// menu bar is mush, and the same letters on a tinted plate are not. Variants were drawn and
/// compared at true size before this one was picked; the ones that lost were plain small caps,
/// two-letter names (`cx` does not read as Codex), and no names at all, which is narrowest and
/// says least.
enum BarLights {
    private static let diameter = 6.0
    private static let betweenDots = 2.5
    private static let dotsToName = 3.0
    private static let betweenServices = 8.0
    /// 18 rather than 16: the two lights and the gap between them stand 14.5 tall, and a
    /// 16-tall plate left 0.75 of air above and below — enough to read as lights glued to the
    /// ceiling and the floor. 18 gives 1.75 each side and still leaves the plate clear of the
    /// menu bar's own 22.
    private static let badgeHeight = 18.0
    private static let badgePadding = 3.0
    private static let badgeRadius = 3.5

    /// Set lowercase, tight, small: inside a badge the name is a tag on the lights beside it,
    /// not a title. Capitals and letter-spacing were what the previous arrangement needed to
    /// read on the bare menu bar; on a plate they only cost width.
    ///
    /// 10pt rather than 9: at 9 the plate carried it, but the letters were smaller than
    /// anything else in the menu bar and read as squinting. The extra point costs 3pt of width
    /// out of 71, which is the cheapest part of this whole layout to spend.
    private static var font: NSFont { .systemFont(ofSize: 10, weight: .semibold) }

    static func image(
        for services: [(name: String, lights: ServiceLights, pulse: Double?, sign: LightSign?)]
    ) -> NSImage {
        let widths = services.map { badgeWidth(for: $0.name) }
        let total = widths.reduce(0, +) + betweenServices * Double(max(services.count - 1, 0))
        let height = badgeHeight + 2
        let middle = height / 2

        let image = NSImage(size: NSSize(width: total.rounded(.up), height: height), flipped: false) { _ in
            var x = 0.0
            for (service, width) in zip(services, widths) {
                // Resolved here rather than stored: the drawing handler runs at draw time, so
                // the plate and the name come out in the menu bar's own colours in either
                // appearance. The plate is the label colour at low alpha rather than a colour
                // of its own, so it sits behind the text in both without being picked twice.
                NSColor.labelColor.withAlphaComponent(0.18).setFill()
                NSBezierPath(
                    roundedRect: NSRect(x: x, y: middle - badgeHeight / 2, width: width, height: badgeHeight),
                    xRadius: badgeRadius,
                    yRadius: badgeRadius
                ).fill()

                let text = NSAttributedString(
                    string: service.name.lowercased(),
                    attributes: [.font: font, .foregroundColor: NSColor.labelColor]
                )
                // `draw(at:)` takes the bottom-left of the whole line box, not the baseline, so
                // the offset has to walk down from the capitals: half the cap height to reach
                // the baseline, then the descender to reach the box. Centring the line box
                // instead leaves the name visibly high, because that box is as tall as the
                // font's accents and descenders and the name uses neither.
                text.draw(
                    at: NSPoint(
                        x: x + badgePadding + diameter + dotsToName,
                        y: middle - font.capHeight / 2 + font.descender
                    )
                )

                // Lights first, name after — the order the panel reads in, where every row is a
                // dot and then what it is about. Two arrangements of the same four lights that
                // disagree about which side the colour is on cost a beat of looking every time
                // the eye moves between the bar and the panel open under it.
                //
                // Stacked the way the panel stacks them too: limits above, context below, the
                // pair centred on the same middle the name is centred on.
                let dotsX = x + badgePadding
                draw(service.lights.limits, atX: dotsX, y: middle + betweenDots / 2)
                let contextY = middle - betweenDots / 2 - diameter
                if !blinkedOut(service.pulse) {
                    draw(service.lights.context, sign: service.sign, atX: dotsX, y: contextY)
                }
                x += width + betweenServices
            }
            return true
        }
        // Not a template: a template image is tinted to one colour, and then green and red look
        // the same. The cost is drawing the text ourselves, above.
        image.isTemplate = false
        return image
    }

    /// Frames in one blink of the context light. Kept equal to `UsageModel.pulseFrames`, which
    /// paces them: that one is main-actor isolated and this drawing is not, so the number lives
    /// in both places and each says so.
    static let blinkFrames = 6.0

    /// Whether the context light is left undrawn for this frame of a blink.
    ///
    /// Blinking is the light going out and coming back, not a glow swelling and fading. Both
    /// were tried in the menu bar: a fade drawn in alpha over a ring a point or two wide was
    /// invisible — the eye gets nothing from a gradient that small — while the light simply
    /// being absent for 200ms is unmistakable. It is also the kind of change that redraws
    /// reliably, the same as a light changing colour, rather than relying on a dozen frames
    /// all arriving.
    ///
    /// The slot is kept, as it is for a light with nothing behind it: position is what names a
    /// light, and a blink that moved its neighbour would be read as something else entirely.
    ///
    /// The bar is not told *why* it is blinking, and does not need to be: the reading moving
    /// blinks three times and stops, a session waiting on its agent goes on blinking until the
    /// answer lands. Which of the two it is, is `UsageModel`'s to know — here it is one phase.
    private static func blinkedOut(_ phase: Double?) -> Bool {
        guard let phase else { return false }
        // Even frames dark, odd frames lit, so a pulse starts by going out — the change happens
        // the instant the reading does, rather than a frame later.
        return Int(phase * blinkFrames) % 2 == 0
    }

    /// Name, lights and the padding around both — everything inside one plate.
    private static func badgeWidth(for name: String) -> Double {
        badgePadding + diameter + dotsToName + width(of: name) + badgePadding
    }

    private static func width(of name: String) -> Double {
        (name.lowercased() as NSString).size(withAttributes: [.font: font]).width
    }

    /// The three things a light can be.
    ///
    /// Nothing reported draws nothing at all — but keeps its place. An outline was tried first
    /// and reads as a dot that failed rather than as an absence; the panel does the same thing
    /// in its own way, showing no session row rather than an empty one. The slot stays because
    /// position is what names a light: a lone dot sitting high is the limits, the same dot
    /// sitting low is the context.
    ///
    /// A spent window is a cross rather than a fourth colour. Red already means "the end is
    /// close", and there is no shade of it that reads as "the end arrived" — a different shape
    /// says that at a glance, which is all the bar is for.
    ///
    /// A session being waited on is the same light drawn as a sign — a figure eight for a wait
    /// past the fuse, the pause bars for an agent asking the person something. Shape for the
    /// state, colour still for the budget, the same pair of claims the panel makes in its own
    /// row. Neither is drawn for a light with nothing behind it: in the bar an unreported
    /// reading draws nothing at all, and a sign appearing where there was never a dot would be
    /// the app announcing a wait on a session whose numbers it never had. The panel, which does
    /// draw that reading as an outline, draws the sign for it too.
    private static func draw(_ light: Light, sign: LightSign? = nil, atX x: Double, y: Double) {
        let box = NSRect(x: x, y: y, width: diameter, height: diameter)
        switch light {
        case .unknown:
            return
        case .level(let level) where sign != nil:
            draw(sign!, in: box, colour: NSColor(Palette.colour(of: level)))
        case .level(let level):
            NSColor(Palette.colour(of: level)).setFill()
            NSBezierPath(ovalIn: box).fill()
        case .spent:
            let cross = NSBezierPath()
            let inset = 0.7
            cross.move(to: NSPoint(x: box.minX + inset, y: box.minY + inset))
            cross.line(to: NSPoint(x: box.maxX - inset, y: box.maxY - inset))
            cross.move(to: NSPoint(x: box.minX + inset, y: box.maxY - inset))
            cross.line(to: NSPoint(x: box.maxX - inset, y: box.minY + inset))
            cross.lineWidth = 1.6
            cross.lineCapStyle = .round
            NSColor(Palette.colour(of: .high)).setStroke()
            cross.stroke()
        }
    }

    /// A sign, in the bar's own drawing. The geometry is `WaitSign` and `PauseSign` — shared
    /// with the panel so that the two halves of the app draw one sign each and not two similar
    /// ones.
    private static func draw(_ sign: LightSign, in box: NSRect, colour: NSColor) {
        let path: NSBezierPath
        switch sign {
        case .stalled: path = waitSignPath(in: box)
        case .asking: path = pauseSignPath(in: box)
        }
        path.lineWidth = sign.lineWidth(forDiameter: diameter)
        path.lineCapStyle = .round
        colour.setStroke()
        path.stroke()
    }

    private static func waitSignPath(in box: NSRect) -> NSBezierPath {
        let (centre, reach, lift) = WaitSign.lobes(in: box)
        let path = NSBezierPath()
        path.move(to: centre)
        path.curve(
            to: centre,
            controlPoint1: NSPoint(x: centre.x - reach, y: centre.y + lift),
            controlPoint2: NSPoint(x: centre.x - reach, y: centre.y - lift)
        )
        path.curve(
            to: centre,
            controlPoint1: NSPoint(x: centre.x + reach, y: centre.y - lift),
            controlPoint2: NSPoint(x: centre.x + reach, y: centre.y + lift)
        )
        return path
    }

    private static func pauseSignPath(in box: NSRect) -> NSBezierPath {
        let path = NSBezierPath()
        for bar in PauseSign.bars(in: box) {
            path.move(to: NSPoint(x: bar.from.x, y: bar.from.y))
            path.line(to: NSPoint(x: bar.to.x, y: bar.to.y))
        }
        return path
    }
}
