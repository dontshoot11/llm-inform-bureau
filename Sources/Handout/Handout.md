# Handout

The description that goes out with a release: an English PDF saying what the app is for, what
each light means and how it is installed. It is the second of the two files on the release page,
beside the disk image — the image is the app, this is the page somebody reads before deciding
to install it.

```sh
Scripts/build-handout.sh    # prints the path of the PDF it built
```

That writes `.build/LLMInformBureau-<version>.pdf`, with the version read from
`Scripts/Info.plist` — the same single source the image takes its number from. Underneath, the
script is `swift run BuildHandout <version> <path>`, which is also how to render a copy
somewhere else while editing.

Nothing here ships. The app target does not depend on this one: it is built on the author's
machine at release time, and what travels is the file.

## The text

`Description.html` is the only copy of it. `{{version}}` stands wherever the version belongs and
is filled in by whoever renders the document, so the number on the page cannot drift from the
number in the app.

Four things are named in it because the app is for four things — several agents kept in the
background, the subscription limits, what each session holds, and an agent waiting on the
person — and a description that dropped one of them would still read perfectly well. That is
what `HandoutTests` is for: it renders the document, reads the PDF back with PDFKit, and fails
if one of the four, or a row of the legend, or a mark itself, is not on the page. It also runs
the same ban on claims about the quality of answers that the interface runs (`QualityClaims`):
this document is the app speaking to the same person, further from the code, where such a
sentence would be easiest to write and hardest to notice.

**No screenshots.** A picture of a menu bar goes stale with the next build and prints badly, so
the lights are drawn as the characters they are. Every colour is named in words beside its dot,
because the page has to carry its legend in black and white too.

## Why HTML and AppKit

Measured on this Mac, 2026-09-17, looking for a way to make a paginated document with nothing
installed beyond the Command Line Tools this package already asks for:

| Tried | Result |
| --- | --- |
| `cupsfilter` from HTML | Refuses: `No filter to convert from text/html to application/pdf` |
| `cupsfilter` from plain text | Works, and prints a typewritten page — no fonts, no tables |
| `pandoc`, `wkhtmltopdf` | Not installed, and installing either is a dependency outside the system |
| `NSAttributedString(html:)` into `NSPrintOperation` | Works from the terminal, with no GUI session |

So the rendering is AppKit's: the HTML becomes an attributed string, a text view lays it out at
the width of an A4 page, and the print machinery paginates it and saves the job as a file
instead of sending it to a printer.

It is a target rather than a few lines inside the release script for one reason: what a script
writes is only ever checked by a person opening the file afterwards, and a target can be
imported by the test suite.

## What the importer does, measured

`NSAttributedString(html:)` is not a browser, and three of its habits shape how the source is
written. All three were measured rather than read about, and each is what a redesign of the page
will meet again:

- **`px` arrives as points, one for one; `pt` arrives a third larger.** 11px is 11pt on the
  page, 9pt is 12pt. The stylesheet is therefore written in px, so the number in the source is
  the number that prints.
- **A width on a cell is a width for that row only.** Widths given once in the header row leave
  every row below it to be measured from its own contents, and the columns come out ragged —
  which is why every cell in every row carries its own `width`. What the numbers do is set
  proportions: the row is scaled to the width of the page, so they are written to add up to it.
- **A non-breaking space does not stop a break.** In a column narrower than the word, the line
  breaks anyway. Keeping "Yellow — past 40%" on one line is a matter of giving the column the
  room, not of gluing the words.

Two other things are load-bearing in `Handout.write`:

- **The text view has to be laid out and grown before printing.** The print machinery paginates
  the view it is given, and a view left at the height it was made with is one page with the
  rest of the document below its edge.
- **The job is saved, not sent.** `jobDisposition = .save` with a `jobSavingURL` in the print
  info is what makes an `NSPrintOperation` write a file; the path is standardised first,
  because a relative one makes it complain twice on stderr about a URL with no scheme.

Page breaks are where the text falls. The importer honours no `page-break` rule, so a block
landing across a break is moved by giving the text above it a line more or a line less — and
the only way to see that it needs moving is to open the file.

## What is in the repository and what is not

The built PDF is not: it lands in `.build/`, which is ignored, and the copy that matters is the
one attached to the release. Rendering it again from the same source and the same version gives
the same document.
