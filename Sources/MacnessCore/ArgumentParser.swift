import Foundation

public enum MacnessArguments {
    public static let helpText = """
    macness: a macOS app harness for agent-driven development

    Usage:
      macness doctor [--prompt] [--json]
      macness build (--project PATH | --workspace PATH) [--scheme NAME] [--configuration NAME] [--destination DEST] [--derived-data-path PATH] [--action build|test] [-- XCODEBUILD_ARGS...]
      macness launch (--app PATH | --bundle-id ID) [--fresh] [--hide] [--wait SECONDS] [-- APP_ARGS...]
      macness snapshot (--bundle-id ID | --pid PID) [--out DIR] [--label NAME] [--max-depth N] [--no-screenshot]
      macness verify (--bundle-id ID | --pid PID) [--expect-window TEXT] [--expect-text TEXT] [--expect-role ROLE] [--out DIR] [--label NAME] [--max-depth N] [--no-screenshot]
      macness monitor (--bundle-id ID | --pid PID) [--interval SECONDS] [--count N] [--out DIR] [--label NAME] [--no-screenshot]
      macness logs (--bundle-id ID | --pid PID) [--seconds N] [--out FILE]

    Examples:
      macness doctor --prompt
      macness build --project MyApp.xcodeproj --scheme MyApp --configuration Debug
      macness launch --app ./Build/Products/Debug/MyApp.app --fresh -- --demo-mode
      macness verify --bundle-id com.example.MyApp --expect-window MyApp --expect-text Ready

    Artifacts default to .macness/runs/<timestamp>-<label>/.
    """

    public static func parse(_ arguments: [String]) throws -> MacnessCommand {
        var scanner = ArgumentScanner(arguments)
        guard let command = scanner.pop() else {
            return .help
        }

        switch command {
        case "-h", "--help", "help":
            return .help
        case "doctor":
            return .doctor(try parseDoctor(&scanner))
        case "build":
            return .build(try parseBuild(&scanner))
        case "launch":
            return .launch(try parseLaunch(&scanner))
        case "snapshot":
            return .snapshot(try parseSnapshot(&scanner))
        case "verify":
            return .verify(try parseVerify(&scanner))
        case "monitor":
            return .monitor(try parseMonitor(&scanner))
        case "logs":
            return .logs(try parseLogs(&scanner))
        default:
            throw MacnessError.usage("Unknown command: \(command)\n\n\(helpText)")
        }
    }

    private static func parseDoctor(_ scanner: inout ArgumentScanner) throws -> DoctorOptions {
        var options = DoctorOptions()
        while let token = scanner.pop() {
            switch token {
            case "--prompt":
                options.prompt = true
            case "--json":
                options.json = true
            case "-h", "--help":
                throw MacnessError.usage(helpText)
            default:
                throw MacnessError.usage("Unknown doctor option: \(token)")
            }
        }
        return options
    }

    private static func parseBuild(_ scanner: inout ArgumentScanner) throws -> BuildOptions {
        var options = BuildOptions()
        while let token = scanner.pop() {
            if token == "--" {
                options.extraArguments.append(contentsOf: scanner.rest())
                break
            }
            let option = splitOption(token)
            switch option.name {
            case "--project":
                options.project = try scanner.value(for: option)
            case "--workspace":
                options.workspace = try scanner.value(for: option)
            case "--scheme":
                options.scheme = try scanner.value(for: option)
            case "--configuration":
                options.configuration = try scanner.value(for: option)
            case "--destination":
                options.destination = try scanner.value(for: option)
            case "--derived-data-path":
                options.derivedDataPath = try scanner.value(for: option)
            case "--action":
                options.action = try scanner.value(for: option)
            case "-h", "--help":
                throw MacnessError.usage(helpText)
            default:
                throw MacnessError.usage("Unknown build option: \(token)")
            }
        }
        if options.project != nil && options.workspace != nil {
            throw MacnessError.usage("Use either --project or --workspace, not both.")
        }
        if options.project == nil && options.workspace == nil {
            throw MacnessError.usage("build requires --project or --workspace.")
        }
        return options
    }

    private static func parseLaunch(_ scanner: inout ArgumentScanner) throws -> LaunchOptions {
        var options = LaunchOptions()
        while let token = scanner.pop() {
            if token == "--" {
                options.arguments.append(contentsOf: scanner.rest())
                break
            }
            let option = splitOption(token)
            switch option.name {
            case "--app":
                options.appPath = try scanner.value(for: option)
            case "--bundle-id":
                options.bundleID = try scanner.value(for: option)
            case "--wait":
                options.waitSeconds = try parseDouble(scanner.value(for: option), flag: option.name)
            case "--fresh":
                options.fresh = true
            case "--hide":
                options.hide = true
            case "-h", "--help":
                throw MacnessError.usage(helpText)
            default:
                throw MacnessError.usage("Unknown launch option: \(token)")
            }
        }
        if options.appPath != nil && options.bundleID != nil {
            throw MacnessError.usage("Use either --app or --bundle-id, not both.")
        }
        if options.appPath == nil && options.bundleID == nil {
            throw MacnessError.usage("launch requires --app or --bundle-id.")
        }
        return options
    }

    private static func parseSnapshot(_ scanner: inout ArgumentScanner) throws -> SnapshotOptions {
        var options = SnapshotOptions()
        while let token = scanner.pop() {
            let option = splitOption(token)
            switch option.name {
            case "--bundle-id":
                options.target.bundleID = try scanner.value(for: option)
            case "--pid":
                options.target.pid = try parsePID(scanner.value(for: option), flag: option.name)
            case "--out":
                options.outRoot = try scanner.value(for: option)
            case "--label":
                options.label = try scanner.value(for: option)
            case "--max-depth":
                options.maxDepth = try parseInt(scanner.value(for: option), flag: option.name)
            case "--no-screenshot":
                options.screenshot = false
            case "-h", "--help":
                throw MacnessError.usage(helpText)
            default:
                throw MacnessError.usage("Unknown snapshot option: \(token)")
            }
        }
        try validateTarget(options.target, command: "snapshot")
        return options
    }

