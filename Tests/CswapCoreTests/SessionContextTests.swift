import Foundation
import Testing
@testable import CswapCore

struct SessionContextTests {
    let block = AccountsBlock(timeZone: taipei)

    func accounts() throws -> [Account] {
        let (r, _) = reader(list: .result(0, Fixture.text("list_ok.json")))
        return try r.accounts().get()
    }

    @Test func `Ultra account line matches the spec example`() throws {
        let line = block.line(for: try accounts()[2])
        #expect(line == "* 3 c@example.com (active) · Ultra · 7d 85% (resets 11-25 11:00) · Fable 100% (resets 11-25 11:00)")
    }

    @Test func `No five-hour entry when cswap reports none`() throws {
        #expect(!block.line(for: try accounts()[2]).contains("5h"))
        // Account 1 has one, with a microsecond fraction in its reset time.
        #expect(block.line(for: try accounts()[0]) == "- 1 a@example.com · Max 5x · 5h 42.5% (resets 11-23 16:00) · 7d 10% (resets 11-28 08:00)")
    }

    @Test func `Stale reading is labelled with its age`() throws {
        let line = block.line(for: try accounts()[1])
        #expect(line.hasSuffix("(as of 12 min ago)"))
        #expect(line == "- 2 b@example.com · Ultra · 7d 9% (resets 11-30 14:00) (as of 12 min ago)")
    }

    @Test func `Unavailable without a last good reading`() throws {
        let json = #"{"schemaVersion":1,"accounts":[{"number":5,"email":"e@example.com","usageStatus":"unavailable","usageError":"http-429"},{"number":6,"email":"f@example.com","usageStatus":"token_expired"}]}"#
        let (r, _) = reader(list: .result(0, json))
        let lines = try r.accounts().get().map(block.line(for:))
        #expect(lines == ["- 5 e@example.com · usage unavailable (http-429)", "- 6 f@example.com · usage unavailable (unknown)"])
    }

    @Test func `Null percentage shows n/a`() {
        #expect(block.entry("7d", UsageWindow(pct: nil, resetsAt: nil)) == "7d n/a")
    }

    @Test func `Block starts with the header and has one line per account`() throws {
        let (r, _) = reader(list: .result(0, Fixture.text("list_ok.json")))
        let output = SessionContext.output(reader: r, block: block)
        let context = try additionalContext(output)
        let lines = context.split(separator: "\n")
        #expect(lines.first == "cswap accounts")
        #expect(lines.count == 4)
    }

    @Test func `Fails open when cswap is missing`() throws {
        let (r, _) = reader()
        let context = try additionalContext(SessionContext.output(reader: r, block: block))
        #expect(context == "cswap-connector: cswap not found; install claude-swap to see account usage")
    }

    private func additionalContext(_ output: String) throws -> String {
        let object = try #require(JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
        let specific = try #require(object["hookSpecificOutput"] as? [String: Any])
        #expect(specific["hookEventName"] as? String == "SessionStart")
        return try #require(specific["additionalContext"] as? String)
    }
}
