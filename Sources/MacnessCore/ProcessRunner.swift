import Darwin
import Foundation

public struct ProcessResult: Equatable {
    public var executable: String
    public var arguments: [String]
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String
    var stdoutTruncated: Bool = false
    var stderrTruncated: Bool = false
}

public final class ProcessRunner {
    static let defaultTimeout: TimeInterval = 300
    static let defaultCaptureLimit = 1_048_576
    static let defaultFileOutputLimit = 50 * 1_048_576

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
        try run(
            executable,
            arguments,
            currentDirectory: currentDirectory,
            environment: environment,
            captureOutput: captureOutput,
            check: check,
            timeout: ProcessRunner.defaultTimeout
        )
    }

    @discardableResult
    func run(
        _ executable: String,
        _ arguments: [String],
        currentDirectory: URL? = nil,
        environment: [String: String]? = nil,
        captureOutput: Bool = false,
        check: Bool = true,
        timeout: TimeInterval,
        outputLimit: Int = ProcessRunner.defaultCaptureLimit
    ) throws -> ProcessResult {
        let process = configuredProcess(
            executable,
            arguments,
            currentDirectory: currentDirectory,
            environment: environment
        )

        let stdoutPipe = captureOutput ? Pipe() : nil
        let stderrPipe = captureOutput ? Pipe() : nil
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        let stdoutCollector = BoundedDataCollector(limit: outputLimit)
        let stderrCollector = BoundedDataCollector(limit: outputLimit)
        let drainGroup = DispatchGroup()
        if let stdoutPipe {
            startDrain(stdoutPipe.fileHandleForReading, into: stdoutCollector, group: drainGroup)
        }
        if let stderrPipe {
            startDrain(stderrPipe.fileHandleForReading, into: stderrCollector, group: drainGroup)
        }

        let timedOut = waitForExit(process, timeout: timeout)
        try finishDrains(
            drainGroup,
            handles: [stdoutPipe, stderrPipe].compactMap { $0?.fileHandleForReading }
        )

        let stdout = stdoutCollector.snapshot()
        let stderr = stderrCollector.snapshot()
        let result = ProcessResult(
            executable: executable,
            arguments: arguments,
            exitCode: process.terminationStatus,
            stdout: stdout.string,
            stderr: stderr.string,
            stdoutTruncated: stdout.truncated,
            stderrTruncated: stderr.truncated
        )

        if timedOut {
            throw timeoutError(executable, arguments, timeout: timeout, stderr: result.stderr)
        }
        try validateResult(result, enabled: check)
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
        try runWritingStdout(
            executable,
            arguments,
            to: outputURL,
            currentDirectory: currentDirectory,
            environment: environment,
            check: check,
            timeout: ProcessRunner.defaultTimeout
        )
    }

    @discardableResult
    func runWritingStdout(
        _ executable: String,
        _ arguments: [String],
        to outputURL: URL,
        currentDirectory: URL? = nil,
        environment: [String: String]? = nil,
        check: Bool = true,
        timeout: TimeInterval,
        outputLimit: Int = ProcessRunner.defaultFileOutputLimit,
        errorLimit: Int = ProcessRunner.defaultCaptureLimit
    ) throws -> ProcessResult {
        let temporaryURL = outputURL.deletingLastPathComponent().appendingPathComponent(
            ".\(outputURL.lastPathComponent).\(UUID().uuidString).tmp"
        )
        guard FileManager.default.createFile(
            atPath: temporaryURL.path,
            contents: nil,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw MacnessError.runtime("could not create private output file at \(temporaryURL.path)")
        }
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        let outputHandle = try FileHandle(forWritingTo: temporaryURL)
        defer { try? outputHandle.close() }

        let process = configuredProcess(
            executable,
            arguments,
            currentDirectory: currentDirectory,
            environment: environment
        )
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        let stdoutCollector = BoundedFileCollector(handle: outputHandle, limit: outputLimit)
        let stderrCollector = BoundedDataCollector(limit: errorLimit)
        let drainGroup = DispatchGroup()
        startDrain(stdoutPipe.fileHandleForReading, into: stdoutCollector, group: drainGroup)
        startDrain(stderrPipe.fileHandleForReading, into: stderrCollector, group: drainGroup)

        let timedOut = waitForExit(process, timeout: timeout)
        try finishDrains(
            drainGroup,
            handles: [stdoutPipe.fileHandleForReading, stderrPipe.fileHandleForReading]
        )
        try outputHandle.synchronize()

        let stderr = stderrCollector.snapshot()
        let stdout = stdoutCollector.snapshot()
        let result = ProcessResult(
            executable: executable,
            arguments: arguments,
            exitCode: process.terminationStatus,
            stdout: "",
            stderr: stderr.string,
            stdoutTruncated: stdout.truncated,
            stderrTruncated: stderr.truncated
        )

        if timedOut {
            throw timeoutError(executable, arguments, timeout: timeout, stderr: result.stderr)
        }
        try validateResult(result, enabled: check)
        if let error = stdout.errorDescription {
            throw MacnessError.runtime("could not write command output: \(error)")
        }
        guard !stdout.truncated else {
            throw MacnessError.runtime(
                "command output exceeded the \(outputLimit)-byte limit: \(renderCommand(executable, arguments))"
            )
        }
        try atomicReplace(temporaryURL, destination: outputURL)
        return result
    }

    private func configuredProcess(
        _ executable: String,
        _ arguments: [String],
        currentDirectory: URL?,
        environment: [String: String]?
    ) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        if let environment {
            process.environment = environment
        }
        return process
    }

    private func startDrain(
        _ handle: FileHandle,
        into collector: some OutputCollector,
        group: DispatchGroup
    ) {
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            defer { group.leave() }
            while true {
                let data = handle.availableData
                guard !data.isEmpty else { return }
                collector.append(data)
            }
        }
    }

    private func waitForExit(_ process: Process, timeout: TimeInterval) -> Bool {
        let boundedTimeout = max(0.1, timeout.isFinite ? timeout : ProcessRunner.defaultTimeout)
        let deadline = Date().addingTimeInterval(boundedTimeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        guard process.isRunning else {
            process.waitUntilExit()
            return false
        }

        process.terminate()
        let terminationDeadline = Date().addingTimeInterval(1)
        while process.isRunning && Date() < terminationDeadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning {
            Darwin.kill(process.processIdentifier, SIGKILL)
        }
        process.waitUntilExit()
        return true
    }

    private func finishDrains(_ group: DispatchGroup, handles: [FileHandle]) throws {
        if group.wait(timeout: .now() + 5) == .timedOut {
            for handle in handles {
                try? handle.close()
            }
            guard group.wait(timeout: .now() + 1) == .success else {
                throw MacnessError.runtime("subprocess output pipes did not close after termination")
            }
        }
    }

    private func validateResult(_ result: ProcessResult, enabled: Bool) throws {
        guard enabled, result.exitCode != 0 else { return }
        throw MacnessError.commandFailed(
            command: renderCommand(result.executable, result.arguments),
            exitCode: result.exitCode,
            stderr: annotated(result.stderr, truncated: result.stderrTruncated)
        )
    }

    private func timeoutError(
        _ executable: String,
        _ arguments: [String],
        timeout: TimeInterval,
        stderr: String
    ) -> MacnessError {
        let detail = stderr.isEmpty ? "" : " Child stderr: \(stderr)"
        return .runtime(
            "command timed out after \(String(format: "%.1f", timeout)) seconds: "
                + renderCommand(executable, arguments)
                + detail
        )
    }

    private func annotated(_ string: String, truncated: Bool) -> String {
        guard truncated else { return string }
        return string + (string.hasSuffix("\n") || string.isEmpty ? "" : "\n") + "[output truncated]"
    }

    private func atomicReplace(_ source: URL, destination: URL) throws {
        let result = source.path.withCString { sourcePath in
            destination.path.withCString { destinationPath in
                Darwin.rename(sourcePath, destinationPath)
            }
        }
        guard result == 0 else {
            throw MacnessError.runtime(
                "could not atomically write \(destination.path): \(String(cString: strerror(errno)))"
            )
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    }
}

private protocol OutputCollector: AnyObject, Sendable {
    func append(_ data: Data)
}

private final class BoundedDataCollector: OutputCollector, @unchecked Sendable {
    private let limit: Int
    private let lock = NSLock()
    private var data = Data()
    private var didTruncate = false

    init(limit: Int) {
        self.limit = max(0, limit)
    }

    func append(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }
        let remaining = max(0, limit - data.count)
        if remaining > 0 {
            data.append(chunk.prefix(remaining))
        }
        if chunk.count > remaining {
            didTruncate = true
        }
    }

    func snapshot() -> (string: String, truncated: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (String(decoding: data, as: UTF8.self), didTruncate)
    }
}

private final class BoundedFileCollector: OutputCollector, @unchecked Sendable {
    private let handle: FileHandle
    private let limit: Int
    private var bytesWritten = 0
    private var truncated = false
    private var errorDescription: String?

    init(handle: FileHandle, limit: Int) {
        self.handle = handle
        self.limit = max(0, limit)
    }

    func append(_ chunk: Data) {
        let remaining = max(0, limit - bytesWritten)
        if remaining > 0 {
            let prefix = chunk.prefix(remaining)
            do {
                try handle.write(contentsOf: prefix)
                bytesWritten += prefix.count
            } catch {
                truncated = true
                errorDescription = String(describing: error)
            }
        }
        if chunk.count > remaining {
            truncated = true
        }
    }

    func snapshot() -> (truncated: Bool, errorDescription: String?) {
        (truncated, errorDescription)
    }
}
