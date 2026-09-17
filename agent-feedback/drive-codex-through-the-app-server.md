# A live Codex measurement goes through the app server, not through its TUI

When: making a real Codex session do something — hold an approval prompt open, reach a state —
to see what the CLI writes to disk.
Do: drive `codex app-server` over stdio (JSON-RPC, one message per line): `initialize` →
`initialized` → `thread/start` (`cwd`, `approvalPolicy: "on-request"`, `sandbox: "read-only"`,
`approvalsReviewer: "user"`; the reply carries the id as `result.thread.id`) → `turn/start`
with `threadId` and `input: [{type: "text", text: …}]`. To hold a request open, simply do not
answer the server's `item/commandExecution/requestApproval` — it stands for as long as the
files need reading. Give `CODEX_HOME` an explicit path in a temporary directory, so the
rollout of the probe is the only one there. `codex app-server generate-json-schema --out <dir>`
prints the whole protocol when a param is in doubt.
Why: the TUI does not start from an agent's session at all — under `expect` and under `screen`
it draws its welcome frame and stays in "model: loading / directory: loading" forever, creating
no session and writing no rollout (a clean `CODEX_HOME` and answering the terminal capability
queries change nothing). `codex exec` fails from the other side: approvals are off there, so a
real request becomes an instant `rejected by user approval settings`. Both look like findings
about Codex and are findings about the probe.

Date: 2026-09-17 · Source: task session-needs-attention, phase 4 (five TUI attempts before the
approval prompt could be held open)
