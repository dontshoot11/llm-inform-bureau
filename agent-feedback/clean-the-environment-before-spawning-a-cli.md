# A CLI session spawned from inside one writes nothing until the environment is cleaned

When: driving a real Claude Code session from the agent's own session to measure what the CLI
writes to disk — `~/.claude/sessions/<pid>.json`, a transcript, anything a live run reads.
Do: strip the inherited markers before spawning — `env -u CLAUDE_CODE_CHILD_SESSION -u CLAUDECODE
-u CLAUDE_CODE_SESSION_ID -u CLAUDE_CODE_ENTRYPOINT -u CLAUDE_CODE_SSE_PORT -u
CLAUDE_CODE_MESSAGING_SOCKET -u CLAUDE_CODE_MESSAGING_TOKEN -u CLAUDE_CODE_EXECPATH -u
CLAUDE_CODE_SESSION_ATTENDED -u CLAUDE_PID -u CLAUDE_EFFORT claude …`. Spawn it through a pty
(`expect`; `script` refuses a fifo for stdin), and send input in two steps — the line, a pause,
then `\r`: a long line sent in one piece reads as a paste and the turn never starts.
Why: a child session inherits `CLAUDE_CODE_CHILD_SESSION`, and with it the CLI turns transcript
saving off and writes no session record at all — only the `.key` file beside it. Two measurements
were read as "the CLI writes nothing while this dialog is open" before the banner in the TUI
("Transcript saving is off — inherited CLAUDE_CODE_CHILD_SESSION marker") explained it. The
absence looks exactly like a finding about the thing being measured.

Date: 2026-09-17 · Source: task session-needs-attention, phase 3 (two probes thrown away before
the permission prompt could be measured)
