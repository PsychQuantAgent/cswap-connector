## Why

People who run several Claude Code subscriptions with [claude-swap](https://github.com/realiti4/claude-swap) (`cswap`) can switch accounts, but Claude itself cannot see how much quota each account has left. It finds out only when a request fails, typically in the middle of a long task or right after dispatching Fable subagents. cswap already knows the numbers and already decides which account it would switch to; nothing hands that knowledge to Claude. Design and decisions: PsychQuantAgent/claude-hot-limit#42 and PsychQuantAgent/cswap-connector#1.

## What Changes

- Add a reader that calls cswap's JSON interface (`cswap list --json`, `cswap auto --once --dry-run --json`). It accepts only `schemaVersion: 1` and fails open: a missing cswap, an error payload, a non-zero exit, a timeout or a schema mismatch produce at most one plain line and never block the session.
- Add a SessionStart hook that injects the active account (shown by email) and every account's 5-hour, 7-day and per-model usage, with reset times, into the session context. Readings older than cswap's trusted window are labelled with their age.
- Add a stdio MCP server with two read-only tools: list account usage, and preview the account cswap would switch to. There is no tool that switches accounts.
- Fill in the `cswap-switch` skill: when to read usage, how to propose `cswap switch <email>` or `cswap run <email>`, the rule that Claude runs the command only after the user agrees, and the macOS Keychain-cache delay (about 30 seconds).
- Add an optional StopFailure hook: after a rate-limit failure it runs cswap's dry-run tick and names the proposed account only when cswap reports a `switch` event; it stays silent on `no-switch`, so short-burst throttling on an account with quota left does not produce a switch suggestion.
- Bump the plugin from the 0.1.0 skeleton to a working release.

## Non-Goals (optional)

Listed in design.md.

## Capabilities

### New Capabilities

- `cswap-reader`: invoking cswap's JSON commands, validating `schemaVersion`, timeouts, and the fail-open contract shared by every other component.
- `session-usage-context`: what the SessionStart hook injects, its format, staleness labelling, and its behaviour when cswap is unavailable.
- `usage-mcp-tools`: the two read-only MCP tools, their inputs and outputs, and the absence of any switching tool.
- `switch-proposal`: the propose-only switching rule as taught by the `cswap-switch` skill, and the StopFailure rate-limit hint.

### Modified Capabilities

(none)

## Impact

- New files under plugins/cswap-connector: hook definitions, the MCP server declaration, the filled-in skills/cswap-switch/SKILL.md, and a Swift package for the reader binary.
- Distribution: the binary ships as a GitHub Release asset of PsychQuantAgent/cswap-connector, signed and notarized with the existing Developer ID pipeline, and fetched by a wrapper script on first use.
- Runtime dependency: cswap 1.x on PATH (JSON contract `schemaVersion: 1`). No dependency on claude-hot-limit; the limiter integration is tracked separately in PsychQuantAgent/claude-hot-limit#43.
- Privacy: account emails reach only the local session context and MCP tool results; the plugin performs no network egress of its own beyond what cswap does.
