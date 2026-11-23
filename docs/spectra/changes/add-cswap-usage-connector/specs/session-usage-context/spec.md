## Purpose

At the start of every session, and again after `/clear`, compaction, resume or fork, cswap-connector adds a short block to Claude's context that lists each cswap account's remaining quota, so Claude can plan around quota before spending it.

## ADDED Requirements

### Requirement: SessionStart injects the cswap accounts block

The plugin SHALL register a SessionStart command hook for the sources `startup`, `resume`, `clear`, `compact` and `fork`. On success it SHALL output `hookSpecificOutput.additionalContext` containing a block that starts with the line `cswap accounts` and has one line per account in cswap's order.

#### Scenario: Accounts block lists every account

- **WHEN** a session starts and `cswap list --json` returns three accounts with `usageStatus` `ok`
- **THEN** the additional context starts with `cswap accounts` and contains three account lines

##### Example: one line per account

- **GIVEN** account 3 `c@example.com` is active, plan `Ultra`, no `fiveHour` window, `sevenDay` 85.0 % resetting 2026-11-25T03:00:00Z, scoped `Fable` 100.0 % resetting 2026-11-25T03:00:00Z, and the machine's time zone is Asia/Taipei
- **WHEN** the block is rendered
- **THEN** the line for account 3 reads `* 3 c@example.com (active) · Ultra · 7d 85% (resets 11-25 11:00) · Fable 100% (resets 11-25 11:00)`

### Requirement: Account lines show only windows the account has

Each account line SHALL include a window only when cswap reports it. A window whose `pct` is null SHALL be shown as `n/a`. An account without a `fiveHour` window SHALL NOT show a 5-hour entry.

#### Scenario: Ultra account without a 5-hour window

- **WHEN** an account's `usage` has no `fiveHour` key
- **THEN** its line contains no `5h` entry

### Requirement: Stale or unavailable usage is labelled

When an account's `usageStatus` is not `ok`, its line SHALL use `lastGoodUsage` and append `(as of N min ago)`, where N is `lastGoodAgeSeconds` divided by 60 and rounded down. When `lastGoodUsage` is absent, the line SHALL show `usage unavailable (<usageError>)`, with `unknown` when `usageError` is absent.

#### Scenario: Stale reading is not shown as fresh

- **WHEN** an account has `usageStatus` `unavailable`, `lastGoodUsage` present and `lastGoodAgeSeconds` 754
- **THEN** its line ends with `(as of 12 min ago)`

### Requirement: SessionStart fails open

On any reader failure the hook SHALL output only the line `cswap-connector: <reader message>` as additional context, SHALL exit with code 0, and SHALL NOT delay the session beyond its 8-second hook timeout.

#### Scenario: cswap missing

- **WHEN** a session starts on a machine without cswap
- **THEN** the additional context is exactly `cswap-connector: cswap not found; install claude-swap to see account usage`
