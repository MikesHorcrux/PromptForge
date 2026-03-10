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
}
