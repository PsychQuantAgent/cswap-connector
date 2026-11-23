## Purpose

cswap-connector runs a stdio MCP server so Claude can check account quota and cswap's proposed switch target in the middle of a session. The server is read-only: it has no tool that switches accounts.

## ADDED Requirements

### Requirement: MCP server exposes exactly two read-only tools

The plugin SHALL declare a stdio MCP server named `cswap` that lists exactly two tools, `cswap_usage` and `cswap_switch_preview`. Neither tool SHALL require input. The server MUST NOT expose any tool that changes cswap or Claude Code state.

#### Scenario: Tool list

- **WHEN** a client calls `tools/list` on the server
- **THEN** the result contains exactly the tools `cswap_usage` and `cswap_switch_preview`

### Requirement: cswap_usage returns the accounts block and decoded data

`cswap_usage` SHALL return two text content items: first the same `cswap accounts` block that SessionStart injects, then a JSON array with one object per account holding `number`, `email`, `active`, `plan` and its windows.

#### Scenario: Usage tool on a working cswap

- **WHEN** Claude calls `cswap_usage` and `cswap list --json` succeeds
- **THEN** the first content item starts with `cswap accounts` and the second parses as a JSON array whose length equals the number of accounts

### Requirement: cswap_switch_preview reports cswap's own choice

`cswap_switch_preview` SHALL return the reader's dry-run outcome. A `switch` result SHALL end with the commands `cswap switch <email>` and `cswap run <email>`, and with the sentence `Switching happens only after the user agrees.`

#### Scenario: Preview proposes without switching

- **WHEN** the dry-run outcome is `switch` to account 2 `b@example.com`
- **THEN** the tool result names account 2, contains `cswap switch b@example.com` and `cswap run b@example.com`, and the active account in `cswap list --json` is unchanged afterwards

### Requirement: Tool failures are reported as tool errors

On a reader failure, either tool SHALL return a result with `isError` true whose text is `cswap-connector: <reader message>`, and the server SHALL keep running.

#### Scenario: Schema mismatch during a session

- **WHEN** Claude calls `cswap_usage` and cswap reports `schemaVersion` 2
- **THEN** the result has `isError` true with text `cswap-connector: unsupported cswap JSON schemaVersion 2; update cswap-connector`, and a later `tools/list` still answers
