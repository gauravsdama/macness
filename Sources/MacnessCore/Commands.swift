import Foundation

public enum MacnessCommand: Equatable {
    case help
    case doctor(DoctorOptions)
    case build(BuildOptions)
    case launch(LaunchOptions)
    case snapshot(SnapshotOptions)
    case verify(VerifyOptions)
    case monitor(MonitorOptions)
    case logs(LogOptions)
}

public struct DoctorOptions: Equatable {
    public var prompt: Bool = false
    public var json: Bool = false
}

public struct BuildOptions: Equatable {
    public var project: String?
    public var workspace: String?
    public var scheme: String?
    public var configuration: String?
    public var destination: String?
    public var derivedDataPath: String?
    public var action: String = "build"
    public var extraArguments: [String] = []
}

public struct LaunchOptions: Equatable {
    public var appPath: String?
    public var bundleID: String?
    public var arguments: [String] = []
    public var waitSeconds: Double = 2
    public var fresh: Bool = false
    public var hide: Bool = false
}

public struct SnapshotOptions: Equatable {
    public var target: TargetSpec = TargetSpec()
    public var outRoot: String?
    public var label: String?
    public var maxDepth: Int = 6
    public var screenshot: Bool = true
}

public struct VerifyOptions: Equatable {
    public var target: TargetSpec = TargetSpec()
    public var outRoot: String?
    public var label: String?
    public var maxDepth: Int = 6
    public var screenshot: Bool = true
    public var expectedWindows: [String] = []
    public var expectedTexts: [String] = []
    public var expectedRoles: [String] = []
    public var expectRunning: Bool = true
}

public struct MonitorOptions: Equatable {
    public var target: TargetSpec = TargetSpec()
    public var outRoot: String?
    public var label: String?
    public var intervalSeconds: Double = 2
    public var count: Int = 10
    public var maxDepth: Int = 4
    public var screenshot: Bool = true
}

public struct LogOptions: Equatable {
    public var target: TargetSpec = TargetSpec()
    public var seconds: Int = 120
    public var outPath: String?
}
