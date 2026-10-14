import Foundation

public struct ProcessResult: Sendable {
    public let standardOutput: String
    public let standardError: String
    public let terminationStatus: Int32

    public init(standardOutput: String, standardError: String, terminationStatus: Int32) {
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.terminationStatus = terminationStatus
    }

    public var succeeded: Bool { terminationStatus == 0 }
}

public protocol ProcessRunning: Sendable {
    func run(executable: String, arguments: [String], currentDirectory: URL?) -> ProcessResult
}

/// Runs a short-lived child, drains both pipes, and kills it past a timeout.
public struct ProcessRunner: ProcessRunning {
    public static let defaultTimeout: TimeInterval = 15
    private static let terminationGracePeriod: TimeInterval = 2

    private let timeout: TimeInterval

    public init(timeout: TimeInterval = ProcessRunner.defaultTimeout) {
        self.timeout = timeout
    }

    public func run(executable: String, arguments: [String], currentDirectory: URL? = nil) -> ProcessResult {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = standardOutput
        process.standardError = standardError

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        do {
            try process.run()
        } catch {
            return ProcessResult(standardOutput: "", standardError: error.localizedDescription, terminationStatus: -1)
        }

        // Both pipes are drained while the child runs; a pipe blocks the writer at 64 KiB.
        let output = ByteBuffer()
        let errorOutput = ByteBuffer()
        let draining = DispatchGroup()
        drain(standardOutput, into: output, group: draining)
        drain(standardError, into: errorOutput, group: draining)

        let timedOut = waitForExit(of: process, signalledBy: exited)
        draining.wait()
        process.waitUntilExit()

        return ProcessResult(
            standardOutput: String(decoding: output.value, as: UTF8.self),
            standardError: timedOut
                ? "\(executable) did not finish within \(Int(timeout))s and was terminated."
                : String(decoding: errorOutput.value, as: UTF8.self),
            terminationStatus: timedOut ? -1 : process.terminationStatus
        )
    }

    private func drain(_ pipe: Pipe, into buffer: ByteBuffer, group: DispatchGroup) {
        DispatchQueue.global(qos: .userInitiated).async(group: group) {
            buffer.set(pipe.fileHandleForReading.readDataToEndOfFile())
        }
    }

    private func waitForExit(of process: Process, signalledBy exited: DispatchSemaphore) -> Bool {
        guard exited.wait(timeout: .now() + timeout) == .timedOut else { return false }
        process.terminate()
        if exited.wait(timeout: .now() + Self.terminationGracePeriod) == .timedOut {
            kill(process.processIdentifier, SIGKILL)
            exited.wait()
        }
        return true
    }
}

private final class ByteBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func set(_ data: Data) {
        lock.lock()
        storage = data
        lock.unlock()
    }

    var value: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
