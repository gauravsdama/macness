import Foundation
@testable import MacnessCore
import Testing

@Test func createsCollisionSafePrivateArtifacts() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ArtifactStore(fileManager: .default)

    let first = try store.makeRunDirectory(root: root.path, label: "same label")
    let second = try store.makeRunDirectory(root: root.path, label: "same label")
    #expect(first != second)

    let directoryAttributes = try FileManager.default.attributesOfItem(atPath: first.path)
    #expect((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)

    let output = first.appendingPathComponent("snapshot.json")
    try store.writeJSON(["secret": "value"], to: output)
    let fileAttributes = try FileManager.default.attributesOfItem(atPath: output.path)
    #expect((fileAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
}

@Test func encodesAccessibilityTraversalLimits() throws {
    let metadata = AccessibilitySnapshotMetadata(
        nodesVisited: 5_000,
        maxNodes: 5_000,
        maxDepth: 6,
        maxChildrenPerNode: 250,
        maxDurationSeconds: 15,
        truncated: true,
        truncationReasons: ["max-nodes"]
    )
    let snapshot = AppSnapshot(
        capturedAt: "2026-09-15T00:00:00Z",
        target: TargetSnapshot(
            bundleID: nil,
            processName: nil,
            pid: 1,
            bundleURL: nil,
            executableURL: nil,
            activationPolicy: nil
        ),
        windows: [],
        accessibility: AXNode(role: "AXApplication"),
        accessibilityMetadata: metadata,
        accessibilityError: nil,
        screenshotPath: nil,
        screenshotError: nil
    )

    let data = try JSONEncoder().encode(snapshot)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let encoded = try #require(object["accessibilityMetadata"] as? [String: Any])
    #expect(encoded["truncated"] as? Bool == true)
    #expect(encoded["maxNodes"] as? Int == 5_000)
    #expect(encoded["maxDurationSeconds"] as? Double == 15)
}
