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

/// Runs a short-lived child with bounded output capture and a deadline spanning pipe draining.
public struct ProcessRunner: ProcessRunning {
    public static let defaultTimeout: TimeInterval = 15
    private let timeout: TimeInterval
    private let environment: [String: String]?

    public init(timeout: TimeInterval = ProcessRunner.defaultTimeout, environment: [String: String]? = nil) {
        self.timeout = timeout
        self.environment = environment
    }

    public func run(executable: String, arguments: [String], currentDirectory: URL? = nil) -> ProcessResult {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        process.environment = ExecutableLocator.childEnvironment(executable: executable,
            environment: environment ?? ProcessInfo.processInfo.environment)
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdout
        process.standardError = stderr

        let handles = [stdout.fileHandleForReading, stderr.fileHandleForReading]
        defer {
            ProcessIO.terminate(process)
            for handle in handles { try? handle.close() }
        }
        var captured = [Data(), Data()]
        var open = [true, true]
        let deadline = Date().addingTimeInterval(timeout)
        do {
            for handle in handles { try ProcessIO.configure(handle) }
            try process.run()
            while open.contains(true) || process.isRunning {
                guard Date() < deadline else { throw LineProcessError.timedOut }
                var madeProgress = false
                for index in handles.indices where open[index] {
                    guard let data = try ProcessIO.read(handles[index]) else { continue }
                    madeProgress = true
                    if data.isEmpty {
                        open[index] = false
                    } else {
                        guard data.count <= ProcessIO.maximumOutputSize - captured[index].count else {
                            throw LineProcessError.responseTooLarge
                        }
                        captured[index].append(data)
                    }
                }
                if !madeProgress { ProcessIO.wait(handles.indices.filter { open[$0] }.map { handles[$0] }) }
            }
            process.waitUntilExit()
            return ProcessResult(standardOutput: String(decoding: captured[0], as: UTF8.self),
                                 standardError: String(decoding: captured[1], as: UTF8.self),
                                 terminationStatus: process.terminationStatus)
        } catch {
            let message: String
            switch error as? LineProcessError {
            case .timedOut: message = "Process or its output pipes did not finish before the timeout."
            case .responseTooLarge: message = "Process output exceeded the capture limit."
            default: message = "Could not run process or read its output."
            }
            return ProcessResult(standardOutput: String(decoding: captured[0], as: UTF8.self),
                                 standardError: message, terminationStatus: -1)
        }
    }
}
