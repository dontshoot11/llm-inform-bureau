# Walking up a process chain needs the short form of `proc_pidinfo`

When: reading who started a process — the terminal above a session, anything found by climbing
`ppid`.
Do: ask for `PROC_PIDT_SHORTBSDINFO` (`proc_bsdshortinfo.pbsi_ppid`). Keep the full
`PROC_PIDTBSDINFO` for what only your own process is asked about — its tty (`e_tdev`) and its
start time (`pbi_start_tvsec`).
Why: the full form is refused for a process this app's user does not own, and a session in
Terminal.app sits under root-owned `login`. The walk then stops one step below the application,
which looks exactly like a session nothing owns — no error, no empty result, just a wrong
answer: every Terminal.app session lost its click while VS Code sessions kept theirs, because
their chain is user-owned all the way up. Only a live run over both terminals shows it.

Date: 2026-09-17 · Source: task session-needs-attention, phase 5 (the tab path never fired on
Terminal.app until the probe printed `приложение=нет` for a process whose `ps` chain plainly
ended at Terminal)
