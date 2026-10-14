import Foundation

final class ArtifactStore {
    private let fileManager: FileManager
    private let encoder: JSONEncoder

    init(fileManager: FileManager) {
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func makeRunDirectory(root: String?, label: String?) throws -> URL {
        let rootURL = absoluteURL(root ?? ".macness/runs")
        try createPrivateDirectory(rootURL, withIntermediateDirectories: true)

        let timestamp = ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "")
        let suffix = sanitize(label ?? "run")

        for _ in 0..<10 {
            let nonce = UUID().uuidString.prefix(8).lowercased()
            let runDirectory = rootURL.appendingPathComponent(
                "\(timestamp)-\(suffix)-\(nonce)",
                isDirectory: true
            )
            do {
                try fileManager.createDirectory(
                    at: runDirectory,
                    withIntermediateDirectories: false,
                    attributes: [.posixPermissions: 0o700]
                )
                return runDirectory
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                continue
            }
        }
        throw MacnessError.runtime("could not allocate a unique artifact directory below \(rootURL.path)")
    }

    func createPrivateParentDirectory(for url: URL) throws {
        try createPrivateDirectory(url.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    func secureFile(at url: URL) throws {
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
        try secureFile(at: url)
    }

    func absoluteURL(_ path: String) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent(path)
    }

    private func createPrivateDirectory(_ url: URL, withIntermediateDirectories: Bool) throws {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw MacnessError.runtime("artifact path is not a directory: \(url.path)")
            }
            return
        }
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: withIntermediateDirectories,
            attributes: [.posixPermissions: 0o700]
        )
    }

    private func sanitize(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let sanitized = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return sanitized.isEmpty ? "run" : sanitized
    }
}
