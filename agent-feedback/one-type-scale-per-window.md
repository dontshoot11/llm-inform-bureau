# Set new interface from the window's own type scale, not by eye

When: adding anything to a window or panel of this app — a heading, a row, an explanation,
a number.
Do: take the size from the scale the surface already declares (`WindowType` in
`WelcomeWindow.swift`: section, item, detail, number) and add to it only when the surface
genuinely lacks a size. Do not pick `.callout` here and `.caption` there because each block
looked right on its own.
Why: every block was set separately as it was written, and the result reads as several windows
stacked up rather than one.

Date: 2026-09-17 · Source: user's report (task settings-and-checkup, phase 1 — "нужен
консистентный шрифт, сейчас все вразнобой")
