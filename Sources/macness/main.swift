import Darwin
import Foundation
import MacnessCore

@main
struct MacnessCLI {
    static func main() {
        do {
            let command = try MacnessArguments.parse(Array(CommandLine.arguments.dropFirst()))
            let status = try MacnessRuntime().run(command)
            exit(status)
        } catch let error as MacnessError {
            writeStderr(error.description)
            exit(error.exitCode)
        } catch {
            writeStderr("macness: \(error)")
            exit(1)
        }
    }

    private static func writeStderr(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
