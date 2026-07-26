import MacnessCore
import Testing

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
