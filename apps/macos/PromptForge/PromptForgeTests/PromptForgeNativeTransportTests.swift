import Foundation
import Testing
@testable import PromptForge

@MainActor
struct PromptForgeNativeTransportTests {
    @Test func nativeTransportCreatesLoadsAndSavesPromptWithoutBundledEngine() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let transport = try PromptForgeTransportFactory.makeTransport(
            projectRoot: tempRoot.path,
            runtimeSelection: nil
        )
        defer { transport.shutdown() }

        let projectPayload = try await transport.send(method: "project.open", params: [:])
        let project = projectPayload["metadata"] as? [String: Any]
        #expect(projectPayload["root"] as? String == tempRoot.path)
        #expect(project?["name"] as? String == tempRoot.lastPathComponent)

        _ = try await transport.send(
            method: "prompts.create",
            params: [
                "prompt": "support-policy",
                "name": "Support Policy",
            ]
        )

        let promptsPayload = try await transport.send(method: "prompts.list", params: [:])
        let prompts = promptsPayload["prompts"] as? [[String: Any]] ?? []
        #expect(prompts.count == 1)
        #expect(prompts.first?["version"] as? String == "support-policy")
        #expect(prompts.first?["name"] as? String == "Support Policy")

        let promptPayload = try await transport.send(method: "prompt.get", params: ["prompt": "support-policy"])
        let prompt = promptPayload["prompt"] as? [String: Any]
        #expect(prompt?["version"] as? String == "support-policy")
        #expect(prompt?["name"] as? String == "Support Policy")
        #expect((prompt?["system_prompt"] as? String ?? "").contains("focused assistant"))

        let saveResult = try await transport.send(
            method: "prompt.save",
            params: [
                "prompt": "support-policy",
                "system_prompt": "You are a careful assistant.",
                "user_template": "Answer with the policy details.",
                "purpose": "Handle policy questions.",
                "expected_behavior": "Stay concise.",
                "success_criteria": "Give the policy answer clearly.",
                "baseline_prompt_ref": "",
                "primary_scenario_suites": ["support-core"],
                "owner": "support",
                "audience": "agents",
                "release_notes": "Initial version",
                "builder_agent_model": "gpt-5-mini",
                "builder_permission_mode": "proposal_only",
                "research_policy": "prompt_only",
                "prompt_blocks": [
                    [
                        "block_id": "voice",
                        "title": "Voice",
                        "body": "Be direct.",
                        "target": "system",
                        "enabled": true,
                    ],
                ],
            ]
        )
        let savedPrompt = saveResult["prompt"] as? [String: Any]
        let insights = saveResult["insights"] as? [String: Any]
        #expect(savedPrompt?["purpose"] as? String == "Handle policy questions.")
        #expect(savedPrompt?["expected_behavior"] as? String == "Stay concise.")
        #expect(savedPrompt?["files"] as? [String] == ["prompt.json", "system.md", "user_template.md", "manifest.yaml", "variables.schema.json"])
        #expect((insights?["weak_cases"] as? [[String: Any]] ?? []).isEmpty)

        let savedSystem = try String(
            contentsOf: tempRoot.appendingPathComponent("prompt_packs/support-policy/system.md"),
            encoding: .utf8
        )
        #expect(savedSystem.contains("You are a careful assistant."))

        let settingsPayload = try await transport.send(method: "settings.get", params: [:])
        let settings = settingsPayload["settings"] as? [String: Any]
        #expect(settings?["preferred_provider"] as? String == "openai")
    }

    @Test func nativeOnlyTransportReturnsClearFallbackRequirement() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let transport = try PromptForgeTransportFactory.makeTransport(
            projectRoot: tempRoot.path,
            runtimeSelection: nil
        )
        defer { transport.shutdown() }

        var didThrow = false
        do {
            _ = try await transport.send(
                method: "agent.chat",
                params: [
                    "prompt": "support-policy",
                    "request": "Improve the prompt.",
                ]
            )
        } catch {
            didThrow = true
            #expect(error.localizedDescription.contains("packaged engine"))
        }
        #expect(didThrow)
    }

    @Test func nativeCodexEndpointsReturnStructuredFailureWhenCLIIsMissing() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let service = try NativeProjectService(
            projectRoot: tempRoot.path,
            codexBinary: "/definitely/missing/codex"
        )

        let deviceAuth = try service.handle(method: .connectionsCodexDeviceAuth, params: [:])
        #expect((deviceAuth["instructions"] as? String ?? "").contains("Codex CLI not found"))

        let loginResult = try service.handle(
            method: .connectionsCodexLoginAPIKey,
            params: ["api_key": "sk-test"]
        )
        #expect(loginResult["success"] as? Bool == false)
        #expect((loginResult["detail"] as? String ?? "").contains("Codex CLI not found"))
    }
}
