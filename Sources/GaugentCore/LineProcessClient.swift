import Darwin
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
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let deadlineLock = NSLock()
    private var deadline = Date.distantFuture
    private let timeout: TimeInterval
    private var buffer = Data()
    private var consumed = 0
    private var scanned = 0

    // One caller owns start/send/receive/terminate. Only expireDeadline may run concurrently.
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
        deadlineLock.lock()
        deadline = Date().addingTimeInterval(timeout)
        deadlineLock.unlock()
        do {
            try ProcessIO.configure(output.fileHandleForReading)
            try ProcessIO.configure(input.fileHandleForWriting, writing: true)
            try process.run()
        } catch {
            throw LineProcessError.launchFailed(error.localizedDescription)
        }
    }

    public func expireDeadline() {
        deadlineLock.lock()
        deadline = .distantPast
        deadlineLock.unlock()
    }

    private func checkDeadline() throws {
        deadlineLock.lock()
        let expired = Date() >= deadline
        deadlineLock.unlock()
        if expired { throw LineProcessError.timedOut }
    }

    public func send(_ message: [String: Any]) throws {
        try checkDeadline()
        var data = try JSONSerialization.data(withJSONObject: message)
        data.append(0x0A)
        guard data.count <= ProcessIO.maximumOutputSize else { throw LineProcessError.responseTooLarge }
        var sent = 0
        while sent < data.count {
            try checkDeadline()
            let count = data.withUnsafeBytes { bytes in
                Darwin.write(input.fileHandleForWriting.fileDescriptor, bytes.baseAddress!.advanced(by: sent), data.count - sent)
            }
            if count > 0 { sent += count }
            else if count < 0 && (errno == EAGAIN || errno == EINTR) {
                ProcessIO.wait([input.fileHandleForWriting], writing: true)
            } else { throw LineProcessError.disconnected }
        }
    }

    /// Returns the first matching JSON object. Bounds are checked before parsing each line.
    public func receive(where matches: ([String: Any]) -> Bool) throws -> [String: Any] {
        while true {
            try checkDeadline()
            if let line = takeLine() {
                guard !line.isEmpty,
                      let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                try checkDeadline()
                let accepted = matches(object)
                try checkDeadline()
                if accepted { return object }
                continue
            }
            guard let data = try ProcessIO.read(output.fileHandleForReading) else {
                ProcessIO.wait([output.fileHandleForReading])
                continue
            }
            if data.isEmpty { throw LineProcessError.disconnected }
            guard data.count <= ProcessIO.maximumOutputSize - (buffer.count - consumed) else {
                throw LineProcessError.responseTooLarge
            }
            compactBufferIfNeeded()
            buffer.append(data)
        }
    }

    private func takeLine() -> Data? {
        guard let newline = buffer[scanned...].firstIndex(of: 0x0A) else {
            scanned = buffer.count
            return nil
        }
        let line = buffer.subdata(in: consumed..<newline)
        consumed = newline + 1
        scanned = consumed
        return line
    }

    private func compactBufferIfNeeded() {
        // Compact in batches, not once per line; scan each byte only once.
        guard consumed > 0 else { return }
        if consumed == buffer.count {
            buffer.removeAll(keepingCapacity: true)
        } else {
            buffer = Data(buffer[consumed...])
        }
        scanned -= consumed
        consumed = 0
    }

    public func terminate() {
        try? input.fileHandleForWriting.close()
        ProcessIO.terminate(process)
        try? output.fileHandleForReading.close()
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
