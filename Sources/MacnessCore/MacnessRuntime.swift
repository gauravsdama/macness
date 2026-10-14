import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

public final class MacnessRuntime {
    private let processRunner: ProcessRunner
    private let accessibilityReader: AccessibilityReader
    private let artifactStore: ArtifactStore
    private let jsonEncoder: JSONEncoder

    public init(
        processRunner: ProcessRunner = ProcessRunner(),
        accessibilityReader: AccessibilityReader = AccessibilityReader(),
        fileManager: FileManager = .default
    ) {
        self.processRunner = processRunner
        self.accessibilityReader = accessibilityReader
        self.artifactStore = ArtifactStore(fileManager: fileManager)
        self.jsonEncoder = JSONEncoder()
        self.jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func run(_ command: MacnessCommand) throws -> Int32 {
        switch command {
        case .help:
            writeStdout(MacnessArguments.helpText)
            return 0
        case .version:
            writeStdout(MacnessVersion.current)
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
                result = try processRunner.run(
                    "/usr/bin/xcrun",
                    [tool] + arguments,
                    captureOutput: true,
                    check: false,
                    timeout: 10
                )
            } else if tool == "screencapture" {
                result = try processRunner.run(
                    "/usr/bin/which",
                    [tool],
                    captureOutput: true,
                    check: false,
                    timeout: 10
                )
            } else {
                result = try processRunner.run(
                    "/usr/bin/env",
                    [tool] + arguments,
                    captureOutput: true,
                    check: false,
                    timeout: 10
                )
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
        try processRunner.run("/usr/bin/xcrun", arguments, timeout: 1_800)
    }

    private func launch(_ options: LaunchOptions) throws {
        let appURL = options.appPath.map(absoluteURL)
        let bundleID = options.bundleID ?? appURL.flatMap { Bundle(url: $0)?.bundleIdentifier }
        if options.fresh, let bundleID {
            try terminateRunningApplications(bundleID: bundleID)
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

        try processRunner.run("/usr/bin/open", arguments, captureOutput: true, timeout: 30)

        let app: NSRunningApplication?
        if options.waitSeconds > 0 {
            app = waitForApplication(
                bundleID: bundleID,
                appURL: appURL,
                timeout: options.waitSeconds
            )
            guard app != nil else {
                throw MacnessError.runtime(
                    "launched app did not become ready within \(options.waitSeconds) seconds"
                )
            }
        } else {
            app = runningApplication(bundleID: bundleID, appURL: appURL)
        }

        var response: [String: String] = ["status": "launched"]
        if let bundleID {
            response["bundleID"] = bundleID
        }
        if let app {
            response["pid"] = String(app.processIdentifier)
            response["processName"] = app.localizedName ?? ""
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
        try artifactStore.writeJSON(snapshot, to: snapshotURL)
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
        try artifactStore.writeJSON(snapshot, to: snapshotURL)

        let accessibilityIndex = snapshot.accessibility.map { AXSearchIndex(root: $0) }

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
            let matched = accessibilityIndex?.containsText(expectedText) ?? false
            results.append(AssertionResult(
                name: "text:\(expectedText)",
                passed: matched,
                detail: matched
                    ? "found in accessibility tree"
                    : accessibilityMissDetail(snapshot, kind: "text")
            ))
        }

        for expectedRole in options.expectedRoles {
            let matched = accessibilityIndex?.containsRole(expectedRole) ?? false
            results.append(AssertionResult(
                name: "role:\(expectedRole)",
                passed: matched,
                detail: matched
                    ? "found in accessibility tree"
                    : accessibilityMissDetail(snapshot, kind: "role")
            ))
        }

        let report = VerificationReport(
            ok: results.allSatisfy(\.passed),
            snapshotPath: snapshotURL.path,
            results: results
        )
        let reportURL = runDirectory.appendingPathComponent("verify.json")
        try artifactStore.writeJSON(report, to: reportURL)
        return report
    }

    private func monitor(_ options: MonitorOptions) throws {
        var index = 0
        while index < options.count {
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
            if index < options.count {
                Thread.sleep(forTimeInterval: options.intervalSeconds)
            }
        }
    }

    private func logs(_ options: LogOptions) throws -> URL {
        let outputURL: URL
        if let outPath = options.outPath {
            outputURL = absoluteURL(outPath)
            try artifactStore.createPrivateParentDirectory(for: outputURL)
        } else {
            let runDirectory = try makeRunDirectory(root: nil, label: "logs")
            outputURL = runDirectory.appendingPathComponent("logs.json")
        }

        let predicate: String
        if let pid = options.target.pid {
            predicate = "processID == \(pid)"
        } else if let bundleID = options.target.bundleID,
                  let app = runningApplication(bundleID: bundleID, appURL: nil) {
            predicate = "processID == \(app.processIdentifier)"
        } else if let bundleID = options.target.bundleID {
            guard isValidBundleIdentifier(bundleID) else {
                throw MacnessError.usage("--bundle-id contains unsupported characters.")
            }
            predicate = "subsystem == \"\(bundleID)\" OR senderImagePath CONTAINS \"\(bundleID)\""
        } else {
            throw MacnessError.runtime("logs requires --bundle-id or --pid")
        }

        let logArguments = ["show", "--style", "json", "--last", "\(options.seconds)s", "--predicate", predicate]
        let result = try processRunner.runWritingStdout(
            "/usr/bin/log",
            logArguments,
            to: outputURL,
            check: false,
            timeout: min(TimeInterval(options.seconds + 30), 300)
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
        var accessibilityMetadata: AccessibilitySnapshotMetadata?
        var accessibilityError: String?
        do {
            let capture = try accessibilityReader.captureWithMetadata(
                pid: app.processIdentifier,
                maxDepth: maxDepth
            )
            accessibility = capture.root
            accessibilityMetadata = capture.metadata
        } catch {
            accessibilityError = "\(error)"
        }

        var screenshotPath: String?
        var screenshotError: String?
        if captureScreenshot {
            let screenshotURL = runDirectory.appendingPathComponent("screen.png")
            do {
                try processRunner.run(
                    "/usr/sbin/screencapture",
                    ["-x", screenshotURL.path],
                    captureOutput: true,
                    timeout: 30
                )
                try artifactStore.secureFile(at: screenshotURL)
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
            accessibilityMetadata: accessibilityMetadata,
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
        if let bundleID = target.bundleID, let app = runningApplication(bundleID: bundleID, appURL: nil) {
            return app
        }
        throw MacnessError.runtime("no running app found for bundle id \(target.bundleID ?? "")")
    }

    private func runningApplication(bundleID: String?, appURL: URL?) -> NSRunningApplication? {
        if let bundleID {
            return NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleID)
                .first { !$0.isTerminated }
        }
        guard let standardizedURL = appURL?.standardizedFileURL else { return nil }
        return NSWorkspace.shared.runningApplications.first {
            !$0.isTerminated && $0.bundleURL?.standardizedFileURL == standardizedURL
        }
    }

    private func waitForApplication(
        bundleID: String?,
        appURL: URL?,
        timeout: TimeInterval
    ) -> NSRunningApplication? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let app = runningApplication(bundleID: bundleID, appURL: appURL), app.isFinishedLaunching {
                return app
            }
            Thread.sleep(forTimeInterval: 0.05)
        } while Date() < deadline
        return nil
    }

    private func terminateRunningApplications(bundleID: String) throws {
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
        throw MacnessError.runtime("running app did not terminate within 5 seconds: \(bundleID)")
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
        try artifactStore.makeRunDirectory(root: root, label: label)
    }

    private func absoluteURL(_ path: String) -> URL {
        artifactStore.absoluteURL(path)
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL?) throws {
        if let url {
            try artifactStore.writeJSON(value, to: url)
        } else {
            let data = try jsonEncoder.encode(value)
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
    }

    private func writeStdout(_ message: String) {
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
    }

    private func isValidBundleIdentifier(_ value: String) -> Bool {
        !value.isEmpty
            && value.first != "."
            && value.last != "."
            && !value.contains("..")
            && value.unicodeScalars.allSatisfy {
                CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-")).contains($0)
            }
    }

    private func accessibilityMissDetail(_ snapshot: AppSnapshot, kind: String) -> String {
        if let error = snapshot.accessibilityError {
            return "accessibility capture unavailable: \(error)"
        }
        if let metadata = snapshot.accessibilityMetadata, metadata.truncated {
            return "\(kind) not found in captured portion; accessibility traversal truncated: "
                + metadata.truncationReasons.joined(separator: ", ")
        }
        return "\(kind) not found in accessibility tree"
    }
}
