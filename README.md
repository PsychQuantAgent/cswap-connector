# cswap-connector

A Claude Code plugin that connects to [claude-swap](https://github.com/realiti4/claude-swap) (`cswap`), a multi-account switcher for Claude Code subscriptions.

- **At session start**, Claude sees which account is active and how much 5-hour, weekly and per-model quota each account has left, with reset times.
- **Mid-session**, Claude can re-check through two read-only MCP tools: `cswap_usage` and `cswap_switch_preview`.
- **After a rate-limit failure**, if cswap's own auto-switch strategy would move to another account, you get one desktop notification per session, and Claude proposes that account on your next message.

The plugin never switches accounts. Claude shows `cswap switch <email>` (all sessions) or `cswap run <email>` (this terminal only) and runs it only after you agree. Spending another account's quota is your decision.

This repo is both the plugin and a single-plugin marketplace. Design: [PsychQuantAgent/claude-hot-limit#42](https://github.com/PsychQuantAgent/claude-hot-limit/issues/42).

## Requirements

- macOS.
- [claude-swap](https://github.com/realiti4/claude-swap) 1.x (`uv tool install claude-swap`) with at least one account added. Its JSON contract `schemaVersion: 1` is the only one supported.

## Install

```bash
claude plugin marketplace add PsychQuantAgent/cswap-connector
claude plugin install cswap-connector@cswap-connector
```

On first use the plugin downloads its signed, notarized binary from this repo's GitHub Release for the installed version and checks it against the published SHA-256.

## What it does and does not touch

- Runs only `cswap list --json` and `cswap auto --once --dry-run --json`. Neither changes cswap's state.
- Every failure (cswap missing, an error, a 5-second timeout, an unsupported version) produces at most one line and never blocks a session.
- Writes only under the plugin data directory: the downloaded binary, and a short-lived proposal file per session that is deleted when delivered or after 30 minutes.
- Sends nothing over the network itself, apart from downloading its own binary; cswap does its usual usage queries.

## Development

```bash
swift test                                  # unit + stdio MCP tests
CSWAP_CONNECTOR_BIN=$PWD/.build/debug/cswap-connector \
  claude --plugin-dir ./plugins/cswap-connector
make release-signed DEVELOPER_ID=<sha1>     # universal build, sign, notarize, checksum
```

## License

To be decided.
