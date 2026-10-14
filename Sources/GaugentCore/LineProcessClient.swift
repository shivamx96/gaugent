import Foundation

public enum LineProcessError: Error, Equatable {
    case launchFailed(String)
    case timedOut
    case disconnected
    case responseTooLarge
    case requestFailed(String)
}

/// Exchanges newline-delimited JSON with a child process over stdio, under one deadline.
///
/// This is the only way gaugent talks to an agent CLI. It sends bounded requests, never a
/// user turn, and terminates the child as soon as it has what it needs. The deadline spans
/// the whole conversation so a chatty or hung child cannot keep a refresh alive forever.
public final class LineProcessClient: @unchecked Sendable {
    private static let maximumBufferSize = 8 * 1024 * 1024
    private static let terminationGracePeriod: TimeInterval = 2

    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let lock = NSCondition()
    private var buffer = Data()
    private var closed = false
    private let timeout: TimeInterval
    private var deadline = Date.distantFuture

    public init(executable: String, arguments: [String], currentDirectory: URL, timeout: TimeInterval = 15) {
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        self.timeout = timeout
    }

    deinit { terminate() }

    public var isRunning: Bool { process.isRunning }

    public func start() throws {
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            self.lock.lock()
            if data.isEmpty {
                self.closed = true
                handle.readabilityHandler = nil
            } else {
                self.buffer.append(data)
            }
            self.lock.broadcast()
            self.lock.unlock()
        }
        process.terminationHandler = { [weak self] _ in
            guard let self else { return }
            self.lock.lock()
            self.closed = true
            self.lock.broadcast()
            self.lock.unlock()
        }
        do {
            try process.run()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            throw LineProcessError.launchFailed(error.localizedDescription)
        }
        deadline = Date().addingTimeInterval(timeout)
    }

    /// Lets tests shorten the remaining time without restarting the child.
    public func expireDeadline() {
        lock.lock()
        deadline = .distantPast
        lock.broadcast()
        lock.unlock()
    }

    public func send(_ message: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: message)
        data.append(0x0A)
        do {
            try input.fileHandleForWriting.write(contentsOf: data)
        } catch {
            throw LineProcessError.disconnected
        }
    }

    /// Returns the first complete JSON object line accepted by `matches`; other lines are dropped.
    public func receive(where matches: ([String: Any]) -> Bool) throws -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        while true {
            while let line = takeLine() {
                guard !line.isEmpty,
                      let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                if matches(object) { return object }
            }
            if buffer.count > Self.maximumBufferSize { throw LineProcessError.responseTooLarge }
            if closed { throw LineProcessError.disconnected }
            guard Date() < deadline else { throw LineProcessError.timedOut }
            lock.wait(until: deadline)
        }
    }

    private func takeLine() -> Data? {
        guard let newline = buffer.firstIndex(of: 0x0A) else { return nil }
        let line = buffer.subdata(in: buffer.startIndex..<newline)
        buffer = Data(buffer[buffer.index(after: newline)...])
        return line
    }

    public func terminate() {
        output.fileHandleForReading.readabilityHandler = nil
        try? input.fileHandleForWriting.close()
        guard process.isRunning else { return }
        process.terminate()
        let limit = Date().addingTimeInterval(Self.terminationGracePeriod)
        while process.isRunning && Date() < limit {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
        process.waitUntilExit()
    }
}

/// JSON-RPC 2.0-style requests with integer ids, as spoken by `codex app-server`.
public struct JSONRPCSession {
    private let client: LineProcessClient
    private let counter = Counter()

    public init(client: LineProcessClient) {
        self.client = client
    }

    public func notify(_ method: String, params: [String: Any]? = nil) throws {
        var message: [String: Any] = ["method": method]
        if let params { message["params"] = params }
        try client.send(message)
    }

    public func request(_ method: String, params: [String: Any]? = nil) throws -> [String: Any] {
        let id = counter.next()
        var message: [String: Any] = ["id": id, "method": method]
        if let params { message["params"] = params }
        try client.send(message)
        let response = try client.receive { ($0["id"] as? Int) == id }
        if let error = response["error"] {
            throw LineProcessError.requestFailed(Self.describe(error, method: method))
        }
        return response["result"] as? [String: Any] ?? [:]
    }

    private static func describe(_ error: Any, method: String) -> String {
        // Provider error text is not surfaced to the user; only the method that failed.
        _ = error
        return "\(method) failed"
    }
}

/// Claude Code's stream-JSON control channel: string request ids wrapped in `control_request`.
public struct ControlSession {
    private let client: LineProcessClient
    private let counter = Counter()

    public init(client: LineProcessClient) {
        self.client = client
    }

    public func request(_ subtype: String, params: [String: Any] = [:]) throws -> [String: Any] {
        let id = String(counter.next())
        var request = params
        request["subtype"] = subtype
        try client.send(["type": "control_request", "request_id": id, "request": request])
        let message = try client.receive { message in
            guard message["type"] as? String == "control_response",
                  let response = message["response"] as? [String: Any] else { return false }
            return response["request_id"] as? String == id
        }
        let response = message["response"] as? [String: Any] ?? [:]
        guard response["subtype"] as? String == "success" else {
            throw LineProcessError.requestFailed("\(subtype) failed")
        }
        return response["response"] as? [String: Any] ?? [:]
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}
