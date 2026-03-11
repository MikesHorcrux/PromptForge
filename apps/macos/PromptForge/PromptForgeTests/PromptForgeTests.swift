//
//  PromptForgeTests.swift
//  PromptForgeTests
//
//  Created by Mike  Van Amburg on 3/10/26.
//

import Testing
@testable import PromptForge

struct PromptForgeTests {
    @Test func parsesLaunchContextArguments() async throws {
        let context = LaunchContext(arguments: ["PromptForge", "--project", "/tmp/project", "--engine-root", "/tmp/engine"])
        #expect(context.projectPath == "/tmp/project")
        #expect(context.engineRoot == "/tmp/engine")
    }

    @Test func prefersBundledEngineRootWhenPresent() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let bundledResourceRoot = tempRoot.appendingPathComponent("Resources", isDirectory: true)
        let bundledEngineRoot = bundledResourceRoot.appendingPathComponent("engine", isDirectory: true)
        try makeEngineRoot(at: bundledEngineRoot)

        let selection = EngineRuntimeLocator.resolve(
            projectURL: URL(fileURLWithPath: "/tmp/project"),
            explicitEngineRoot: nil,
            savedEngineRoot: nil,
            bundleResourceURL: bundledResourceRoot
        )

        #expect(selection?.rootPath == bundledEngineRoot.standardizedFileURL.path)
        #expect(selection?.source == .bundled)
    }

    @Test func returnsNilWhenNoProductionRuntimeExists() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let selection = EngineRuntimeLocator.resolve(
            projectURL: tempRoot.appendingPathComponent("project", isDirectory: true),
            explicitEngineRoot: nil,
            savedEngineRoot: nil,
            bundleResourceURL: tempRoot.appendingPathComponent("Resources", isDirectory: true)
        )

        #if DEBUG
        #expect(selection == nil)
        #else
        #expect(selection == nil)
        #endif
    }

    private func makeEngineRoot(at root: URL) throws {
        let srcRoot = root.appendingPathComponent("src/promptforge/helper", isDirectory: true)
        let pythonRoot = root.appendingPathComponent(".venv/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: srcRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: pythonRoot, withIntermediateDirectories: true)
        let helperPath = srcRoot.appendingPathComponent("server.py")
        try Data().write(to: helperPath)
        let pythonPath = pythonRoot.appendingPathComponent("python")
        try "#!/bin/sh\nexit 0\n".write(to: pythonPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: pythonPath.path
        )
    }
}
