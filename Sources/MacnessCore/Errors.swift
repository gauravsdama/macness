import Foundation

public enum MacnessError: Error, CustomStringConvertible, Equatable {
    case usage(String)
    case runtime(String)
    case commandFailed(command: String, exitCode: Int32, stderr: String)

    public var description: String {
        switch self {
        case .usage(let message):
            return message
        case .runtime(let message):
            return "macness: \(message)"
        case .commandFailed(let command, let exitCode, let stderr):
            let suffix = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if suffix.isEmpty {
                return "macness: command failed with exit \(exitCode): \(command)"
            }
            return "macness: command failed with exit \(exitCode): \(command)\n\(suffix)"
        }
    }

    public var exitCode: Int32 {
        switch self {
        case .usage:
            return 64
        case .runtime:
            return 1
        case .commandFailed(_, let exitCode, _):
            return exitCode == 0 ? 1 : exitCode
        }
    }
}
