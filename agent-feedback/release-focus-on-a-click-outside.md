# A control that takes focus has to give it back

When: writing a focusable control of your own in SwiftUI — anything that holds `@FocusState`
so the arrow keys reach it.
Do: give the surface around it a way to drop the focus (`makeFirstResponder(nil)` on a tap
outside), and check it by clicking elsewhere after using the control.
Why: nothing takes the ring off by itself. A handle touched once stays ringed for the rest of
the run, which reads as the app being stuck rather than as focus.

Date: 2026-09-17 · Source: user's report (task settings-and-checkup, phase 1 — "выделение
кнопки нужно снимать по click outside, а то оно там навечно висит")
