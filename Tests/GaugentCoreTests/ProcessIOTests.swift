import Darwin
import Foundation
import XCTest
@testable import GaugentCore

final class ProcessIOTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func script(_ body: String) throws -> String {
        let url = directory.appendingPathComponent("child.py")
        try ("#!/usr/bin/python3\n" + body).write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url.path
    }

    func testRunnerBoundsDrainWhenDescendantKeepsPipesOpen() throws {
        let path = try script("""
        import os, time
        pid = os.fork()
        if pid == 0:
            time.sleep(60)
            os._exit(0)
        print(pid, flush=True)
        os._exit(0)
        """)
        let start = Date()
        let result = ProcessRunner(timeout: 0.5).run(executable: path, arguments: [])
        let pid = try XCTUnwrap(Int32(result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)))
        defer { kill(pid, SIGKILL) }
        XCTAssertEqual(result.terminationStatus, -1)
        XCTAssertTrue(result.standardError.contains("timeout"))
        XCTAssertLessThan(Date().timeIntervalSince(start), 2.5)
    }

    func testRunnerDrainsBothStreamsWithoutDeadlocking() throws {
        let path = try script("""
        import os
        for _ in range(32):
            os.write(1, b'o' * 16384)
            os.write(2, b'e' * 16384)
        """)
        let result = ProcessRunner(timeout: 5).run(executable: path, arguments: [])
        XCTAssertTrue(result.succeeded, result.standardError)
        XCTAssertEqual(result.standardOutput.count, 524288)
        XCTAssertEqual(result.standardError.count, 524288)
    }

    func testRunnerRejectsExcessiveOutput() throws {
        let path = try script("import sys\nsys.stdout.write('x' * (9 * 1024 * 1024))")
        let result = ProcessRunner(timeout: 5).run(executable: path, arguments: [])
        XCTAssertEqual(result.terminationStatus, -1)
        XCTAssertTrue(result.standardError.contains("capture limit"))
        XCTAssertLessThanOrEqual(result.standardOutput.utf8.count, ProcessIO.maximumOutputSize)
    }

    func testClientRejectsOversizedLineWithAndWithoutNewline() throws {
        for suffix in ["", " + '\\n'"] {
            let path = try script("import sys\nsys.stdout.write('{\"payload\":\"' + 'x' * (9 * 1024 * 1024) + '\"}'\(suffix))\nsys.stdout.flush()")
            let client = LineProcessClient(executable: path, arguments: [], currentDirectory: directory, timeout: 5)
            defer { client.terminate() }
            try client.start()
            XCTAssertThrowsError(try client.receive { _ in true }) {
                XCTAssertEqual($0 as? LineProcessError, .responseTooLarge)
            }
        }
    }

    func testClientChecksDeadlineBetweenBufferedMessages() throws {
        let path = try script("print('{\"id\":1}\\n{\"id\":2}', flush=True)")
        let client = LineProcessClient(executable: path, arguments: [], currentDirectory: directory, timeout: 5)
        defer { client.terminate() }
        try client.start()
        XCTAssertThrowsError(try client.receive { object in
            if object["id"] as? Int == 1 { client.expireDeadline(); return false }
            return true
        }) { XCTAssertEqual($0 as? LineProcessError, .timedOut) }
    }

    func testSendTimesOutWhenChildDoesNotReadInput() throws {
        let path = try script("import time\ntime.sleep(60)")
        let client = LineProcessClient(executable: path, arguments: [], currentDirectory: directory, timeout: 0.3)
        defer { client.terminate() }
        try client.start()
        let start = Date()
        XCTAssertThrowsError(try client.send(["payload": String(repeating: "x", count: 1024 * 1024)])) {
            XCTAssertEqual($0 as? LineProcessError, .timedOut)
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }

    func testClientPreservesFragmentedAndBatchedLinesThroughEOF() throws {
        let path = try script("""
        import os
        os.write(1, b'{"pay')
        os.write(1, b'load":"' + b'x' * 100000 + b'"}\\n')
        for _ in range(10000):
            os.write(1, b'{"notice":true}\\n')
        os.write(1, b'{"done":true}\\n')
        """)
        let client = LineProcessClient(executable: path, arguments: [], currentDirectory: directory, timeout: 5)
        defer { client.terminate() }
        try client.start()
        let first = try client.receive { $0["payload"] != nil }
        XCTAssertEqual((first["payload"] as? String)?.count, 100000)
        XCTAssertEqual(try client.receive { $0["done"] != nil }["done"] as? Bool, true)
        XCTAssertThrowsError(try client.receive { _ in true }) {
            XCTAssertEqual($0 as? LineProcessError, .disconnected)
        }
    }
}
