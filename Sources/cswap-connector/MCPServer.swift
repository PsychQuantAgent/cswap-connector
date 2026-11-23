import CswapCore
import Foundation
import MCP

/// Read-only stdio MCP server. Exposes exactly the tools in `UsageTools.names`.
enum MCPServer {
    static let version = "0.2.0"

    static var tools: [Tool] {
        let noInput: Value = .object(["type": .string("object"), "properties": .object([:])])
        return [
            Tool(name: UsageTools.usageName, description: UsageTools.usageDescription, inputSchema: noInput),
            Tool(name: UsageTools.previewName, description: UsageTools.previewDescription, inputSchema: noInput),
        ]
    }

    static func call(_ name: String) -> CallTool.Result {
        let output: ToolOutput
        switch name {
        case UsageTools.usageName: output = UsageTools.usage(reader: Reader())
        case UsageTools.previewName: output = UsageTools.preview(reader: Reader())
        default: return CallTool.Result(content: [.text(text: "unknown tool: \(name)", annotations: nil, _meta: nil)], isError: true)
        }
        return CallTool.Result(content: output.texts.map { .text(text: $0, annotations: nil, _meta: nil) }, isError: output.isError)
    }

    static func run() async throws {
        let server = Server(
            name: "cswap-connector",
            version: version,
            instructions: "Read-only view of claude-swap (cswap) accounts. Never switches accounts; propose `cswap switch <email>` and wait for the user.",
            capabilities: .init(tools: .init())
        )
        let tools = Self.tools
        await server.withMethodHandler(ListTools.self) { _ in ListTools.Result(tools: tools) }
        await server.withMethodHandler(CallTool.self) { params in Self.call(params.name) }
        try await server.start(transport: StdioTransport())
        await server.waitUntilCompleted()
    }
}
