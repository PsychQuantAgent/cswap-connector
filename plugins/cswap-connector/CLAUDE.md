# cswap-connector — CLAUDE.md

## Purpose

Shows [claude-swap](https://github.com/realiti4/claude-swap) (`cswap`) account usage to Claude at session start and proposes account switches. Read-only toward cswap's state, propose-only toward the user. Design and decisions: PsychQuantAgent/claude-hot-limit#42.

## Components

| Component | Type | Status |
|-----------|------|--------|
| `/cswap-connector:cswap-switch` | skill | done |
| SessionStart usage injection (`session-context`, `cswap list --json`) | hook | done |
| StopFailure rate-limit proposal (`stop-failure`, `cswap auto --once --dry-run --json`; one notification per session) | hook | done |
| UserPromptSubmit delivery of the proposal (`pending-hint`; never calls cswap) | hook | done |
| MCP server `cswap` with `cswap_usage` and `cswap_switch_preview` (no switch tool) | mcp | done |
| `schemaVersion` guard, 5 s timeout, fail-open messages (`Reader`) | shared | done |

All four entry points are subcommands of one Swift binary (`Sources/`), reached through `bin/cswap-connector-wrapper.sh`, which downloads the release binary for the plugin version into `${CLAUDE_PLUGIN_DATA}/bin`. Set `CSWAP_CONNECTOR_BIN` to a local build to bypass the download.

## Boundaries

- Never reimplement cswap's switching or ranking; call its JSON interface.
- Never switch accounts without the user's agreement.
- No dependency from claude-hot-limit on this plugin (limiter integration is claude-hot-limit#43).
- Fail open: missing cswap, errors, timeouts or a `schemaVersion` mismatch produce at most one line, never a blocked session.

## Development

- Plugin structure: see [official plugin-dev](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/plugin-dev)
- Tests: `swift test` at the repo root (Swift Testing; includes stdio MCP tests against the built binary)
- Local test: `CSWAP_CONNECTOR_BIN=$PWD/.build/debug/cswap-connector claude --plugin-dir ./plugins/cswap-connector`
- Release: `make release-signed DEVELOPER_ID=<sha1>`, then `gh release create v<version> dist/cswap-connector dist/cswap-connector.sha256`; the tag must match `plugin.json`
- Update after changes: `/harness-devtools:plugin-update cswap-connector`
- Health check: `/harness-devtools:plugin-health`
