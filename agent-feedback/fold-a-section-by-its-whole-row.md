# A fold opens by its whole row, and says so under the pointer

When: giving a section somewhere to fold away in this app.
Do: make the whole row the button — chevron plus title — and put `Hoverable` on it, the same
plate every other control here wears. The chevron is decoration and never the only target.
Reuse the shape the panel already has (`limitsDisclosure` in `MenuContent.swift`) rather than
SwiftUI's `DisclosureGroup`, which puts the click on the triangle alone and says nothing on
hover.
Why: nothing in this interface is styled to be clicked, so a row that does something has only
the plate to say it with.

Date: 2026-09-17 · Source: user's report (task settings-and-checkup, phase 1 — "нужно
раскрывать по клику по всей строке, шеврон просто декор, ну и нужно выделение по ховеру")
