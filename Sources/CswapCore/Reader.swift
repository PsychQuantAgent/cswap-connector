import Foundation

/// Every way reading from cswap can fail. Each maps to exactly one fixed message.
public enum ReaderFailure: Error, Equatable, Sendable {
    case cswapNotFound
    case cswapError(String)
    case timedOut
    case unsupportedSchema(String)
    case unsupportedPlatform

    public var message: String {
        switch self {
        case .cswapNotFound:
            return "cswap not found; install claude-swap to see account usage"
        case .cswapError(let detail):
            return "cswap error: \(detail)"
        case .timedOut:
            return "cswap did not answer within 5 s"
        case .unsupportedSchema(let version):
            return "unsupported cswap JSON schemaVersion \(version); update cswap-connector"
        case .unsupportedPlatform:
            return "unsupported platform"
        }
    }
}

/// The only component that runs cswap. It invokes read-only commands only.
public struct Reader: Sendable {
    /// The two invocations this plugin is allowed to make. No other cswap
    /// arguments exist anywhere in the plugin (see `ReaderTests`).
    public static let listArguments = ["list", "--json"]
    public static let dryRunArguments = ["auto", "--once", "--dry-run", "--json"]
    public static let timeout: TimeInterval = 5

    let runner: CommandRunner
    let executable: String
    let platformSupported: Bool

    public init(runner: CommandRunner = ProcessRunner(), executable: String = "cswap", platformSupported: Bool = Reader.isMacOS) {
        self.runner = runner
        self.executable = executable
        self.platformSupported = platformSupported
    }

    public static var isMacOS: Bool {
        #if os(macOS)
        return true
        #else
        return false
        #endif
    }

    // MARK: - cswap list

    public func accounts() -> Result<[Account], ReaderFailure> {
        switch invoke(Self.listArguments) {
        case .failure(let failure):
            return .failure(failure)
        case .success(let result):
            let data = result.stdout
            guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
                return .failure(result.exitCode == 0
                    ? .cswapError("output was not JSON")
                    : .cswapError("exit code \(result.exitCode)"))
            }
            if let failure = schemaFailure(envelope.schemaVersion) { return .failure(failure) }
            if let error = envelope.error {
                return .failure(.cswapError(error.message ?? "exit code \(result.exitCode)"))
            }
            if result.exitCode != 0 { return .failure(.cswapError("exit code \(result.exitCode)")) }
            guard let payload = try? JSONDecoder().decode(ListPayload.self, from: data) else {
                return .failure(.cswapError("output had no accounts"))
            }
            return .success(payload.accounts)
        }
    }

    // MARK: - cswap auto --once --dry-run

    public func switchPreview() -> Result<SwitchPreview, ReaderFailure> {
        switch invoke(Self.dryRunArguments) {
        case .failure(let failure):
            return .failure(failure)
        case .success(let result):
            let lines = String(decoding: result.stdout, as: UTF8.self)
                .split(whereSeparator: \.isNewline)
            var events: [AutoEvent] = []
            var errorMessage: String?
            for line in lines {
                let data = Data(line.utf8)
                guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else { continue }
                if let failure = schemaFailure(envelope.schemaVersion) { return .failure(failure) }
                if let error = envelope.error { errorMessage = error.message }
                if let event = try? JSONDecoder().decode(AutoEvent.self, from: data) { events.append(event) }
            }
            if let errorMessage { return .failure(.cswapError(errorMessage)) }
            if result.exitCode == 3 { return .success(.blocked) }
            if let event = events.first(where: { $0.event == "switch" }), let target = event.to {
                return .success(.switchTo(target, trigger: event.trigger ?? "unknown"))
            }
            if result.exitCode == 2 || result.exitCode == 0 {
                let reason = events.first(where: { $0.event == "no-switch" })?.reason ?? "unknown"
                return .success(.noSwitch(reason: reason))
            }
            return .failure(.cswapError("exit code \(result.exitCode)"))
        }
    }

    // MARK: - Shared

    private func invoke(_ arguments: [String]) -> Result<CommandResult, ReaderFailure> {
        guard platformSupported else { return .failure(.unsupportedPlatform) }
        do {
            return .success(try runner.run(executable, arguments, timeout: Self.timeout))
        } catch CommandFailure.notFound {
            return .failure(.cswapNotFound)
        } catch CommandFailure.timedOut {
            return .failure(.timedOut)
        } catch {
            return .failure(.cswapError(String(describing: error)))
        }
    }

    private func schemaFailure(_ version: Int?) -> ReaderFailure? {
        guard let version else { return .unsupportedSchema("missing") }
        return version == supportedSchemaVersion ? nil : .unsupportedSchema(String(version))
    }
}
