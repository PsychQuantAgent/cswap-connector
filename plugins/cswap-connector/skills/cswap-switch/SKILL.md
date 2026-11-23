---
name: cswap-switch
description: |
  Decide whether to switch Claude Code accounts with claude-swap (cswap) and propose the switch — never switch on your own.
  Use when the injected cswap usage shows the active account near a limit, before spending a lot of quota (Fable subagents, a wide Workflow),
  after a rate-limit failure, or when the user asks which account to use. Triggers: switch account, which account, quota left,
  out of usage, 5-hour limit, weekly limit, cswap.
allowed-tools:
  - Bash
  - AskUserQuestion
---

# cswap switch

## Purpose

Skeleton. The behaviour is specified in the Spectra proposal for PsychQuantAgent/claude-hot-limit#42 and filled in during implementation.

Fixed decisions (claude-hot-limit#42, decision comment 2026-11-23):

- Propose only. Claude shows `cswap switch <email>` (or `cswap run <email>` for one terminal) and runs it only after the user agrees.
- Which account to propose comes from cswap itself: `cswap auto --once --dry-run --json`, using the user's `autoswitch.strategy`. The plugin does not rank accounts.
- Accounts are shown by email in local context only; never written to logs or any GitHub egress.
- On macOS a running session picks up a switch after Claude Code's ~30 s Keychain cache expires.

## Execution Steps

### Step 1: TODO

TODO — written from the Spectra proposal.
