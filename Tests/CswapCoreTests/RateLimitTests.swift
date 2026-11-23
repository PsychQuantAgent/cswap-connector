import Foundation
import Testing
@testable import CswapCore

struct StopFailureTests {
    let store = PendingStore(root: temporaryDirectory())
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func switchReader() -> Reader {
        reader(auto: .result(0, Fixture.text("dryrun_switch.jsonl"))).0
    }

    func terminalSequence(_ output: String) throws -> String {
        let object = try #require(JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
        return try #require(object["terminalSequence"] as? String)
    }

    @Test func `Switch writes the pending file and notifies`() throws {
        let output = StopFailureHook.handle(error: "rate_limit", sessionID: "s1", reader: switchReader(), store: store, now: now)
        let sequence = try terminalSequence(output)
        #expect(sequence.hasPrefix("\u{1B}]9;"))
        #expect(sequence.hasSuffix("\u{07}"))
        #expect(sequence.contains("b@example.com"))

        let data = try Data(contentsOf: store.pendingURL("s1"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let pending = try decoder.decode(PendingProposal.self, from: data)
        #expect(pending.proposed == AccountRef(number: 2, email: "b@example.com"))
        #expect(pending.trigger == "at-limit")
    }

    @Test func `Second switch in the same session does not notify`() throws {
        _ = StopFailureHook.handle(error: "rate_limit", sessionID: "s1", reader: switchReader(), store: store, now: now)
        try FileManager.default.removeItem(at: store.pendingURL("s1"))
        let second = StopFailureHook.handle(error: "rate_limit", sessionID: "s1", reader: switchReader(), store: store, now: now)
        #expect(second.isEmpty)
        #expect(FileManager.default.fileExists(atPath: store.pendingURL("s1").path))

        // Another session still gets its own first notification.
        let other = StopFailureHook.handle(error: "rate_limit", sessionID: "s2", reader: switchReader(), store: store, now: now)
        #expect(!other.isEmpty)
    }

    @Test(arguments: [
        StubRunner.Response.result(2, Fixture.text("dryrun_noswitch.jsonl")),
        StubRunner.Response.result(3, Fixture.text("dryrun_blocked.jsonl")),
        StubRunner.Response.failure(.notFound),
        StubRunner.Response.failure(.timedOut),
    ])
    func `No switch is silent`(response: StubRunner.Response) {
        let (r, _) = reader(auto: response)
        #expect(StopFailureHook.handle(error: "rate_limit", sessionID: "s1", reader: r, store: store, now: now).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: store.pendingURL("s1").path))
    }

    @Test func `Other errors never run cswap`() {
        let (r, stub) = reader(auto: .result(0, Fixture.text("dryrun_switch.jsonl")))
        #expect(StopFailureHook.handle(error: "server_error", sessionID: "s1", reader: r, store: store, now: now).isEmpty)
        #expect(stub.calls.isEmpty)
    }

    @Test func `Session ids cannot escape the data directory`() {
        let url = store.pendingURL("../../etc/passwd")
        #expect(url.deletingLastPathComponent().lastPathComponent == "pending")
        #expect(!url.lastPathComponent.contains("/"))
    }
}

struct PendingHintTests {
    let store = PendingStore(root: temporaryDirectory())
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func record(ageMinutes: Double) {
        let (r, _) = reader(auto: .result(0, Fixture.text("dryrun_switch.jsonl")))
        _ = StopFailureHook.handle(error: "rate_limit", sessionID: "s1", reader: r, store: store, now: now.addingTimeInterval(-ageMinutes * 60))
    }

    @Test func `Proposal is delivered once`() {
        record(ageMinutes: 2)
        let output = PendingHintHook.handle(sessionID: "s1", store: store, now: now)
        #expect(output.contains("account 2 (b@example.com)"))
        #expect(output.contains("cswap switch b@example.com"))
        #expect(output.contains("cswap run b@example.com"))
        #expect(output.hasSuffix(ProposalText.consentSentence))
        #expect(!FileManager.default.fileExists(atPath: store.pendingURL("s1").path))
        #expect(PendingHintHook.handle(sessionID: "s1", store: store, now: now).isEmpty)
    }

    @Test func `Expired proposal is discarded`() {
        record(ageMinutes: 45)
        #expect(PendingHintHook.handle(sessionID: "s1", store: store, now: now).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: store.pendingURL("s1").path))
    }

    @Test func `Pending hint never calls cswap`() {
        // The hook takes no Reader at all; this pins the signature.
        let handle: (String?, PendingStore, Date) -> String = PendingHintHook.handle
        #expect(handle("none", store, now).isEmpty)
    }
}
