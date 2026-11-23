import Foundation
@testable import CswapCore

/// A CommandRunner that returns canned output and records every invocation.
final class StubRunner: CommandRunner, @unchecked Sendable {
    enum Response {
        case result(Int32, String)
        case failure(CommandFailure)
    }

    private let lock = NSLock()
    private var responses: [String: Response]
    private(set) var calls: [[String]] = []

    init(_ responses: [String: Response]) {
        self.responses = responses
    }

    func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) throws -> CommandResult {
        lock.lock(); calls.append(arguments); let response = responses[arguments.first ?? ""]; lock.unlock()
        switch response {
        case .result(let code, let out): return CommandResult(exitCode: code, stdout: Data(out.utf8))
        case .failure(let failure): throw failure
        case nil: throw CommandFailure.notFound
        }
    }
}

enum Fixture {
    static func text(_ name: String) -> String {
        let url = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil)!
        return try! String(contentsOf: url, encoding: .utf8)
    }
}

let taipei = TimeZone(identifier: "Asia/Taipei")!

func reader(list: StubRunner.Response? = nil, auto: StubRunner.Response? = nil) -> (Reader, StubRunner) {
    var responses: [String: StubRunner.Response] = [:]
    if let list { responses["list"] = list }
    if let auto { responses["auto"] = auto }
    let stub = StubRunner(responses)
    return (Reader(runner: stub, platformSupported: true), stub)
}

func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("cswap-connector-tests-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
