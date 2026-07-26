import Foundation

public struct ProcessResult: Equatable {
    public var executable: String
    public var arguments: [String]
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String
}

public final class ProcessRunner {
    public init() {}

    @discardableResult
    public func run(
        _ executable: String,
        _ arguments: [String],
        currentDirectory: URL? = nil,
        environment: [String: String]? = nil,
        captureOutput: Bool = false,
        check: Bool = true
    ) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        if let environment {
            process.environment = environment
        }

        let stdoutPipe = captureOutput ? Pipe() : nil
        let stderrPipe = captureOutput ? Pipe() : nil
        if let stdoutPipe {
            process.standardOutput = stdoutPipe
        }
        if let stderrPipe {
            process.standardError = stderrPipe
        }

        try process.run()
        process.waitUntilExit()

        let stdout = stdoutPipe.flatMap { String(data: $0.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) } ?? ""
        let stderr = stderrPipe.flatMap { String(data: $0.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) } ?? ""
        let result = ProcessResult(
            executable: executable,
            arguments: arguments,
            exitCode: process.terminationStatus,
            stdout: stdout,
            stderr: stderr
        )

        if check && result.exitCode != 0 {
            throw MacnessError.commandFailed(
                command: renderCommand(executable, arguments),
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }

        return result
    }

    public func renderCommand(_ executable: String, _ arguments: [String]) -> String {
        ([executable] + arguments).map { part in
            if part.rangeOfCharacter(from: .whitespacesAndNewlines) == nil {
                return part
            }
            return "'\(part.replacingOccurrences(of: "'", with: "'\\''"))'"
        }.joined(separator: " ")
    }

    @discardableResult
    public func runWritingStdout(
        _ executable: String,
        _ arguments: [String],
        to outputURL: URL,
        currentDirectory: URL? = nil,
        environment: [String: String]? = nil,
        check: Bool = true
    ) throws -> ProcessResult {
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let outputHandle = try FileHandle(forWritingTo: outputURL)
        defer {
            try? outputHandle.close()
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        process.standardOutput = outputHandle
        if let environment {
            process.environment = environment
        }

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let result = ProcessResult(
            executable: executable,
            arguments: arguments,
            exitCode: process.terminationStatus,
            stdout: "",
            stderr: stderr
        )

        if check && result.exitCode != 0 {
            throw MacnessError.commandFailed(
                command: renderCommand(executable, arguments),
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }

        return result
    }
}
