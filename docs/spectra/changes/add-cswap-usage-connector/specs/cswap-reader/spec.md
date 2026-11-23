## Purpose

The cswap reader is the only part of cswap-connector that runs cswap. It invokes cswap's read-only JSON commands, accepts only JSON contract version 1, and turns every failure into a single fail-open message so no other component has to handle cswap errors itself.

## ADDED Requirements

### Requirement: Reader invokes only read-only cswap commands

The reader SHALL invoke only `cswap list --json` and `cswap auto --once --dry-run --json`. The plugin MUST NOT invoke any other cswap command, including `cswap switch`, `cswap run`, `cswap add`, `cswap remove`, `cswap config set`, or `cswap auto` without `--dry-run`.

#### Scenario: Source contains no state-changing invocation

- **WHEN** the plugin source is searched for cswap invocations
- **THEN** every invocation is `cswap list --json` or `cswap auto --once --dry-run --json`

### Requirement: Reader accepts only schemaVersion 1

The reader SHALL decode cswap's stdout as one JSON object and SHALL accept it only when its `schemaVersion` field equals 1. Any other value, or a missing field, MUST produce the failure `unsupported cswap JSON schemaVersion <value>; update cswap-connector`, where `<value>` is the received value or `missing`.

#### Scenario: Version mismatch is reported, not decoded

- **WHEN** cswap prints a JSON object with `schemaVersion` 2
- **THEN** the reader returns the failure `unsupported cswap JSON schemaVersion 2; update cswap-connector` and decodes no accounts

### Requirement: Reader fails open with one message per failure

The reader SHALL map each failure to exactly one message and SHALL NOT raise or exit non-zero on behalf of a hook. The messages are fixed per condition.

#### Scenario: Each failure condition maps to its message

- **WHEN** the reader runs under one of the conditions below
- **THEN** it returns the listed message and no account data

##### Example: failure messages

| Condition | Message |
| --- | --- |
| `cswap` not on PATH | `cswap not found; install claude-swap to see account usage` |
| cswap prints `{"schemaVersion":1,"error":{"message":"lock busy"}}` and exits 1 | `cswap error: lock busy` |
| cswap exits 1 with no parsable JSON | `cswap error: exit code 1` |
| cswap does not finish within 5 seconds | `cswap did not answer within 5 s` |
| platform is not macOS | `unsupported platform` |

### Requirement: Reader bounds every cswap call by a timeout

The reader SHALL terminate a cswap process that has not exited within 5 seconds and SHALL report the timeout failure. It MUST NOT leave the child process running after it returns.

#### Scenario: Slow cswap is terminated

- **WHEN** a cswap call has not exited after 5 seconds
- **THEN** the reader terminates the process and returns `cswap did not answer within 5 s`

### Requirement: Reader decodes the dry-run outcome

For `cswap auto --once --dry-run --json`, the reader SHALL return one of three outcomes: `switch` with the target account's `number` and `email` and the event's `trigger`, when cswap emits a `switch` event; `blocked`, when the process exits with code 3; or `no-switch` with cswap's `reason`, otherwise on exit code 2.

#### Scenario: Dry-run outcome mapping

- **WHEN** the dry-run tick finishes
- **THEN** the reader returns the outcome mapped from the event and exit code

##### Example: outcomes

| cswap output | Exit code | Outcome |
| --- | --- | --- |
| `switch` event, `to` = {number 2, email "b@example.com"}, trigger "at-limit" | 0 | switch → #2 b@example.com (at-limit) |
| `no-switch` event, reason "below-threshold" | 2 | no-switch (below-threshold) |
| no event | 3 | blocked |
