import Foundation

/// Renders the `cswap accounts` block shared by SessionStart and the `cswap_usage` tool.
public struct AccountsBlock: Sendable {
    public static let header = "cswap accounts"

    let timeZone: TimeZone

    public init(timeZone: TimeZone = .current) {
        self.timeZone = timeZone
    }

    public func render(_ accounts: [Account]) -> String {
        ([Self.header] + accounts.map(line(for:))).joined(separator: "\n")
    }

    public func line(for account: Account) -> String {
        let marker = account.active == true ? "*" : "-"
        var parts = ["\(marker) \(account.number) \(account.email)\(account.active == true ? " (active)" : "")"]
        if let label = account.plan?.label { parts.append(label) }

        if account.usageStatus == nil || account.usageStatus == "ok", let usage = account.usage {
            parts.append(contentsOf: windows(usage))
        } else if let stale = account.lastGoodUsage {
            let minutes = Int((account.lastGoodAgeSeconds ?? 0) / 60)
            parts.append(contentsOf: windows(stale))
            parts[parts.count - 1] += " (as of \(minutes) min ago)"
        } else {
            parts.append("usage unavailable (\(account.usageError ?? "unknown"))")
        }
        return parts.joined(separator: " · ")
    }

    func windows(_ usage: Usage) -> [String] {
        var out: [String] = []
        if let five = usage.fiveHour { out.append(entry("5h", five)) }
        if let seven = usage.sevenDay { out.append(entry("7d", seven)) }
        for scoped in usage.scoped ?? [] { out.append(entry(scoped.name ?? "model", scoped)) }
        if out.isEmpty { out.append("no usage windows reported") }
        return out
    }

    func entry(_ label: String, _ window: UsageWindow) -> String {
        let pct = window.pct.map(Self.formatPercent) ?? "n/a"
        guard let reset = window.resetsAt.flatMap(Self.parseDate) else { return "\(label) \(pct)" }
        return "\(label) \(pct) (resets \(format(reset)))"
    }

    func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }

    static func formatPercent(_ value: Double) -> String {
        value.rounded() == value ? "\(Int(value))%" : String(format: "%.1f%%", value)
    }

    /// cswap writes ISO-8601 with up to microsecond fractions and an offset;
    /// fractions are dropped (display precision is minutes).
    static func parseDate(_ text: String) -> Date? {
        let trimmed = text.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: trimmed)
    }
}
