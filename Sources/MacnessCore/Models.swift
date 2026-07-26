import CoreGraphics
import Foundation

public struct TargetSpec: Codable, Equatable {
    public var bundleID: String?
    public var pid: Int32?

    public init(bundleID: String? = nil, pid: Int32? = nil) {
        self.bundleID = bundleID
        self.pid = pid
    }

    public var isEmpty: Bool {
        bundleID == nil && pid == nil
    }
}

public struct RectSnapshot: Codable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(_ rect: CGRect) {
        self.init(
            x: Double(rect.origin.x),
            y: Double(rect.origin.y),
            width: Double(rect.size.width),
            height: Double(rect.size.height)
        )
    }
}

public struct WindowSnapshot: Codable, Equatable {
    public var id: UInt32
    public var ownerName: String?
    public var title: String?
    public var bounds: RectSnapshot?
    public var layer: Int?
    public var alpha: Double?
    public var isOnscreen: Bool?
}

public struct TargetSnapshot: Codable, Equatable {
    public var bundleID: String?
    public var processName: String?
    public var pid: Int32
    public var bundleURL: String?
    public var executableURL: String?
    public var activationPolicy: String?
}

public struct AXNode: Codable, Equatable {
    public var role: String?
    public var subrole: String?
    public var title: String?
    public var value: String?
    public var axDescription: String?
    public var identifier: String?
    public var help: String?
    public var enabled: Bool?
    public var focused: Bool?
    public var frame: RectSnapshot?
    public var children: [AXNode]

    public init(
        role: String? = nil,
        subrole: String? = nil,
        title: String? = nil,
        value: String? = nil,
        axDescription: String? = nil,
        identifier: String? = nil,
        help: String? = nil,
        enabled: Bool? = nil,
        focused: Bool? = nil,
        frame: RectSnapshot? = nil,
        children: [AXNode] = []
    ) {
        self.role = role
        self.subrole = subrole
        self.title = title
        self.value = value
        self.axDescription = axDescription
        self.identifier = identifier
        self.help = help
        self.enabled = enabled
        self.focused = focused
        self.frame = frame
        self.children = children
    }

    enum CodingKeys: String, CodingKey {
        case role
        case subrole
        case title
        case value
        case axDescription = "description"
        case identifier
        case help
        case enabled
        case focused
        case frame
        case children
    }
}

public extension AXNode {
    var searchableStrings: [String] {
        var values = [role, subrole, title, value, axDescription, identifier, help].compactMap { $0 }
        for child in children {
            values.append(contentsOf: child.searchableStrings)
        }
        return values
    }

    func containsText(_ text: String) -> Bool {
        searchableStrings.contains { $0.localizedCaseInsensitiveContains(text) }
    }

    func containsRole(_ expectedRole: String) -> Bool {
        if role == expectedRole {
            return true
        }
        return children.contains { $0.containsRole(expectedRole) }
    }
}

public struct AppSnapshot: Codable, Equatable {
    public var capturedAt: String
    public var target: TargetSnapshot
    public var windows: [WindowSnapshot]
    public var accessibility: AXNode?
    public var accessibilityError: String?
    public var screenshotPath: String?
    public var screenshotError: String?
}

public struct AssertionResult: Codable, Equatable {
    public var name: String
    public var passed: Bool
    public var detail: String
}

public struct VerificationReport: Codable, Equatable {
    public var ok: Bool
    public var snapshotPath: String
    public var results: [AssertionResult]
}

public struct DoctorCheck: Codable, Equatable {
    public var name: String
    public var ok: Bool
    public var detail: String
}