    private static func parseVerify(_ scanner: inout ArgumentScanner) throws -> VerifyOptions {
        var options = VerifyOptions()
        while let token = scanner.pop() {
            let option = splitOption(token)
            switch option.name {
            case "--bundle-id":
                options.target.bundleID = try scanner.value(for: option)
            case "--pid":
                options.target.pid = try parsePID(scanner.value(for: option), flag: option.name)
            case "--out":
                options.outRoot = try scanner.value(for: option)
            case "--label":
                options.label = try scanner.value(for: option)
            case "--max-depth":
                options.maxDepth = try parseInt(scanner.value(for: option), flag: option.name)
            case "--no-screenshot":
                options.screenshot = false
            case "--expect-window":
                options.expectedWindows.append(try scanner.value(for: option))
            case "--expect-text":
                options.expectedTexts.append(try scanner.value(for: option))
            case "--expect-role":
                options.expectedRoles.append(try scanner.value(for: option))
            case "--no-running-check":
                options.expectRunning = false
            case "-h", "--help":
                throw MacnessError.usage(helpText)
            default:
                throw MacnessError.usage("Unknown verify option: \(token)")
            }
        }
        try validateTarget(options.target, command: "verify")
        return options
    }

    private static func parseMonitor(_ scanner: inout ArgumentScanner) throws -> MonitorOptions {
        var options = MonitorOptions()
        while let token = scanner.pop() {
            let option = splitOption(token)
            switch option.name {
            case "--bundle-id":
                options.target.bundleID = try scanner.value(for: option)
            case "--pid":
                options.target.pid = try parsePID(scanner.value(for: option), flag: option.name)
            case "--out":
                options.outRoot = try scanner.value(for: option)
            case "--label":
                options.label = try scanner.value(for: option)
            case "--interval":
                options.intervalSeconds = try parseDouble(scanner.value(for: option), flag: option.name)
            case "--count":
                options.count = try parseInt(scanner.value(for: option), flag: option.name)
            case "--max-depth":
                options.maxDepth = try parseInt(scanner.value(for: option), flag: option.name)
            case "--no-screenshot":
                options.screenshot = false
            case "-h", "--help":
                throw MacnessError.usage(helpText)
            default:
                throw MacnessError.usage("Unknown monitor option: \(token)")
            }
        }
        try validateTarget(options.target, command: "monitor")
        return options
    }

    private static func parseLogs(_ scanner: inout ArgumentScanner) throws -> LogOptions {
        var options = LogOptions()
        while let token = scanner.pop() {
            let option = splitOption(token)
            switch option.name {
            case "--bundle-id":
                options.target.bundleID = try scanner.value(for: option)
            case "--pid":
                options.target.pid = try parsePID(scanner.value(for: option), flag: option.name)
            case "--seconds":
                options.seconds = try parseInt(scanner.value(for: option), flag: option.name)
            case "--out":
                options.outPath = try scanner.value(for: option)
            case "-h", "--help":
                throw MacnessError.usage(helpText)
            default:
                throw MacnessError.usage("Unknown logs option: \(token)")
            }
        }
        try validateTarget(options.target, command: "logs")
        return options
    }

    private static func validateTarget(_ target: TargetSpec, command: String) throws {
        if target.bundleID != nil && target.pid != nil {
            throw MacnessError.usage("Use either --bundle-id or --pid, not both.")
        }
        if target.isEmpty {
            throw MacnessError.usage("\(command) requires --bundle-id or --pid.")
        }
    }

    private static func splitOption(_ token: String) -> ParsedOption {
        guard token.hasPrefix("--"), let index = token.firstIndex(of: "=") else {
            return ParsedOption(name: token, inlineValue: nil)
        }
        return ParsedOption(
            name: String(token[..<index]),
            inlineValue: String(token[token.index(after: index)...])
        )
    }

    private static func parseInt(_ value: String, flag: String) throws -> Int {
        guard let parsed = Int(value) else {
            throw MacnessError.usage("\(flag) expects an integer.")
        }
        return parsed
    }

    private static func parsePID(_ value: String, flag: String) throws -> Int32 {
        guard let parsed = Int32(value) else {
            throw MacnessError.usage("\(flag) expects a process id.")
        }
        return parsed
    }

    private static func parseDouble(_ value: String, flag: String) throws -> Double {
        guard let parsed = Double(value) else {
            throw MacnessError.usage("\(flag) expects a number.")
        }
        return parsed
    }
}

private struct ParsedOption {
    var name: String
    var inlineValue: String?
}

private struct ArgumentScanner {
    private var arguments: [String]
    private var index: Int = 0

    init(_ arguments: [String]) {
        self.arguments = arguments
    }

    mutating func pop() -> String? {
        guard index < arguments.count else {
            return nil
        }
        let value = arguments[index]
        index += 1
        return value
    }

    mutating func value(for option: ParsedOption) throws -> String {
        if let inlineValue = option.inlineValue {
            return inlineValue
        }
        guard let value = pop(), !value.hasPrefix("--") else {
            throw MacnessError.usage("\(option.name) requires a value.")
        }
        return value
    }

    mutating func rest() -> [String] {
        let suffix = Array(arguments[index...])
        index = arguments.count
        return suffix
    }
}
