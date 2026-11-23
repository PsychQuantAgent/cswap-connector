import Foundation

/// The only cswap JSON contract version this plugin understands.
public let supportedSchemaVersion = 1

/// One usage window (`fiveHour`, `sevenDay`, or a per-model `scoped` entry).
public struct UsageWindow: Decodable, Equatable, Sendable {
    public let pct: Double?
    public let resetsAt: String?
    /// Present only on `scoped` windows, e.g. "Fable".
    public let name: String?

    public init(pct: Double?, resetsAt: String?, name: String? = nil) {
        self.pct = pct
        self.resetsAt = resetsAt
        self.name = name
    }
}

public struct Usage: Decodable, Equatable, Sendable {
    public let fiveHour: UsageWindow?
    public let sevenDay: UsageWindow?
    public let scoped: [UsageWindow]?
}

public struct Plan: Decodable, Equatable, Sendable {
    public let label: String?
}

/// One row of `cswap list --json`. Only the fields this plugin reads are decoded.
public struct Account: Decodable, Equatable, Sendable {
    public let number: Int
    public let email: String
    public let active: Bool?
    public let plan: Plan?
    public let usageStatus: String?
    public let usage: Usage?
    public let lastGoodUsage: Usage?
    public let lastGoodAgeSeconds: Double?
    public let usageError: String?
}

/// Envelope shared by every cswap JSON output.
struct Envelope: Decodable {
    let schemaVersion: Int?
    let error: ErrorPayload?
}

struct ErrorPayload: Decodable {
    let message: String?
}

struct ListPayload: Decodable {
    let accounts: [Account]
}

/// One line of `cswap auto --once --dry-run --json`.
struct AutoEvent: Decodable {
    let schemaVersion: Int?
    let event: String?
    let reason: String?
    let trigger: String?
    let to: AccountRef?
}

public struct AccountRef: Codable, Equatable, Sendable {
    public let number: Int
    public let email: String

    public init(number: Int, email: String) {
        self.number = number
        self.email = email
    }
}

/// Outcome of one dry-run auto-switch tick.
public enum SwitchPreview: Equatable, Sendable {
    case switchTo(AccountRef, trigger: String)
    case noSwitch(reason: String)
    case blocked
}
