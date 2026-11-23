import Foundation
import Testing
@testable import CswapCore

/// Drives the built `cswap-connector mcp` binary over stdio, with a fake `cswap` on PATH.
@Suite(.serialized)
final class MCPTests {
    let dir = temporaryDirectory()

    static var binary: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/debug/cswap-connector")
    }

    /// Writes a fake cswap that prints `list` / `auto` fixtures; `listOverride` replaces the list output.
    func installFakeCswap(listOverride: String? = nil, autoFixture: String = "dryrun_switch.jsonl", autoExit: Int = 0) throws {
        let list = dir.appendingPathComponent("list.json")
        try (listOverride ?? Fixture.text("list_ok.json")).write(to: list, atomically: true, encoding: .utf8)
        let auto = dir.appendingPathComponent("auto.jsonl")
        try Fixture.text(autoFixture).write(to: auto, atomically: true, encoding: .utf8)
        let script = dir.appendingPathComponent("cswap")
        try """
        #!/bin/sh
        case "$1" in
          list) cat "\(list.path)" ;;
          auto) cat "\(auto.path)"; exit \(autoExit) ;;
          *) echo "unexpected cswap call: $*" >&2; exit 99 ;;
        esac
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
    }

    /// Sends JSON-RPC lines and returns the responses keyed by id.
    func exchange(_ requests: [[String: Any]]) throws -> [Int: [String: Any]] {
        let process = Process()
        process.executableURL = Self.binary
        process.arguments = ["mcp"]
        process.environment = ["PATH": "\(dir.path):/usr/bin:/bin", "HOME": dir.path]
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()

        let initialize: [String: Any] = [
            "jsonrpc": "2.0", "id": 0, "method": "initialize",
            "params": ["protocolVersion": "2025-06-18", "capabilities": [:] as [String: Any], "clientInfo": ["name": "test", "version": "1"]],
        ]
        let initialized: [String: Any] = ["jsonrpc": "2.0", "method": "notifications/initialized"]

        // Collect stdout as it arrives, then wait until every request id has an answer.
        let collected = OutputCollector()
        output.fileHandleForReading.readabilityHandler = { handle in
            collected.append(handle.availableData)
        }
        func parsed() -> [Int: [String: Any]] {
            var responses: [Int: [String: Any]] = [:]
            for line in String(decoding: collected.get(), as: UTF8.self).split(separator: "\n") {
                if let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                   let id = object["id"] as? Int {
                    responses[id] = object
                }
            }
            return responses
        }
        func send(_ message: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: message)
            data.append(0x0A)
            input.fileHandleForWriting.write(data)
        }
        func waitFor(_ ids: Set<Int>) {
            let deadline = Date().addingTimeInterval(10)
            while !ids.isSubset(of: Set(parsed().keys)) && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        }

        try send(initialize)
        waitFor([0])
        try send(initialized)
        for request in requests { try send(request) }
        waitFor(Set(requests.compactMap { $0["id"] as? Int }))
        output.fileHandleForReading.readabilityHandler = nil
        try input.fileHandleForWriting.close()
        process.terminate()
        process.waitUntilExit()
        let responses = parsed()
        return responses
    }

    func call(_ id: Int, _ name: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "method": "tools/call", "params": ["name": name, "arguments": [:] as [String: Any]]]
    }

    func texts(_ response: [String: Any]?) throws -> (texts: [String], isError: Bool) {
        let result = try #require(response?["result"] as? [String: Any])
        let content = try #require(result["content"] as? [[String: Any]])
        return (content.compactMap { $0["text"] as? String }, (result["isError"] as? Bool) ?? false)
    }

    @Test func `Tool list has exactly the two read-only tools`() throws {
        try installFakeCswap()
        let responses = try exchange([["jsonrpc": "2.0", "id": 1, "method": "tools/list"]])
        let result = try #require(responses[1]?["result"] as? [String: Any])
        let tools = try #require(result["tools"] as? [[String: Any]])
        #expect(Set(tools.compactMap { $0["name"] as? String }) == ["cswap_usage", "cswap_switch_preview"])
        #expect(tools.count == 2)
    }

    @Test func `Usage tool returns the block and a JSON array`() throws {
        try installFakeCswap()
        let (out, isError) = try texts(exchange([call(1, "cswap_usage")])[1])
        #expect(!isError)
        #expect(out.count == 2)
        #expect(out.first?.hasPrefix("cswap accounts") == true)
        let array = try #require(JSONSerialization.jsonObject(with: Data(out[1].utf8)) as? [[String: Any]])
        #expect(array.count == 3)
    }

    @Test func `Schema mismatch is a tool error and the server keeps answering`() throws {
        try installFakeCswap(listOverride: #"{"schemaVersion":2,"accounts":[]}"#)
        let responses = try exchange([call(1, "cswap_usage"), ["jsonrpc": "2.0", "id": 2, "method": "tools/list"]])
        let (out, isError) = try texts(responses[1])
        #expect(isError)
        #expect(out == ["cswap-connector: unsupported cswap JSON schemaVersion 2; update cswap-connector"])
        #expect(responses[2]?["result"] != nil)
    }

    @Test func `Switch preview proposes without switching`() throws {
        try installFakeCswap()
        let (out, isError) = try texts(exchange([call(1, "cswap_switch_preview")])[1])
        #expect(!isError)
        let text = try #require(out.first)
        #expect(text.hasPrefix("switch\n"))
        #expect(text.contains("account 2 (b@example.com)"))
        #expect(text.contains("cswap switch b@example.com"))
        #expect(text.contains("cswap run b@example.com"))
        #expect(text.hasSuffix("Switching happens only after the user agrees."))
    }

    @Test(arguments: [("dryrun_noswitch.jsonl", 2, "no-switch"), ("dryrun_blocked.jsonl", 3, "blocked")])
    func `Preview reports no-switch and blocked`(fixture: String, code: Int, prefix: String) throws {
        try installFakeCswap(autoFixture: fixture, autoExit: code)
        let (out, isError) = try texts(exchange([call(1, "cswap_switch_preview")])[1])
        #expect(!isError)
        #expect(out.first?.hasPrefix(prefix) == true)
    }
}
