# A watcher started from a tool call dies with it, and its empty log proves nothing

When: watching for something the app does while you wait — a notification going up, a file
being written, a process appearing — during a live run of this app.
Do: arm the watcher through the harness (`Monitor`, or `Bash` with `run_in_background`), never
as `nohup … &` inside an ordinary Bash call. That shell is reaped when the call returns, so the
loop stops sampling seconds after it starts. And before reading silence as evidence, check the
watcher is still alive (`ps -eo pid,comm | grep '[w]atch-'`): an empty log written by a dead
watcher and an empty log written by an app that said nothing look exactly the same.
Why: two live cases of "the notification stayed silent" were recorded here against a watcher
that had been dead for minutes. The check was rerun; the app was right both times, and the
evidence had been worthless.

Also worth knowing before instrumenting notifications: the notification centre's own database
(`~/Library/Group Containers/group.com.apple.usernoted/db2/db`) is refused by TCC, and
`log show` returns nothing for `osascript` or `usernoted`. Sampling the process table catches
an `osascript` banner only if it outlives the poll interval, which it may not — so the person
in front of the screen is a legitimate witness, and the report should say which of the two saw
it.

Дата: 2026-09-17 · Источник: session-needs-attention, фаза 2 (прогон уведомления)
