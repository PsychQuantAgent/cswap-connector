## Purpose

cswap-connector helps the user decide whether to move to another cswap account, without ever moving them. It teaches Claude a propose-only rule through the `cswap-switch` skill and, after a rate-limit failure, passes cswap's own proposed account to Claude and to the user.

## ADDED Requirements

### Requirement: Claude proposes switches and never runs them unasked

The `cswap-switch` skill SHALL instruct Claude to propose a switch by showing `cswap switch <email>` (all sessions) or `cswap run <email>` (this terminal only), to run the command only after the user agrees in the conversation, and to state that on macOS a running session picks the switch up after Claude Code's Keychain cache expires, about 30 seconds.

#### Scenario: Skill content states the rule

- **WHEN** the installed `skills/cswap-switch/SKILL.md` is read
- **THEN** it contains both commands, the requirement to wait for the user's agreement, and the Keychain-cache note

### Requirement: Rate-limit failure records cswap's proposal

The plugin SHALL register a StopFailure command hook with matcher `rate_limit`. The hook SHALL run the reader's dry-run tick. On a `switch` outcome it SHALL write `pending/<session_id>.json` under the plugin data directory, holding the proposed account, the trigger and the creation time, and, when `notified/<session_id>` does not exist under the plugin data directory, SHALL create it and return a `terminalSequence` containing an OSC 9 notification that names the proposed account. A later `switch` outcome in the same session SHALL write the pending file and SHALL NOT return a notification. On `no-switch`, `blocked` or any reader failure it SHALL write nothing and return nothing.

#### Scenario: Burst throttling on an account with quota

- **WHEN** a turn ends with `error` `rate_limit` and the dry-run outcome is `no-switch`
- **THEN** no pending file is written and no notification is emitted

#### Scenario: Active account at its limit

- **WHEN** a turn ends with `error` `rate_limit` and the dry-run outcome is `switch` to account 2 `b@example.com`
- **THEN** `pending/<session_id>.json` names account 2 and the hook returns a `terminalSequence` OSC 9 notification naming `b@example.com`

#### Scenario: Second proposal in the same session

- **WHEN** a second `rate_limit` failure in the same session again yields a `switch` outcome
- **THEN** the pending file is rewritten with the new proposal and the hook returns no `terminalSequence`

### Requirement: The next prompt delivers the proposal once

The plugin SHALL register a UserPromptSubmit command hook that reads `pending/<session_id>.json` for the current session. When the file exists and is at most 30 minutes old, the hook SHALL print the proposal, with both commands and the sentence `Switching happens only after the user agrees.`, as context, and SHALL delete the file. A file older than 30 minutes SHALL be deleted without output. The hook SHALL NOT invoke cswap.

#### Scenario: Proposal delivered and consumed

- **WHEN** the user sends a prompt and a 2-minute-old pending file exists for the session
- **THEN** Claude's context for that prompt contains the proposal, and the file no longer exists

#### Scenario: Expired proposal discarded

- **WHEN** the user sends a prompt and the pending file is 45 minutes old
- **THEN** nothing is added to context and the file is deleted
