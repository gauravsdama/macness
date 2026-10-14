import ApplicationServices
import CoreGraphics
import Foundation

public final class AccessibilityReader {
    private let maxChildrenPerNode: Int
    private let maxNodes: Int
    private let messagingTimeout: Float
    private let captureTimeout: TimeInterval

    public init() {
        self.maxNodes = 5_000
        self.maxChildrenPerNode = 250
        self.messagingTimeout = 1
        self.captureTimeout = 15
    }

    init(
        maxNodes: Int,
        maxChildrenPerNode: Int,
        messagingTimeout: Float,
        captureTimeout: TimeInterval
    ) {
        self.maxNodes = max(1, maxNodes)
        self.maxChildrenPerNode = max(1, maxChildrenPerNode)
        self.messagingTimeout = max(0.1, messagingTimeout)
        self.captureTimeout = max(0.1, captureTimeout)
    }

    public func capture(pid: Int32, maxDepth: Int) throws -> AXNode {
        try captureWithMetadata(pid: pid, maxDepth: maxDepth).root
    }

    func captureWithMetadata(pid: Int32, maxDepth: Int) throws -> AccessibilityCapture {
        guard AXIsProcessTrusted() else {
            throw MacnessError.runtime("Accessibility permission is not granted. Run `macness doctor --prompt` and allow access in System Settings.")
        }

        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, messagingTimeout)
        let boundedDepth = max(0, maxDepth)
        var state = TraversalState(
            deadline: ProcessInfo.processInfo.systemUptime + captureTimeout
        )
        let root = capture(element: appElement, depth: 0, maxDepth: boundedDepth, state: &state)
        let reasons = state.truncationReasons.sorted()
        return AccessibilityCapture(
            root: root,
            metadata: AccessibilitySnapshotMetadata(
                nodesVisited: state.nodesVisited,
                maxNodes: maxNodes,
                maxDepth: boundedDepth,
                maxChildrenPerNode: maxChildrenPerNode,
                maxDurationSeconds: captureTimeout,
                truncated: !reasons.isEmpty,
                truncationReasons: reasons
            )
        )
    }

    private func capture(
        element: AXUIElement,
        depth: Int,
        maxDepth: Int,
        state: inout TraversalState
    ) -> AXNode {
        state.nodesVisited += 1
        var node = AXNode(
            role: stringAttribute(element, kAXRoleAttribute),
            subrole: stringAttribute(element, kAXSubroleAttribute),
            title: stringAttribute(element, kAXTitleAttribute),
            value: stringAttribute(element, kAXValueAttribute),
            axDescription: stringAttribute(element, kAXDescriptionAttribute),
            identifier: stringAttribute(element, kAXIdentifierAttribute),
            help: stringAttribute(element, kAXHelpAttribute),
            enabled: boolAttribute(element, kAXEnabledAttribute),
            focused: boolAttribute(element, kAXFocusedAttribute),
            frame: frame(element)
        )

        guard let children = copyAttribute(element, kAXChildrenAttribute) as? [AXUIElement], !children.isEmpty else {
            return node
        }

        guard ProcessInfo.processInfo.systemUptime < state.deadline else {
            state.truncationReasons.insert("max-duration")
            return node
        }

        guard depth < maxDepth else {
            state.truncationReasons.insert("max-depth")
            return node
        }

        if children.count > maxChildrenPerNode {
            state.truncationReasons.insert("max-children-per-node")
        }

        for child in children.prefix(maxChildrenPerNode) {
            guard ProcessInfo.processInfo.systemUptime < state.deadline else {
                state.truncationReasons.insert("max-duration")
                break
            }
            guard state.nodesVisited < maxNodes else {
                state.truncationReasons.insert("max-nodes")
                break
            }
            node.children.append(capture(
                element: child,
                depth: depth + 1,
                maxDepth: maxDepth,
                state: &state
            ))
        }

        return node
    }

    private func frame(_ element: AXUIElement) -> RectSnapshot? {
        guard
            let positionValue = copyAttribute(element, kAXPositionAttribute),
            let sizeValue = copyAttribute(element, kAXSizeAttribute),
            let point = cgPoint(from: positionValue),
            let size = cgSize(from: sizeValue)
        else {
            return nil
        }
        return RectSnapshot(CGRect(origin: point, size: size))
    }

    private func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        guard let value = copyAttribute(element, attribute) else {
            return nil
        }
        return string(from: value)
    }

    private func boolAttribute(_ element: AXUIElement, _ attribute: String) -> Bool? {
        guard let value = copyAttribute(element, attribute) else {
            return nil
        }
        if let boolValue = value as? Bool {
            return boolValue
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        return nil
    }

    private func copyAttribute(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success, let value else {
            return nil
        }
        return value as AnyObject
    }

    private func string(from value: AnyObject) -> String? {
        if let string = value as? String {
            return string.isEmpty ? nil : string
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        if CFGetTypeID(value) == AXValueGetTypeID() {
            if let rect = cgRect(from: value) {
                return "\(Int(rect.origin.x)),\(Int(rect.origin.y)) \(Int(rect.size.width))x\(Int(rect.size.height))"
            }
            if let point = cgPoint(from: value) {
                return "\(Int(point.x)),\(Int(point.y))"
            }
            if let size = cgSize(from: value) {
                return "\(Int(size.width))x\(Int(size.height))"
            }
        }
        return nil
    }

    private func cgPoint(from value: AnyObject) -> CGPoint? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgPoint else {
            return nil
        }
        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else {
            return nil
        }
        return point
    }

    private func cgSize(from value: AnyObject) -> CGSize? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgSize else {
            return nil
        }
        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else {
            return nil
        }
        return size
    }

    private func cgRect(from value: AnyObject) -> CGRect? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgRect else {
            return nil
        }
        var rect = CGRect.zero
        guard AXValueGetValue(axValue, .cgRect, &rect) else {
            return nil
        }
        return rect
    }
}

struct AccessibilityCapture: Equatable {
    var root: AXNode
    var metadata: AccessibilitySnapshotMetadata

    init(root: AXNode, metadata: AccessibilitySnapshotMetadata) {
        self.root = root
        self.metadata = metadata
    }
}

private struct TraversalState {
    let deadline: TimeInterval
    var nodesVisited = 0
    var truncationReasons = Set<String>()
}
