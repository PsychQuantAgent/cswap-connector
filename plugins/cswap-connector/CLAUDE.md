# cswap-connector — CLAUDE.md

## Purpose

Shows [claude-swap](https://github.com/realiti4/claude-swap) (`cswap`) account usage to Claude at session start and proposes account switches. Read-only toward cswap's state, propose-only toward the user. Design and decisions: PsychQuantAgent/claude-hot-limit#42.

## Components

| Component | Type | Status |
|-----------|------|--------|
| `/cswap-connector:cswap-switch` | skill | skeleton |
| SessionStart usage injection (`cswap list --json`) | hook | planned |
| StopFailure rate-limit hint (`cswap auto --once --dry-run --json`) | hook | planned |
| `schemaVersion` guard (cswap JSON contract v1) | shared check | planned |

## Boundaries

- Never reimplement cswap's switching or ranking; call its JSON interface.
- Never switch accounts without the user's agreement.
- No dependency from claude-hot-limit on this plugin (limiter integration is claude-hot-limit#43).
- Fail open: missing cswap, errors, timeouts or a `schemaVersion` mismatch produce at most one line, never a blocked session.

## Development

- Plugin structure: see [official plugin-dev](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/plugin-dev)
- Local test: `claude --plugin-dir ./plugins/cswap-connector`
- Update after changes: `/harness-devtools:plugin-update cswap-connector`
- Health check: `/harness-devtools:plugin-health`
