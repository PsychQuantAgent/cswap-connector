import Foundation

/// Text used wherever the plugin names an account to switch to.
public enum ProposalText {
    public static let consentSentence = "Switching happens only after the user agrees."

    public static func render(_ target: AccountRef, trigger: String) -> String {
        """
        cswap proposes switching to account \(target.number) (\(target.email)), trigger: \(trigger).
        All sessions: cswap switch \(target.email)
        This terminal only: cswap run \(target.email)
        \(consentSentence)
        """
    }
}

/// Prefixes a reader failure for any user- or Claude-visible line.
public func failOpenLine(_ failure: ReaderFailure) -> String {
    "cswap-connector: \(failure.message)"
}

// MARK: - SessionStart

public enum SessionContext {
    /// Returns the hook's stdout JSON. Never throws; failures become one line.
    public static func output(reader: Reader, block: AccountsBlock = AccountsBlock()) -> String {
        let context: String
        switch reader.accounts() {
        case .success(let accounts): context = block.render(accounts)
        case .failure(let failure): context = failOpenLine(failure)
        }
        return jsonString([
            "hookSpecificOutput": [
                "hookEventName": "SessionStart",
                "additionalContext": context,
            ],
        ])
    }
}

// MARK: - StopFailure + UserPromptSubmit

/// Files under the plugin data directory that carry a proposal from a
/// StopFailure hook to the next UserPromptSubmit hook in the same session.
public struct PendingStore: Sendable {
    public static let maxAge: TimeInterval = 30 * 60

    let root: URL

    public init(root: URL) {
        self.root = root
    }

    func pendingURL(_ sessionID: String) -> URL {
        root.appendingPathComponent("pending").appendingPathComponent("\(Self.safe(sessionID)).json")
    }

    func notifiedURL(_ sessionID: String) -> URL {
        root.appendingPathComponent("notified").appendingPathComponent(Self.safe(sessionID))
    }

    /// Session ids come from Claude Code; anything outside a conservative
    /// character set is replaced so the id can never escape the directory.
    static func safe(_ id: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = String(id.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
        return cleaned.isEmpty ? "_" : cleaned
    }
}

public struct PendingProposal: Codable, Equatable, Sendable {
    public let proposed: AccountRef
    public let trigger: String
    public let createdAt: Date
}

public enum StopFailureHook {
    /// Handles a StopFailure event. Returns the stdout to print (a
    /// `terminalSequence` JSON on the session's first switch), or "".
    public static func handle(error: String?, sessionID: String?, reader: Reader, store: PendingStore, now: Date = Date()) -> String {
        guard error == "rate_limit", let sessionID else { return "" }
        guard case .success(.switchTo(let target, let trigger)) = reader.switchPreview() else { return "" }

        let proposal = PendingProposal(proposed: target, trigger: trigger, createdAt: now)
        let fm = FileManager.default
        do {
            let pending = store.pendingURL(sessionID)
            try fm.createDirectory(at: pending.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(proposal).write(to: pending, options: .atomic)
        } catch {
            return ""
        }

        let marker = store.notifiedURL(sessionID)
        guard !fm.fileExists(atPath: marker.path) else { return "" }
        try? fm.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard fm.createFile(atPath: marker.path, contents: Data()) else { return "" }
        let text = "cswap-connector: rate limited. cswap would switch to account \(target.number) (\(target.email)); Claude will propose it on your next message."
        return jsonString(["terminalSequence": "\u{1B}]9;\(text)\u{07}"])
    }
}

public enum PendingHintHook {
    /// Handles a UserPromptSubmit event. Never runs cswap.
    public static func handle(sessionID: String?, store: PendingStore, now: Date = Date()) -> String {
        guard let sessionID else { return "" }
        let url = store.pendingURL(sessionID)
        guard let data = try? Data(contentsOf: url) else { return "" }
        try? FileManager.default.removeItem(at: url)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let proposal = try? decoder.decode(PendingProposal.self, from: data),
              now.timeIntervalSince(proposal.createdAt) <= PendingStore.maxAge
        else { return "" }
        return ProposalText.render(proposal.proposed, trigger: proposal.trigger)
    }
}

// MARK: - Hook input

public struct HookInput: Decodable, Sendable {
    public let sessionID: String?
    public let error: String?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case error
    }

    public static func read(from data: Data) -> HookInput {
        (try? JSONDecoder().decode(HookInput.self, from: data)) ?? HookInput(sessionID: nil, error: nil)
    }

    public init(sessionID: String?, error: String?) {
        self.sessionID = sessionID
        self.error = error
    }
}

func jsonString(_ object: [String: Any]) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return "" }
    return String(decoding: data, as: UTF8.self)
}
