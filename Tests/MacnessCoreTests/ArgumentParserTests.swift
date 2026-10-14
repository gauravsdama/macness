@testable import MacnessCore
import Testing

@Test func parsesVersion() throws {
    #expect(try MacnessArguments.parse(["--version"]) == .version)
    #expect(MacnessVersion.current == "0.1.1")
}

@Test func parsesVerifyExpectations() throws {
    let command = try MacnessArguments.parse([
        "verify",
        "--bundle-id", "com.example.App",
        "--expect-window", "Main",
        "--expect-text=Ready",
        "--expect-role", "AXButton",
        "--no-screenshot",
    ])

    guard case .verify(let options) = command else {
        Issue.record("Expected verify command")
        return
    }

    #expect(options.target.bundleID == "com.example.App")
    #expect(options.expectedWindows == ["Main"])
    #expect(options.expectedTexts == ["Ready"])
    #expect(options.expectedRoles == ["AXButton"])
    #expect(options.screenshot == false)
}

@Test func parsesLaunchArgumentsAfterSeparator() throws {
    let command = try MacnessArguments.parse([
        "launch",
        "--app", "/tmp/Demo.app",
        "--fresh",
        "--",
        "--demo-mode",
        "fixture",
    ])

    guard case .launch(let options) = command else {
        Issue.record("Expected launch command")
        return
    }

    #expect(options.appPath == "/tmp/Demo.app")
    #expect(options.fresh)
    #expect(options.arguments == ["--demo-mode", "fixture"])
}

@Test func rejectsMissingSnapshotTarget() throws {
    do {
        _ = try MacnessArguments.parse(["snapshot"])
        Issue.record("Expected missing target to throw")
    } catch let error as MacnessError {
        #expect(error.description.contains("snapshot requires --bundle-id or --pid"))
    }
}

@Test func searchesAccessibilityTree() {
    let tree = AXNode(
        role: "AXApplication",
        title: "Demo",
        children: [
            AXNode(role: "AXWindow", title: "Main Window", children: [
                AXNode(role: "AXStaticText", value: "Ready for verification"),
                AXNode(role: "AXButton", title: "Run"),
            ]),
        ]
    )

    #expect(tree.containsText("ready"))
    #expect(tree.containsRole("AXButton"))
    #expect(!tree.containsText("missing"))
}

@Test func buildsOneAccessibilitySearchIndex() {
    let tree = AXNode(
        role: "AXApplication",
        title: "Demo",
        children: [
            AXNode(role: "AXButton", title: "Run"),
            AXNode(role: "AXStaticText", value: "Ready"),
        ]
    )

    let index = AXSearchIndex(root: tree)
    #expect(index.containsText("ready"))
    #expect(index.containsText("demo"))
    #expect(index.containsRole("AXButton"))
    #expect(!index.containsRole("AXWindow"))
}

@Test(arguments: [
    ["launch", "--bundle-id", "com.example.App", "--wait", "-1"],
    ["launch", "--bundle-id", "com.example.App", "--wait", "nan"],
    ["snapshot", "--pid", "0"],
    ["snapshot", "--pid", "123", "--max-depth", "21"],
    ["verify", "--bundle-id", "com.example.App", "--expect-text="],
    ["monitor", "--bundle-id", "com.example.App", "--count", "0"],
    ["monitor", "--bundle-id", "com.example.App", "--interval", "0"],
    ["logs", "--bundle-id", "com.example.App", "--seconds", "0"],
    ["logs", "--bundle-id", "com.example.App\" OR TRUEPREDICATE", "--seconds", "10"],
    ["build", "--project", "Demo.xcodeproj", "--action", "archive"],
    ["build", "--project="],
])
func rejectsUnsafeOptionValues(arguments: [String]) {
    do {
        _ = try MacnessArguments.parse(arguments)
        Issue.record("Expected invalid arguments to throw: \(arguments)")
    } catch let error as MacnessError {
        if case .usage = error {
            return
        }
        Issue.record("Expected a usage error, got: \(error)")
    } catch {
        Issue.record("Expected a MacnessError, got: \(error)")
    }
}
