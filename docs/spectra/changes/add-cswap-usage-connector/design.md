## Context

cswap (claude-swap 1.x) manages several Claude Code subscriptions on one machine. Its JSON contract (`docs/json-output.md` upstream, `schemaVersion: 1`) gives two read-only entry points this change relies on:

- `cswap list --json`: one object with every account's `usage` (`fiveHour`, `sevenDay`, per-model `scoped` windows, each with `pct` and `resetsAt`), plus `usageStatus`, `usageAgeSeconds`, `lastGoodUsage`, `plan`, `alias`, and which account is active. Handled errors print `{"schemaVersion":1,"error":{...}}` and exit non-zero.
- `cswap auto --once --dry-run --json`: one tick of cswap's real auto-switch engine with the user's `autoswitch.strategy`. It never writes state, emits a `switch` event (`trigger`, `from`, `to` with `number` and `email`, `warnings`, `dryRun: true`) or a `no-switch` event (`reason`), and its exit code encodes the outcome (`0` would switch, `2` nothing to do, `3` blocked, `1` error).

Measured on the maintainer's machine (2026-11-23, cswap 1.2.0, 3 accounts): `cswap list --json` returned in 0.15 s on two consecutive warm calls; the first call of the day took noticeably longer because it fetched usage from Anthropic. These are two measurements on one machine, not a latency guarantee.

Claude Code facts this design depends on (code.claude.com/docs/en/hooks.md and mcp.md, read 2026-11-23):

- A `SessionStart` command hook's plain stdout, or `hookSpecificOutput.additionalContext`, is added to Claude's context. At launch, SessionStart `mcp_tool` hooks are skipped because MCP servers are not yet available, so the launch injection must be a `command` hook.
- `StopFailure` fires when a turn ends on an API error, with `error` (for example `rate_limit`; an HTTP 529 is `server_error`) usable as the matcher. Claude Code ignores its output and exit code except `terminalSequence`, so it cannot talk to Claude directly.
- `UserPromptSubmit` command hooks can add context and default to a 30 s timeout; they run before every prompt.
- Plugin stdio MCP servers start with the session and stop with it. With tool search on by default, their tools are deferred, so only tool names sit in context until used.

