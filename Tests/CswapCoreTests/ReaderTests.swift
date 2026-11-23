import Foundation
import Testing
@testable import CswapCore

struct ReaderTests {
    @Test func `Decodes accounts from cswap list`() throws {
        let (r, _) = reader(list: .result(0, Fixture.text("list_ok.json")))
        let accounts = try r.accounts().get()
        #expect(accounts.map(\.number) == [1, 2, 3])
        #expect(accounts[2].active == true)
    }

    @Test(arguments: [
        ("{\"schemaVersion\":2,\"accounts\":[]}", Int32(0), "unsupported cswap JSON schemaVersion 2; update cswap-connector"),
        ("{\"accounts\":[]}", Int32(0), "unsupported cswap JSON schemaVersion missing; update cswap-connector"),
        ("{\"schemaVersion\":1,\"error\":{\"message\":\"lock busy\"}}", Int32(1), "cswap error: lock busy"),
        ("not json at all", Int32(1), "cswap error: exit code 1"),
    ])
    func `Each failure maps to its fixed message`(output: String, code: Int32, message: String) {
        let (r, _) = reader(list: .result(code, output))
        #expect(r.accounts() == .failure(failure(message)))
        #expect(failOpenLine(failure(message)) == "cswap-connector: \(message)")
    }

    @Test func `Schema mismatch decodes no accounts`() {
        let (r, _) = reader(list: .result(0, "{\"schemaVersion\":2,\"accounts\":[{\"number\":1,\"email\":\"x@example.com\"}]}"))
        guard case .failure(.unsupportedSchema("2")) = r.accounts() else {
            Issue.record("expected schema failure")
            return
        }
    }

    @Test func `cswap not found`() {
        let (r, _) = reader(list: .failure(.notFound))
        #expect(r.accounts() == .failure(.cswapNotFound))
        #expect(ReaderFailure.cswapNotFound.message == "cswap not found; install claude-swap to see account usage")
    }

    @Test func `Unsupported platform never runs cswap`() {
        let stub = StubRunner(["list": .result(0, Fixture.text("list_ok.json"))])
        let r = Reader(runner: stub, platformSupported: false)
        #expect(r.accounts() == .failure(.unsupportedPlatform))
        #expect(stub.calls.isEmpty)
        #expect(ReaderFailure.unsupportedPlatform.message == "unsupported platform")
    }

    @Test func `Timeout maps to the timeout message`() {
        let (r, _) = reader(list: .failure(.timedOut))
        #expect(r.accounts() == .failure(.timedOut))
        #expect(ReaderFailure.timedOut.message == "cswap did not answer within 5 s")
    }

    @Test func `Timeout terminates the child`() throws {
        let dir = temporaryDirectory()
        let script = dir.appendingPathComponent("cswap")
        let pidFile = dir.appendingPathComponent("pid")
        try "#!/bin/sh\necho $$ > \(pidFile.path)\nexec sleep 30\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let started = Date()
        #expect(throws: CommandFailure.timedOut) {
            _ = try ProcessRunner(searchPath: dir.path).run("cswap", ["list", "--json"], timeout: 1)
        }
        #expect(Date().timeIntervalSince(started) < 4)
        let pid = try #require(Int32(String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        #expect(kill(pid, 0) != 0, "child process is still running")
    }

    @Test(arguments: [
        ("dryrun_switch.jsonl", Int32(0), SwitchPreview.switchTo(AccountRef(number: 2, email: "b@example.com"), trigger: "at-limit")),
        ("dryrun_noswitch.jsonl", Int32(2), SwitchPreview.noSwitch(reason: "below-threshold")),
        ("dryrun_blocked.jsonl", Int32(3), SwitchPreview.blocked),
    ])
    func `Dry-run outcomes`(fixture: String, code: Int32, expected: SwitchPreview) {
        let (r, stub) = reader(auto: .result(code, Fixture.text(fixture)))
        #expect(r.switchPreview() == .success(expected))
        #expect(stub.calls == [Reader.dryRunArguments])
    }

    @Test func `Only read-only invocations exist`() throws {
        #expect(Reader.listArguments == ["list", "--json"])
        #expect(Reader.dryRunArguments == ["auto", "--once", "--dry-run", "--json"])

        // Scan the package sources: cswap may only be invoked through Reader's two constants.
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)!
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        #expect(!files.isEmpty)
        // An argument list for any state-changing cswap subcommand, e.g. ["switch", ...].
        let forbidden = try Regex(#"\[\s*"(switch|run|add|remove|import|config|--switch-to)""#)
        var checked = 0
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            #expect(text.firstMatch(of: forbidden) == nil, "\(file.lastPathComponent) builds a state-changing cswap argument list")
            #expect(!text.contains("--force"), "\(file.lastPathComponent) mentions --force")
            checked += 1
        }
        #expect(checked == files.count)
    }

    private func failure(_ message: String) -> ReaderFailure {
        switch message {
        case let m where m.hasPrefix("unsupported cswap JSON schemaVersion "):
            let v = m.dropFirst("unsupported cswap JSON schemaVersion ".count).split(separator: ";").first.map(String.init) ?? ""
            return .unsupportedSchema(v)
        case let m where m.hasPrefix("cswap error: "):
            return .cswapError(String(m.dropFirst("cswap error: ".count)))
        default:
            return .cswapError(message)
        }
    }
}
