import Foundation
import XCTest
@testable import GaugentCore

final class ExecutableLocatorTests: XCTestCase {
    func testChildEnvironmentPreservesPrecedenceAndConfiguration() {
        let original = ["PATH": "/custom/bin:/usr/bin:/custom/bin", "CLAUDE_CONFIG_DIR": "/config", "CODEX_HOME": "/codex"]
        let home = URL(fileURLWithPath: "/example-home")
        let result = ExecutableLocator.childEnvironment(executable: "/launcher/bin/tool", environment: original, home: home)
        let paths = result["PATH"]!.split(separator: ":").map(String.init)
        XCTAssertEqual(Array(paths.prefix(3)), ["/custom/bin", "/usr/bin", "/launcher/bin"])
        XCTAssertEqual(Set(paths).count, paths.count)
        for path in ["/opt/homebrew/bin", "/usr/local/bin", "/example-home/.npm-global/bin", "/example-home/.volta/bin", "/bin"] {
            XCTAssertTrue(paths.contains(path))
        }
        XCTAssertEqual(result["CLAUDE_CONFIG_DIR"], original["CLAUDE_CONFIG_DIR"])
        XCTAssertEqual(result["CODEX_HOME"], original["CODEX_HOME"])
        XCTAssertTrue(ExecutableLocator.childEnvironment(executable: "/tool", environment: [:])["PATH"]!.contains("/usr/bin"))
    }

    func testDiscoveredEnvShebangRunsWithFinderPathForBothProcessClients() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bin = home.appendingPathComponent(".npm-global/bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let runtime = bin.appendingPathComponent("gaugent-test-runtime")
        let cli = bin.appendingPathComponent("gaugent-test-cli")
        try "#!/bin/sh\nexec /usr/bin/python3 \"$@\"\n".write(to: runtime, atomically: true, encoding: .utf8)
        try """
        #!/usr/bin/env gaugent-test-runtime
        import json, os, sys
        if '--auth' in sys.argv:
            print(os.environ['TEST_CONFIG'])
        else:
            for line in sys.stdin:
                q = json.loads(line)
                print(json.dumps({'id':q['id'],'result':{'config':os.environ['TEST_CONFIG']}}), flush=True)
        """.write(to: cli, atomically: true, encoding: .utf8)
        for url in [runtime, cli] { try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path) }
        let environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "TEST_CONFIG": "preserved"]
        let path = try XCTUnwrap(ExecutableLocator.locate("gaugent-test-cli", environment: environment, home: home))
        let auth = ProcessRunner(timeout: 5, environment: environment).run(executable: path, arguments: ["--auth"])
        XCTAssertTrue(auth.succeeded, auth.standardError)
        XCTAssertEqual(auth.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines), "preserved")
        let client = LineProcessClient(executable: path, arguments: [], currentDirectory: home, timeout: 5, environment: environment)
        defer { client.terminate() }
        try client.start()
        XCTAssertEqual(try JSONRPCSession(client: client).request("ping")["config"] as? String, "preserved")
    }
}