Decisions already made by the maintainer (claude-hot-limit#42, cswap-connector#1): separate plugin; propose-only switching; accounts shown by email; switch target comes from cswap's own strategy; a read-only MCP with no switch tool; claude-hot-limit takes no dependency on this plugin.

## Goals / Non-Goals

**Goals:**

- Claude sees every account's remaining quota at session start and can re-query it mid-session.
- After a rate-limit failure, Claude and the user see which account cswap would switch to, without any account being switched.
- Every failure of cswap or of the reader leaves the session usable and costs at most one line of text.

**Non-Goals:**

- Switching accounts automatically, or exposing any tool or hook that switches. Rejected because spending another account's quota is the user's decision.
- Re-implementing cswap's ranking or strategies, including a fallback ranking. Rejected because a second copy drifts from cswap's behaviour.
- Polling usage in the background, caching usage ourselves, or running a daemon. cswap already caches per account.
- Integrating with claude-hot-limit's usage limiter (tracked in claude-hot-limit#43).
- Supporting cswap JSON `schemaVersion` values other than 1.
- Windows and Linux support in the first release. The binary is built for macOS; other platforms get the fail-open "cswap-connector: unsupported platform" line.

## Decisions

### One Swift binary with subcommands for every component

A single executable `cswap-connector` provides `session-context` (SessionStart), `stop-failure` (StopFailure), `pending-hint` (UserPromptSubmit) and `mcp` (stdio MCP server). All four go through one reader module, so the `schemaVersion` guard, the timeouts and the fail-open rules exist exactly once.

Alternatives: shell + `jq` hooks with a separate MCP server would duplicate the guard in two languages; a Python server adds an interpreter dependency and conflicts with the maintainer's preference for Swift for CLIs and parsers. The reader only decodes cswap's JSON with `Codable`; it does not parse cswap's human output.

### MCP server built on the official Swift SDK

The `mcp` subcommand uses `modelcontextprotocol/swift-sdk` (0.12.x, the version already used by che-word-mcp) over stdio. The plugin declares it in its `.mcp.json` through the wrapper script, so the scoped server name is `plugin:cswap-connector:cswap`.

### Release binary fetched by a wrapper script

`plugins/cswap-connector/bin/cswap-connector-wrapper.sh` resolves the binary in `${CLAUDE_PLUGIN_DATA}/bin`. When it is missing or older than the plugin version, the script downloads the matching GitHub Release asset from PsychQuantAgent/cswap-connector and verifies its `.sha256`. Hooks and the MCP declaration call the wrapper, never the binary path directly. The universal binary is signed with the maintainer's Developer ID and notarized with the existing `che-mcps-notary` profile. It needs no TCC permission; notarization keeps Gatekeeper from blocking a downloaded binary.

Alternative: committing the binary into the repo. Rejected because it bloats history and bypasses signing per release.

### Rate-limit hint delivered through a pending-hint file and a terminal notification

Because StopFailure output cannot reach Claude, the `stop-failure` subcommand (matcher `rate_limit`) runs the dry-run tick. On a `switch` event it does two things:

- it writes `${CLAUDE_PLUGIN_DATA}/pending/<session_id>.json` holding the proposed account and the time;
- it returns `terminalSequence` with an OSC 9 desktop notification naming the proposed account, but only for the first `switch` event in the session. It records that by creating `${CLAUDE_PLUGIN_DATA}/notified/<session_id>`; later events in the same session still write the pending file, so Claude still sees each proposal, but send no notification (maintainer decision, 2026-11-23).

On the next prompt in that session, the `pending-hint` subcommand (UserPromptSubmit) prints the hint as context once and deletes the file. Files older than 30 minutes are ignored and deleted. The 30 minutes is a chosen bound, not a measured one. `pending-hint` never calls cswap; it only checks for one file, so it adds no network latency to prompts.

Alternative: calling cswap on every UserPromptSubmit. Rejected because it would run network-bound work before every prompt.

### SessionStart injection runs on every session source

The `session-context` hook matches `startup|resume|clear|compact|fork`, because `/clear` and compaction drop the earlier injection from context. It has its own 8-second hook timeout; the reader gives `cswap list --json` 5 seconds. Both numbers are chosen bounds; the 0.15 s warm measurement above suggests they are generous, which is unconfirmed for a cold fetch over a slow network.

### Propose-only rule lives in the skill and in every output

Every text the plugin produces that names an account to switch to ends with the exact command, `cswap switch <email>` (all sessions) or `cswap run <email>` (this terminal only), and the sentence that the switch happens only after the user agrees. The `cswap-switch` skill states the same rule for Claude, and the macOS note that a running session picks the switch up after Claude Code's Keychain cache expires (about 30 seconds per cswap's README).

## Implementation Contract

**Behaviour:**

- At session start, Claude's context contains a block headed `cswap accounts` listing, per account: number, email, a marker on the active account, plan label, and each present window as `pct%` with its reset time in the machine's local time zone. A reading whose `usageStatus` is not `ok` is shown from `lastGoodUsage` with its age (`as of N min ago`), or as `usage unavailable (<usageError>)` when none exists.
- The MCP server exposes exactly two tools, `cswap_usage` and `cswap_switch_preview`, both without required input. `cswap_usage` returns the same block as text plus the decoded accounts as JSON. `cswap_switch_preview` returns `switch` with the proposed account, `no-switch` with cswap's reason, or `blocked`.
- After a turn ends with `error: rate_limit`, if cswap's dry-run reports `switch`, Claude sees the proposal on the next prompt, and the user gets a desktop notification the first time this happens in the session; otherwise nothing is shown.

