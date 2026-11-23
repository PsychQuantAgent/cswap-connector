import Foundation

/// Result of one MCP tool call, independent of the MCP SDK so it can be tested directly.
public struct ToolOutput: Equatable, Sendable {
    public let texts: [String]
    public let isError: Bool

    public init(texts: [String], isError: Bool) {
        self.texts = texts
        self.isError = isError
    }
}

/// The two read-only tools. There is intentionally no tool that switches accounts.
public enum UsageTools {
    public static let usageName = "cswap_usage"
    public static let previewName = "cswap_switch_preview"
    public static let names = [usageName, previewName]

    public static let usageDescription =
        "List every cswap account with its active marker, plan, and 5-hour / 7-day / per-model usage and reset times. Read-only."
    public static let previewDescription =
        "Preview which account cswap's own auto-switch strategy would move to right now, without switching. Read-only; the user decides."

    public static func usage(reader: Reader, block: AccountsBlock = AccountsBlock()) -> ToolOutput {
        switch reader.accounts() {
        case .failure(let failure):
            return ToolOutput(texts: [failOpenLine(failure)], isError: true)
        case .success(let accounts):
            return ToolOutput(texts: [block.render(accounts), accountsJSON(accounts, block: block)], isError: false)
        }
    }

    public static func preview(reader: Reader) -> ToolOutput {
        switch reader.switchPreview() {
        case .failure(let failure):
            return ToolOutput(texts: [failOpenLine(failure)], isError: true)
        case .success(.switchTo(let target, let trigger)):
            return ToolOutput(texts: ["switch\n" + ProposalText.render(target, trigger: trigger)], isError: false)
        case .success(.noSwitch(let reason)):
            return ToolOutput(texts: ["no-switch: cswap would stay on the current account (\(reason))."], isError: false)
        case .success(.blocked):
            return ToolOutput(texts: ["blocked: cswap wants to move but no account has quota left."], isError: false)
        }
    }

    static func accountsJSON(_ accounts: [Account], block: AccountsBlock) -> String {
        func window(_ w: UsageWindow?) -> Any {
            guard let w else { return NSNull() }
            return ["pct": w.pct.map { $0 as Any } ?? NSNull(), "resetsAt": w.resetsAt ?? NSNull()] as [String: Any]
        }
        let rows: [[String: Any]] = accounts.map { a in
            let usage = (a.usageStatus == nil || a.usageStatus == "ok") ? a.usage : a.lastGoodUsage
            return [
                "number": a.number,
                "email": a.email,
                "active": a.active ?? false,
                "plan": a.plan?.label ?? NSNull(),
                "usageStatus": a.usageStatus ?? NSNull(),
                "fiveHour": window(usage?.fiveHour),
                "sevenDay": window(usage?.sevenDay),
                "scoped": (usage?.scoped ?? []).map { ["name": $0.name ?? NSNull(), "pct": $0.pct.map { $0 as Any } ?? NSNull(), "resetsAt": $0.resetsAt ?? NSNull()] as [String: Any] },
            ]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }
}
