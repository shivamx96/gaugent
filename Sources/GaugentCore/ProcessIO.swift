import Darwin
import Foundation

/// Nonblocking pipe operations keep both reads and writes inside the caller's deadline.
enum ProcessIO {
    static let maximumOutputSize = 8 * 1024 * 1024
    static let chunkSize = 64 * 1024

    static func configure(_ handle: FileHandle, writing: Bool = false) throws {
        let fd = handle.fileDescriptor
        let flags = fcntl(fd, F_GETFL)
        guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 else {
            throw LineProcessError.disconnected
        }
        if writing, fcntl(fd, F_SETNOSIGPIPE, 1) != 0 {
            throw LineProcessError.disconnected
        }
    }

    /// nil means try again; empty data means EOF. Never waits for a descendant to close a pipe.
    static func read(_ handle: FileHandle) throws -> Data? {
        var bytes = [UInt8](repeating: 0, count: chunkSize)
        let count = Darwin.read(handle.fileDescriptor, &bytes, bytes.count)
        if count >= 0 { return Data(bytes.prefix(count)) }
        if errno == EAGAIN || errno == EINTR { return nil }
        throw LineProcessError.disconnected
    }

    static func wait(_ handles: [FileHandle], writing: Bool = false) {
        var descriptors = handles.map { pollfd(fd: $0.fileDescriptor, events: Int16(writing ? POLLOUT : POLLIN), revents: 0) }
        // Short bounded waits also let expireDeadline() interrupt a pending operation.
        _ = poll(&descriptors, nfds_t(descriptors.count), 20)
    }

    static func terminate(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let deadline = Date().addingTimeInterval(2)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit()
    }
}
