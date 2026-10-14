import Foundation
@testable import MacnessCore
import Testing

@Test func drainsLargeStdoutAndStderrWithoutDeadlock() throws {
    let script = """
    i=0
    while [ "$i" -lt 20000 ]; do
      printf 'stdout-line-%s-abcdefghijklmnopqrstuvwxyz0123456789\\n' "$i"
      printf 'stderr-line-%s-abcdefghijklmnopqrstuvwxyz0123456789\\n' "$i" >&2
      i=$((i + 1))
    done
    """

    let result = try ProcessRunner().run(
        "/bin/sh",
        ["-c", script],
        captureOutput: true,
        timeout: 10,
        outputLimit: 4_096
    )

    #expect(result.exitCode == 0)
    #expect(result.stdout.utf8.count == 4_096)
    #expect(result.stderr.utf8.count == 4_096)
    #expect(result.stdoutTruncated)
    #expect(result.stderrTruncated)
}

@Test func terminatesTimedOutProcess() throws {
    let started = Date()
    do {
        _ = try ProcessRunner().run("/bin/sleep", ["10"], timeout: 0.1)
        Issue.record("Expected timeout")
    } catch let error as MacnessError {
        #expect(error.description.contains("timed out"))
    }
    #expect(Date().timeIntervalSince(started) < 3)
}

@Test func atomicallyWritesPrivateBoundedOutput() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let output = root.appendingPathComponent("logs.json")

    let result = try ProcessRunner().runWritingStdout(
        "/usr/bin/printf",
        ["private evidence"],
        to: output,
        timeout: 5,
        outputLimit: 1_024
    )

    #expect(result.exitCode == 0)
    #expect(try String(contentsOf: output, encoding: .utf8) == "private evidence")
    let attributes = try FileManager.default.attributesOfItem(atPath: output.path)
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path)
        .filter { $0.hasSuffix(".tmp") }
    #expect(leftovers.isEmpty)
}