**Interfaces / data shapes:**

- `cswap-connector session-context`: reads the hook JSON on stdin and writes `{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"<block>"}}` on stdout.
- `cswap-connector stop-failure`: reads the hook JSON (`session_id`, `error`). It writes the pending file on every dry-run `switch`, and prints `{"terminalSequence":"<OSC 9>"}` only when `notified/<session_id>` does not exist yet, creating it at the same time.
- `cswap-connector pending-hint`: reads the hook JSON (`session_id`). It prints the hint as plain text and deletes the file, or prints nothing.
- `cswap-connector mcp`: a stdio MCP server.
- Pending file: `{"proposed":{"number":<int>,"email":"<string>"},"trigger":"<string>","createdAt":"<ISO-8601>"}`.

**Failure modes (all fail open, exit 0, at most one line):**

| Condition | Session-start output | MCP tool result |
|---|---|---|
| cswap not on PATH | `cswap-connector: cswap not found; install claude-swap to see account usage` | `isError` text with the same message |
| cswap exits non-zero or prints an `error` payload | `cswap-connector: cswap error: <error.message or exit code>` | `isError` with the same text |
| reader timeout | `cswap-connector: cswap did not answer within 5 s` | `isError` with the same text |
| `schemaVersion` missing or not 1 | `cswap-connector: unsupported cswap JSON schemaVersion <v>; update cswap-connector` | `isError` with the same text |
| unsupported platform | `cswap-connector: unsupported platform` | `isError` with the same text |

The StopFailure and UserPromptSubmit paths print nothing in all of these cases.

**Acceptance criteria:**

- `swift test` passes fixture tests for every row of the failure table and for: one active `ok` account; a stale reading; an Ultra account without `fiveHour`; a scoped Fable window; dry-run `switch`, `no-switch` and `blocked`.
- A manual check with cswap installed and the plugin loaded through `claude --plugin-dir ./plugins/cswap-connector` shows the `cswap accounts` block at session start and both MCP tools in `/mcp`.
- A search of the source finds no invocation of `cswap switch`, `cswap run`, `cswap auto` without `--dry-run`, or any other state-changing cswap command.

**Scope boundaries:**

- In scope: the binary, wrapper, hook and MCP declarations, the skill body, fixture tests, a release workflow, and README install and usage notes.
- Out of scope: claude-hot-limit changes, any switching action, background polling, other platforms.

## Risks / Trade-offs

- [cswap changes its JSON or bumps `schemaVersion`] → The guard disables the plugin with a one-line message; a cswap-connector update restores it. Fixtures pin the version-1 shape.
- [Cold `cswap list` is slow on a bad network] → 5 s reader timeout and 8 s hook timeout; on timeout the session starts with one line instead of the block.
- [`cswap list` may refresh OAuth tokens] → cswap takes Claude Code's own credential locks; the plugin never touches credentials itself.
- [Emails in local transcripts] → Accepted by the maintainer. The plugin sends nothing over the network and writes emails only to the pending file under `${CLAUDE_PLUGIN_DATA}`, which is deleted on use or after 30 minutes.
- [Desktop notification support varies by terminal] → OSC 9 is ignored by terminals that do not support it; Claude still sees the proposal on the next prompt.
- [Wrapper download fails offline] → The wrapper prints the one-line failure and exits 0; the plugin stays inert until the next successful download.

## Migration Plan

The 0.1.0 skeleton is replaced in place, with no persisted state to migrate. Release: tag the version, attach the signed universal binary and its `.sha256`, bump `plugin.json` and the root `marketplace.json`, and push. Rollback: users pin the previous plugin version, or uninstall; the plugin leaves nothing outside `${CLAUDE_PLUGIN_DATA}`.

## Open Questions

(none) — the notification frequency was decided on 2026-11-23: one desktop notification per session, on the first `switch` event.
