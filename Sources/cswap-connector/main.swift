import CswapCore
import Foundation

let usage = """
usage: cswap-connector <subcommand>

Subcommands:
  session-context   SessionStart hook: print the cswap accounts block as additional context
  stop-failure      StopFailure hook: record cswap's proposed account after a rate limit
  pending-hint      UserPromptSubmit hook: hand a recorded proposal to Claude once
  mcp               Run the read-only stdio MCP server (cswap_usage, cswap_switch_preview)
"""

/// Hooks must never block a session: every subcommand exits 0.
func readStdin() -> Data {
    FileHandle.standardInput.readDataToEndOfFile()
}

func pluginDataRoot() -> URL {
    if let dir = ProcessInfo.processInfo.environment["CLAUDE_PLUGIN_DATA"], !dir.isEmpty {
        return URL(fileURLWithPath: dir)
    }
    return FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/plugins/data/cswap-connector")
}

func emit(_ text: String) {
    guard !text.isEmpty else { return }
    FileHandle.standardOutput.write(Data((text + "\n").utf8))
}

let arguments = CommandLine.arguments.dropFirst()
switch arguments.first {
case "session-context":
    emit(SessionContext.output(reader: Reader()))
case "stop-failure":
    let input = HookInput.read(from: readStdin())
    emit(StopFailureHook.handle(error: input.error, sessionID: input.sessionID, reader: Reader(), store: PendingStore(root: pluginDataRoot())))
case "pending-hint":
    let input = HookInput.read(from: readStdin())
    emit(PendingHintHook.handle(sessionID: input.sessionID, store: PendingStore(root: pluginDataRoot())))
case "mcp":
    try await MCPServer.run()
case "--help", "-h", "help", nil:
    print(usage)
default:
    FileHandle.standardError.write(Data("unknown subcommand\n\(usage)\n".utf8))
}
exit(0)
