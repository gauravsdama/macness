import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

public final class MacnessRuntime {
    private let processRunner: ProcessRunner
    private let accessibilityReader: AccessibilityReader
    private let fileManager: FileManager
    private let jsonEncoder: JSONEncoder

    public init(
        processRunner: ProcessRunner = ProcessRunner(),
        accessibilityReader: AccessibilityReader = AccessibilityReader(),
        fileManager: FileManager = .default
    ) {
        self.processRunner = processRunner
        self.accessibilityReader = accessibilityReader
        self.fileManager = fileManager
        self.jsonEncoder = JSONEncoder()
        self.jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func run(_ command: MacnessCommand) throws -> Int32 {
        switch command {
        case .help:
            writeStdout(MacnessArguments.helpText)
            return 0
        case .doctor(let options):
            try doctor(options)
            return 0
        case .build(let options):
            try build(options)
            return 0
        case .launch(let options):
            try launch(options)
            return 0
        case .snapshot(let options):
            let result = try snapshot(options)
            writeStdout(result.snapshotPath)
            return 0
        case .verify(let options):
            let report = try verify(options)
            try writeJSON(report, to: nil)
            return report.ok ? 0 : 2
        case .monitor(let options):
            try monitor(options)
            return 0
        case .logs(let options):
            let path = try logs(options)
            writeStdout(path.path)
            return 0
        }
    }

    private func doctor(_ options: DoctorOptions) throws {
        var checks: [DoctorCheck] = []
        checks.append(toolCheck("swift", arguments: ["--version"]))
        checks.append(toolCheck("xcodebuild", arguments: ["-version"], throughXcrun: true))
        checks.append(toolCheck("screencapture", arguments: []))

        let axTrusted: Bool
        if options.prompt {
            let promptKey = "AXTrustedCheckOptionPrompt"
            axTrusted = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
        } else {
            axTrusted = AXIsProcessTrusted()
        }
        checks.append(DoctorCheck(
            name: "accessibility",
            ok: axTrusted,
            detail: axTrusted ? "granted" : "not granted; run `macness doctor --prompt`"
        ))

        let screenCaptureTrusted = CGPreflightScreenCaptureAccess()
        if options.prompt && !screenCaptureTrusted {
            _ = CGRequestScreenCaptureAccess()
        }
        checks.append(DoctorCheck(
            name: "screen-recording",
            ok: CGPreflightScreenCaptureAccess(),
            detail: CGPreflightScreenCaptureAccess() ? "granted" : "not granted; enable Screen & System Audio Recording for your terminal"
        ))

        if options.json {
            try writeJSON(checks, to: nil)
            return
        }

        writeStdout("Macness doctor")
        for check in checks {
            writeStdout("\(check.ok ? "OK" : "MISSING")  \(check.name): \(check.detail)")
        }
    }

    private func toolCheck(_ tool: String, arguments: [String], throughXcrun: Bool = false) -> DoctorCheck {
        do {
            let result: ProcessResult
            if throughXcrun {
                result = try processRunner.run("/usr/bin/xcrun", [tool] + arguments, captureOutput: true, check: false)
            } else if tool == "screencapture" {
                result = try processRunner.run("/usr/bin/which", [tool], captureOutput: true, check: false)
            } else {
                result = try processRunner.run("/usr/bin/env", [tool] + arguments, captureOutput: true, check: false)
            }
            let output = (result.stdout + result.stderr)
                .split(separator: "\n")
                .first
                .map(String.init) ?? "found"
            return DoctorCheck(name: tool, ok: result.exitCode == 0, detail: output)
        } catch {
            return DoctorCheck(name: tool, ok: false, detail: "\(error)")
        }
    }

    private func build(_ options: BuildOptions) throws {
        var arguments: [String] = ["xcodebuild"]
        if let project = options.project {
            arguments += ["-project", project]
        }
        if let workspace = options.workspace {
            arguments += ["-workspace", workspace]
        }
        if let scheme = options.scheme {
            arguments += ["-scheme", scheme]
        }
        if let configuration = options.configuration {
            arguments += ["-configuration", configuration]
        }
        if let destination = options.destination {
            arguments += ["-destination", destination]
        }
        if let derivedDataPath = options.derivedDataPath {
            arguments += ["-derivedDataPath", derivedDataPath]
        }
        arguments.append(options.action)
        arguments += options.extraArguments
        try processRunner.run("/usr/bin/xcrun", arguments)
    }

    private func launch(_ options: LaunchOptions) throws {
        let bundleID = options.bundleID ?? options.appPath.flatMap { bundleIdentifier(forAppPath: $0) }
        if options.fresh, let bundleID {
            terminateRunningApplications(bundleID: bundleID)
        }

        var arguments: [String] = []
        if options.fresh {
            arguments.append("-n")
        }
        if options.hide {
            arguments.append("-j")
        }
        if let bundleID = options.bundleID {
            arguments += ["-b", bundleID]
        } else if let appPath = options.appPath {
            arguments.append(appPath)
        }
        if !options.arguments.isEmpty {
            arguments.append("--args")
            arguments += options.arguments
        }

        try processRunner.run("/usr/bin/open", arguments, captureOutput: true)
        if options.waitSeconds > 0 {
            Thread.sleep(forTimeInterval: options.waitSeconds)
        }

        var response: [String: String] = ["status": "launched"]
        if let bundleID {
            response["bundleID"] = bundleID
            if let app = runningApplication(bundleID: bundleID) {
                response["pid"] = String(app.processIdentifier)
                response["processName"] = app.localizedName ?? ""
            }
        }
        try writeJSON(response, to: nil)
    }

    private func snapshot(_ options: SnapshotOptions) throws -> VerificationReport {
        let runDirectory = try makeRunDirectory(root: options.outRoot, label: options.label ?? "snapshot")
        let snapshot = try collectSnapshot(
            target: options.target,
            runDirectory: runDirectory,
            maxDepth: options.maxDepth,
            captureScreenshot: options.screenshot
        )
        let snapshotURL = runDirectory.appendingPathComponent("snapshot.json")
        try writeJSON(snapshot, to: snapshotURL)
        return VerificationReport(ok: true, snapshotPath: snapshotURL.path, results: [])
    }

    private func verify(_ options: VerifyOptions) throws -> VerificationReport {
        let runDirectory = try makeRunDirectory(root: options.outRoot, label: options.label ?? "verify")
        let snapshot = try collectSnapshot(
            target: options.target,
            runDirectory: runDirectory,
            maxDepth: options.maxDepth,
            captureScreenshot: options.screenshot
        )
        let snapshotURL = runDirectory.appendingPathComponent("snapshot.json")
        try writeJSON(snapshot, to: snapshotURL)

        var results: [AssertionResult] = []
        if options.expectRunning {
            results.append(AssertionResult(
                name: "running",
                passed: true,
                detail: "pid \(snapshot.target.pid)"
            ))
        }

        for expectedWindow in options.expectedWindows {
            let matched = snapshot.windows.contains { window in
                [window.title, window.ownerName]
                    .compactMap { $0 }
                    .contains { $0.localizedCaseInsensitiveContains(expectedWindow) }
            }
            results.append(AssertionResult(
                name: "window:\(expectedWindow)",
                passed: matched,
                detail: matched ? "found matching window" : "no visible window title or owner contains `\(expectedWindow)`"
            ))
        }

        for expectedText in options.expectedTexts {
            let matched = snapshot.accessibility?.containsText(expectedText) ?? false
            results.append(AssertionResult(
                name: "text:\(expectedText)",
                passed: matched,
                detail: matched ? "found in accessibility tree" : "not found in accessibility tree"
            ))
        }

        for expectedRole in options.expectedRoles {
            let matched = snapshot.accessibility?.containsRole(expectedRole) ?? false
            results.append(AssertionResult(
                name: "role:\(expectedRole)",
                passed: matched,
                detail: matched ? "found in accessibility tree" : "not found in accessibility tree"
            ))
        }

        let report = VerificationReport(
            ok: results.allSatisfy(\.passed),
            snapshotPath: snapshotURL.path,
            results: results
        )
        let reportURL = runDirectory.appendingPathComponent("verify.json")
        try writeJSON(report, to: reportURL)
        return report
    }

    private func monitor(_ options: MonitorOptions) throws {
        var index = 0
        while options.count == 0 || index < options.count {
            let label = [options.label, String(format: "%03d", index + 1)]
                .compactMap { $0 }
                .joined(separator: "-")
            let snapshotOptions = SnapshotOptions(
                target: options.target,
                outRoot: options.outRoot,
                label: label.isEmpty ? "monitor" : label,
                maxDepth: options.maxDepth,
                screenshot: options.screenshot
            )
            let result = try snapshot(snapshotOptions)
            writeStdout(result.snapshotPath)
            index += 1
            if options.count == 0 || index < options.count {
                Thread.sleep(forTimeInterval: options.intervalSeconds)
            }
        }
    }

    private func logs(_ options: LogOptions) throws -> URL {
        let outputURL: URL
        if let outPath = options.outPath {
            outputURL = absoluteURL(outPath)
            try createParentDirectory(for: outputURL)
        } else {
            let runDirectory = try makeRunDirectory(root: nil, label: "logs")
            outputURL = runDirectory.appendingPathComponent("logs.json")
        }

        let predicate: String
        if let pid = options.target.pid {
            predicate = "processID == \(pid)"
        } else if let bundleID = options.target.bundleID, let app = runningApplication(bundleID: bundleID) {
            predicate = "processID == \(app.processIdentifier)"
        } else if let bundleID = options.target.bundleID {
            predicate = "subsystem == \"\(bundleID)\" OR senderImagePath CONTAINS \"\(bundleID)\""
        } else {
            throw MacnessError.runtime("logs requires --bundle-id or --pid")
        }

        let logArguments = ["show", "--style", "json", "--last", "\(options.seconds)s", "--predicate", predicate]
        let result = try processRunner.runWritingStdout(
            "/usr/bin/log",
            logArguments,
            to: outputURL,
            check: false
        )
        if result.exitCode != 0 {
            throw MacnessError.commandFailed(
                command: processRunner.renderCommand("/usr/bin/log", logArguments),
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }
        return outputURL
    }

    private func collectSnapshot(
        target: TargetSpec,
        runDirectory: URL,
        maxDepth: Int,
        captureScreenshot: Bool
    ) throws -> AppSnapshot {
        let app = try resolveRunningApplication(target)
        let targetSnapshot = TargetSnapshot(
            bundleID: app.bundleIdentifier,
            processName: app.localizedName,
            pid: app.processIdentifier,
            bundleURL: app.bundleURL?.path,
            executableURL: app.executableURL?.path,
            activationPolicy: activationPolicyName(app.activationPolicy)
        )

        let windows = collectWindows(pid: app.processIdentifier)

        var accessibility: AXNode?
        var accessibilityError: String?
        do {
            accessibility = try accessibilityReader.capture(pid: app.processIdentifier, maxDepth: maxDepth)
        } catch {
            accessibilityError = "\(error)"
        }

        var screenshotPath: String?
        var screenshotError: String?
        if captureScreenshot {
            let screenshotURL = runDirectory.appendingPathComponent("screen.png")
            do {
                try processRunner.run("/usr/sbin/screencapture", ["-x", screenshotURL.path], captureOutput: true)
                screenshotPath = screenshotURL.path
            } catch {
                screenshotError = "\(error)"
            }
        }

        return AppSnapshot(
            capturedAt: ISO8601DateFormatter().string(from: Date()),
            target: targetSnapshot,
            windows: windows,
            accessibility: accessibility,
            accessibilityError: accessibilityError,
            screenshotPath: screenshotPath,
            screenshotError: screenshotError
        )
    }

    private func collectWindows(pid: Int32) -> [WindowSnapshot] {
        guard let rawWindows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        return rawWindows.compactMap { item in
            guard let ownerPID = item[kCGWindowOwnerPID as String] as? Int, ownerPID == Int(pid) else {
                return nil
            }

            var bounds: RectSnapshot?
            if
                let dictionary = item[kCGWindowBounds as String] as? NSDictionary,
                let rect = CGRect(dictionaryRepresentation: dictionary as CFDictionary)
            {
                bounds = RectSnapshot(rect)
            }

            return WindowSnapshot(
                id: (item[kCGWindowNumber as String] as? UInt32) ?? 0,
                ownerName: item[kCGWindowOwnerName as String] as? String,
                title: item[kCGWindowName as String] as? String,
                bounds: bounds,
                layer: item[kCGWindowLayer as String] as? Int,
                alpha: item[kCGWindowAlpha as String] as? Double,
                isOnscreen: (item[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue
            )
        }
    }

    private func resolveRunningApplication(_ target: TargetSpec) throws -> NSRunningApplication {
        if let pid = target.pid {
            guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else {
                throw MacnessError.runtime("no running app found for pid \(pid)")
            }
            return app
        }
        if let bundleID = target.bundleID, let app = runningApplication(bundleID: bundleID) {
            return app
        }
        throw MacnessError.runtime("no running app found for bundle id \(target.bundleID ?? "")")
    }

    private func runningApplication(bundleID: String) -> NSRunningApplication? {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .first { !$0.isTerminated }
    }

    private func terminateRunningApplications(bundleID: String) {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        for app in apps where !app.isTerminated {
            _ = app.terminate()
        }

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).allSatisfy(\.isTerminated) {
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    private func bundleIdentifier(forAppPath path: String) -> String? {
        Bundle(url: absoluteURL(path))?.bundleIdentifier
    }

    private func activationPolicyName(_ policy: NSApplication.ActivationPolicy) -> String {
        switch policy {
        case .regular:
            return "regular"
        case .accessory:
            return "accessory"
        case .prohibited:
            return "prohibited"
        @unknown default:
            return "unknown"
        }
    }

    private func makeRunDirectory(root: String?, label: String?) throws -> URL {
        let rootURL = absoluteURL(root ?? ".macness/runs")
        let timestamp = ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "")
        let suffix = sanitize(label ?? "run")
        let runDirectory = rootURL.appendingPathComponent("\(timestamp)-\(suffix)", isDirectory: true)
        try fileManager.createDirectory(at: runDirectory, withIntermediateDirectories: true)
        return runDirectory
    }

    private func createParentDirectory(for url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    private func absoluteURL(_ path: String) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent(path)
    }

    private func sanitize(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let sanitized = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return sanitized.isEmpty ? "run" : sanitized
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL?) throws {
        let data = try jsonEncoder.encode(value)
        if let url {
            try data.write(to: url)
        } else {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
    }

    private func writeStdout(_ message: String) {
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
    }
}
