---
name: cswap-switch
description: |
  Decide whether to switch Claude Code accounts with claude-swap (cswap) and propose the switch — never switch on your own.
  Use when the injected cswap usage shows the active account near a limit, before spending a lot of quota (Fable subagents, a wide Workflow),
  after a rate-limit failure, or when the user asks which account to use. Triggers: switch account, which account, quota left,
  out of usage, 5-hour limit, weekly limit, Fable limit, rate limited, cswap.
allowed-tools:
  - Bash
  - AskUserQuestion
---

# cswap switch

cswap-connector shows Claude how much quota each cswap account has left and which account cswap itself would move to. This skill says how to use that information. One rule never bends: **Claude proposes a switch; the user decides; Claude runs the command only after the user agrees in the conversation.** Moving to another account spends that account's quota, and that is the user's call.

## Where the numbers come from

| Source | When | What it shows |
|---|---|---|
| The `cswap accounts` block in context | Every session start, `/clear`, compaction, resume, fork | Each account: active marker `*`, plan, `5h` / `7d` / per-model windows with reset times. `(as of N min ago)` marks a stale reading. |
| MCP tool `cswap_usage` | Any time mid-session | The same block, plus the accounts as JSON |
| MCP tool `cswap_switch_preview` | Any time mid-session | `switch` with cswap's proposed account, `no-switch`, or `blocked` (every account exhausted) |
| A `cswap proposes switching to account …` note before a prompt | After a rate-limit failure in this session | cswap's proposal, recorded when the failure happened |

A line starting with `cswap-connector:` means cswap could not be read: it is not installed, it returned an error or timed out, or its version is unsupported. Say so in one sentence and carry on; do not retry in a loop.

## When to look before acting

Check the block, or call `cswap_usage` if the block is old, before:

- dispatching Fable subagents, or anything else on a model whose per-model window (for example `Fable 100%`) is at or near its limit;
- launching a wide Workflow or several parallel agents;
- starting long work when the active account's `5h` or `7d` window is above roughly 90%.

If the active account will not last, tell the user which window is the problem and when it resets, then call `cswap_switch_preview`.

## How to propose

Use cswap's own choice, from `cswap_switch_preview` or from the rate-limit note. Do not rank accounts yourself. Show both commands and let the user choose:

- `cswap switch <email>`: switches the login for **all** Claude Code sessions on this machine.
- `cswap run <email>`: runs one Claude Code process as that account, **in this terminal only**.

Then ask, for example with AskUserQuestion: switch for all sessions, this terminal only, or stay. Run the chosen command only after the user agrees. Never run `cswap switch` or `cswap run` because a preview, a note or a high percentage suggested it.

If the preview says `no-switch`, a rate limit was probably short-burst throttling rather than exhausted quota: wait and retry instead of proposing a switch. If it says `blocked`, every account is exhausted; report the earliest reset time.

## After a switch

On macOS, Claude Code caches the Keychain login for about 30 seconds, so a running session picks up the new account within about half a minute; restarting Claude Code applies it at once. `cswap switch N` for the account that is already active does nothing, which is expected.
