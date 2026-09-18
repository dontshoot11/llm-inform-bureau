import Foundation
import Handout
import PDFKit

/// That the document handed out with the release says what it is for.
///
/// The genre is `OfflineTests`' and `TranslationTests`': the claim is about a whole artefact
/// rather than about one function, so the test builds the artefact and reads it. Here it is
/// built twice over — the source is rendered to a PDF and the PDF is read back with PDFKit —
/// because what a person receives is the rendered file, and a check against the HTML would
/// pass on a document that came out empty, in Latin-1, or on one page with the rest below the
/// paper's edge.
///
/// What it does not check is how the page looks. That is read by opening it, and the reasons
/// behind the shape it has are in `Handout.md`.
@MainActor
func runHandoutTests(_ suite: TestSuite) {
    withTemporaryDirectory(suite, named: "handout") { directory in
        let pdf = directory.appendingPathComponent("description.pdf")
        // Not a version any release will have: it is here to be looked for on the page.
        let version = "9.9.9-test"

        var document: PDFDocument?
        suite.test("the description renders to a PDF of several pages") {
            do {
                try Handout.write(version: version, to: pdf)
            } catch {
                suite.expect(false, "rendering failed: \(error)")
                return
            }
            guard let rendered = PDFDocument(url: pdf) else {
                suite.expect(false, "PDFKit could not open what was written")
                return
            }
            document = rendered
            suite.expect(
                rendered.pageCount > 1,
                "the description came out on \(rendered.pageCount) page — the text view was not paginated"
            )
        }

        guard let text = document?.string else {
            suite.test("the description has text in it") {
                suite.expect(false, "nothing could be read back out of the PDF")
            }
            return
        }

        suite.test("the version it was built for is on the page, and the mark for it is gone") {
            suite.expect(text.contains(version), "the page does not name version \(version)")
            suite.expect(
                !text.contains(Handout.versionMark),
                "\(Handout.versionMark) is still standing where the version belongs"
            )
        }

        // The four the PRD names, each looked for by the phrase it is named with rather than by
        // a whole sentence: the wording is the author's to improve, the four subjects are not
        // the author's to drop.
        let four = [
            "several agents in the background": "several agents in the background",
            "the subscription limits": "subscription limits",
            "what each session holds": "context window",
            "an agent waiting on the person": "waiting on you"
        ]
        suite.test("the description names all four things the app is for") {
            for (subject, said) in four {
                suite.expect(text.contains(said), "nothing on the page says \(subject) (\"\(said)\")")
            }
        }

        suite.test("the legend of the lights is there, colours and shapes both") {
            let legend = [
                "Green", "Yellow", "Orange", "Red",
                "under 40%", "past 40%", "past 60%", "past 90%",
                "Red cross", "Steady", "Figure eight", "Pause sign"
            ]
            for entry in legend {
                suite.expect(text.contains(entry), "the legend does not mention \(entry)")
            }
        }

        // The dots are the legend: a colour named in words beside a mark that is not there is
        // half a legend. They are also what an encoding mistake takes first, and a document
        // that lost them renders, paginates and passes every check above — so what is read
        // back here is the characters, not the words about them. The three things keeping
        // them whole are in `Handout.write`.
        suite.test("the marks themselves survived the rendering") {
            suite.expect(text.contains("\u{25CF}"), "no filled dot reached the page")
            suite.expect(text.contains("\u{25CB}"), "no hollow dot reached the page")
            suite.expect(text.contains("\u{221E}"), "the figure eight did not reach the page")
        }

        suite.test("the description claims nothing about the quality of the answers") {
            let said = QualityClaims.found(in: text)
            suite.expect(said.isEmpty, "the page says \(said) — AGENTS.md forbids it anywhere the app speaks")
        }
    }
}
