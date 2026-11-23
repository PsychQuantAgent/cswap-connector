# cswap-connector

A Claude Code plugin that connects to [claude-swap](https://github.com/realiti4/claude-swap) (`cswap`), a multi-account switcher for Claude Code subscriptions.

- At session start, Claude sees which account is active and how much 5-hour, weekly and per-model quota each account has left.
- When an account is near its limit, Claude proposes the switch cswap itself would make, and runs it only after you agree.

This repo is both the plugin and a single-plugin marketplace.

> **Status: 0.1.0 skeleton.** Hooks and the skill body are not implemented yet. Design: [PsychQuantAgent/claude-hot-limit#42](https://github.com/PsychQuantAgent/claude-hot-limit/issues/42).

## Requirements

- [claude-swap](https://github.com/realiti4/claude-swap) installed (`uv tool install claude-swap`) with at least one account added.

## Install

```bash
claude plugin marketplace add PsychQuantAgent/cswap-connector
claude plugin install cswap-connector@cswap-connector
```

## License

To be decided.
