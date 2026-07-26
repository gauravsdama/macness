import ApplicationServices
import CoreGraphics
import Foundation

public final class AccessibilityReader {
    private let maxChildrenPerNode = 250

    public init() {}

    public func capture(pid: Int32, maxDepth: Int) throws -> AXNode {
        guard AXIsProcessTrusted() else {
            throw MacnessError.runtime("Accessibility permission is not granted. Run `macness doctor --prompt` and allow access in System Settings.")
        }

        let appElement = AXUIElementCreateApplication(pid)
        return capture(element: appElement, depth: 0, maxDepth: max(0, maxDepth))
    }

    private func capture(element: AXUIElement, depth: Int, maxDepth: Int) -> AXNode {
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

        guard depth < maxDepth else {
            return node
        }

        if let children = copyAttribute(element, kAXChildrenAttribute) as? [AXUIElement] {
            node.children = children.prefix(maxChildrenPerNode).map {
                capture(element: $0, depth: depth + 1, maxDepth: maxDepth)
            }
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
