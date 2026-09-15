import AppKit
import SwiftUI
import Phrasing
import SessionHealthCore

/// The menu bar app: a title in the bar, a panel behind it, no windows.
///
/// `LSUIElement` in the bundle's Info.plist is what keeps it out of the Dock and out of the
/// app switcher; `Scripts/build-app.sh` is what turns the SwiftPM executable into that bundle.
@main
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
                (Wording.service($0), model.lights(of: $0))
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

/// The whole menu bar label, drawn: each service's name followed by its two lights, stacked.
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
/// The pair is stacked rather than in a row for two reasons: it costs a third of the width,
/// and it puts the two in the order the panel puts its two sections in — limits above,
/// session context below — so the bar is read the same way round as what opens behind it.
enum BarLights {
    private static let diameter = 6.0
    private static let betweenDots = 2.5
    private static let nameToDots = 6.0
    private static let betweenServices = 10.0

    /// Set in capitals, letter-spaced, a size down: the names are labels for the lights next
    /// to them rather than titles of their own, and the panel's section captions are set the
    /// same way.
    private static var font: NSFont { .menuBarFont(ofSize: 11) }
    private static let tracking = 0.6

    static func image(for services: [(name: String, lights: ServiceLights)]) -> NSImage {
        let columnWidth = diameter
        let widths = services.map { width(of: $0.name) + nameToDots + columnWidth }
        let total = widths.reduce(0, +) + betweenServices * Double(max(services.count - 1, 0))
        let height = (font.ascender - font.descender).rounded(.up) + 2
        let middle = height / 2

        let image = NSImage(size: NSSize(width: total.rounded(.up), height: height), flipped: false) { _ in
            var x = 0.0
            for service in services {
                // Resolved here rather than stored: the drawing handler runs at draw time, so
                // the name comes out in the menu bar's own colour in either appearance.
                let text = NSAttributedString(
                    string: service.name.uppercased(),
                    attributes: [.font: font, .foregroundColor: NSColor.labelColor, .kern: tracking]
                )
                // `draw(at:)` takes the bottom-left of the whole line box, not the baseline, so
                // the offset has to walk down from the capitals: half the cap height to reach
                // the baseline, then the descender to reach the box. Centring the line box
                // instead leaves the name visibly high, because that box is as tall as the
                // font's accents and descenders and the name uses neither.
                text.draw(at: NSPoint(x: x, y: middle - font.capHeight / 2 + font.descender))
                x += width(of: service.name) + nameToDots

                // Stacked, in the order the panel puts them in: limits above, context below,
                // and the pair centred on the same middle the capitals are centred on.
                draw(service.lights.limits, atX: x, y: middle + betweenDots / 2)
                draw(service.lights.context, atX: x, y: middle - betweenDots / 2 - diameter)
                x += columnWidth + betweenServices
            }
            return true
        }
        // Not a template: a template image is tinted to one colour, and then green and red look
        // the same. The cost is drawing the text ourselves, above.
        image.isTemplate = false
        return image
    }

    private static func width(of name: String) -> Double {
        (name.uppercased() as NSString).size(withAttributes: [.font: font, .kern: tracking]).width
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
    private static func draw(_ light: Light, atX x: Double, y: Double) {
        let box = NSRect(x: x, y: y, width: diameter, height: diameter)
        switch light {
        case .unknown:
            return
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
}
