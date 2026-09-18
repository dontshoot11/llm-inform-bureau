# A measurement borrowed from research is taken again where the comment lands

When: about to explain a defence — an option, a flag, an ordering — by a measurement made
somewhere else: research.md, an earlier task, a scratch file.
Do: reproduce it against the code that will carry the comment, both ways, with the defence and
without it. It does not reproduce → say what is true here instead, and keep the defence only if
something else justifies it. Then write down which of the several things holding the result up
is the load-bearing one, so the next person does not have to find out the same way.
Why: the measurement was taken on a smaller thing than the one that shipped, and the shipped
one usually grew other defences in the meantime. Measured here: `.characterEncoding` on
`NSAttributedString(html:)` was recorded in research as the thing keeping the dots of the legend
whole. In the document actually written it changes nothing — the source declares its encoding in
a `<meta>` tag and writes its marks as numeric entities, either of which is enough on its own —
and a comment calling it the reason would have been a confident false claim about live code,
which is exactly the kind of sentence nobody rechecks.

Date: 2026-09-18 · Source: task app-release, phase 4 (the encoding option of the handout
renderer)
