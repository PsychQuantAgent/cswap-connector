import Foundation

/// Result of running one external command.
public struct CommandResult: Sendable, Equatable {
    public let exitCode: Int32
    public let stdout: Data

    public init(exitCode: Int32, stdout: Data) {
        self.exitCode = exitCode
        self.stdout = stdout
    }
}

public enum CommandFailure: Error, Equatable, Sendable {
    /// The executable could not be found on PATH.
    case notFound
    /// The process did not exit within the time limit and was terminated.
    case timedOut
}

/// Runs a command; injected so tests can substitute canned cswap output.
public protocol CommandRunner: Sendable {
    func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) throws -> CommandResult
}

/// Runs a real process found on PATH, terminating it at the timeout.
public struct ProcessRunner: CommandRunner {
    public let searchPath: String

    public init(searchPath: String = ProcessInfo.processInfo.environment["PATH"] ?? "") {
        self.searchPath = searchPath
    }

    func resolve(_ executable: String) -> URL? {
        if executable.contains("/") {
            return FileManager.default.isExecutableFile(atPath: executable) ? URL(fileURLWithPath: executable) : nil
        }
        for dir in searchPath.split(separator: ":") where !dir.isEmpty {
            let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent(executable)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    public func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) throws -> CommandResult {
        guard let url = resolve(executable) else { throw CommandFailure.notFound }

        let process = Process()
        process.executableURL = url
        process.arguments = arguments
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }

        // Drain stdout concurrently so a large output cannot block the child on a full pipe.
        let collected = OutputCollector()
        let reader = out.fileHandleForReading
        let readDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            collected.set(reader.readDataToEndOfFile())
            readDone.signal()
        }

        try process.run()
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if finished.wait(timeout: .now() + 1) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 1)
            }
            throw CommandFailure.timedOut
        }
        _ = readDone.wait(timeout: .now() + 1)
        return CommandResult(exitCode: process.terminationStatus, stdout: collected.get())
    }
}

/// Thread-safe holder for the bytes read from the child's stdout.
final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func set(_ value: Data) {
        lock.lock(); defer { lock.unlock() }
        data = value
    }

    func append(_ value: Data) {
        lock.lock(); defer { lock.unlock() }
        data.append(value)
    }

    func get() -> Data {
        lock.lock(); defer { lock.unlock() }
        return data
    }
}
