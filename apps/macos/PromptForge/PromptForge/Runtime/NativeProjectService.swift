import Foundation

private let nativeProjectDirectoryName = ".promptforge"
private let nativeProjectMetadataFileName = "project.json"
private let nativePromptDirectoryName = "prompts"
private let nativeDatasetDirectoryName = "datasets"
private let nativeScenarioDirectoryName = "scenarios"
private let nativeVarDirectoryName = "var"

private struct NativeProjectMetadata: Codable {
    var formatVersion: Int = 1
    var name: String = "PromptForge Project"
    var lastOpenedPrompt: String?
    var quickBenchmarkDataset: String = "datasets/core.jsonl"
    var fullEvaluationDataset: String = "datasets/core.jsonl"
    var quickBenchmarkRepeats: Int = 1
    var fullEvaluationRepeats: Int = 1
    var preferredProvider: String = ProviderID.openAI.rawValue
    var preferredJudgeProvider: String?
    var preferredGenerationModel: String = "gpt-5.4"
    var preferredJudgeModel: String = "gpt-5-mini"
    var preferredAgentModel: String = "gpt-5-mini"
    var builderPermissionMode: String = "proposal_only"
    var builderResearchPolicy: String = "prompt_only"
    var createdAt: String = nativeTimestamp()
    var updatedAt: String = nativeTimestamp()

    enum CodingKeys: String, CodingKey {
        case formatVersion = "format_version"
        case name
        case lastOpenedPrompt = "last_opened_prompt"
        case quickBenchmarkDataset = "quick_benchmark_dataset"
        case fullEvaluationDataset = "full_evaluation_dataset"
        case quickBenchmarkRepeats = "quick_benchmark_repeats"
        case fullEvaluationRepeats = "full_evaluation_repeats"
        case preferredProvider = "preferred_provider"
        case preferredJudgeProvider = "preferred_judge_provider"
        case preferredGenerationModel = "preferred_generation_model"
        case preferredJudgeModel = "preferred_judge_model"
        case preferredAgentModel = "preferred_agent_model"
        case builderPermissionMode = "builder_permission_mode"
        case builderResearchPolicy = "builder_research_policy"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

private struct NativePromptManifest {
    var version: String
    var name: String
    var description: String
}

private struct NativePromptBlock: Codable {
    var blockID: String
    var title: String
    var body: String
    var target: String
    var enabled: Bool

    enum CodingKeys: String, CodingKey {
        case blockID = "block_id"
        case title
        case body
        case target
        case enabled
    }
}

private struct NativePromptBrief: Codable {
    var formatVersion: Int = 1
    var purpose: String = ""
    var expectedBehavior: String = ""
    var successCriteria: String = ""
    var baselinePromptRef: String = ""
    var primaryScenarioSuites: [String] = []
    var owner: String = ""
    var audience: String = ""
    var releaseNotes: String = ""
    var builderAgentModel: String = "gpt-5-mini"
    var builderPermissionMode: String = "proposal_only"
    var researchPolicy: String = "prompt_only"
    var promptBlocks: [NativePromptBlock] = []

    enum CodingKeys: String, CodingKey {
        case formatVersion = "format_version"
        case purpose
        case expectedBehavior = "expected_behavior"
        case successCriteria = "success_criteria"
        case baselinePromptRef = "baseline_prompt_ref"
        case primaryScenarioSuites = "primary_scenario_suites"
        case owner
        case audience
        case releaseNotes = "release_notes"
        case builderAgentModel = "builder_agent_model"
        case builderPermissionMode = "builder_permission_mode"
        case researchPolicy = "research_policy"
        case promptBlocks = "prompt_blocks"
    }
}

enum NativeProjectServiceError: Error, LocalizedError {
    case invalidPayload(String)
    case promptNotFound(String)
    case unsupportedMethod(String)

    var errorDescription: String? {
        switch self {
        case .invalidPayload(let detail):
            return detail
        case .promptNotFound(let prompt):
            return "Prompt not found: \(prompt)"
        case .unsupportedMethod(let method):
            return "The native helper does not support \(method) yet."
        }
    }
}

final class NativeProjectService {
    static let supportedMethods: Set<PromptForgeServiceMethod> = [
        .health,
        .statusGet,
        .settingsGet,
        .settingsUpdate,
        .connectionsRefresh,
        .connectionsCodexDeviceAuth,
        .connectionsCodexLoginAPIKey,
        .projectOpen,
        .projectCreate,
        .promptsList,
        .promptsCreate,
        .promptsClone,
        .promptGet,
        .promptSave,
        .insightsLatest,
        .scenariosList,
        .reviewLatest,
        .builderActions,
        .decisionsList,
    ]

    private let lock = NSLock()
    private let fileManager = FileManager.default
    private let projectRoot: URL
    private let codexBinary: String
    private var metadata: NativeProjectMetadata
    private var connectionCache: [String: [String: Any]] = [:]

    init(projectRoot: String, codexBinary: String?) throws {
        self.projectRoot = URL(fileURLWithPath: projectRoot).standardizedFileURL
        self.codexBinary = codexBinary ?? ProcessInfo.processInfo.environment["PF_CODEX_BIN"] ?? "codex"
        self.metadata = NativeProjectMetadata(name: self.projectRoot.lastPathComponent.isEmpty ? "PromptForge Project" : self.projectRoot.lastPathComponent)
        try initializeProject()
    }

    func supports(_ method: PromptForgeServiceMethod) -> Bool {
        Self.supportedMethods.contains(method)
    }

    func handle(method: PromptForgeServiceMethod, params: [String: Any]) throws -> [String: Any] {
        try lock.withLock {
            try handleLocked(method: method, params: params)
        }
    }

    private var projectDirectory: URL {
        projectRoot.appendingPathComponent(nativeProjectDirectoryName, isDirectory: true)
    }

    private var metadataURL: URL {
        projectDirectory.appendingPathComponent(nativeProjectMetadataFileName)
    }

    private var promptDirectory: URL {
        projectRoot.appendingPathComponent(nativePromptDirectoryName, isDirectory: true)
    }

    private func initializeProject() throws {
        try ensureLayout()
        if fileManager.fileExists(atPath: metadataURL.path) {
            metadata = try loadMetadata()
        } else {
            try saveMetadata()
        }
    }

    private func ensureLayout() throws {
        try fileManager.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: promptDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: projectRoot.appendingPathComponent(nativeDatasetDirectoryName, isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: projectRoot.appendingPathComponent(nativeScenarioDirectoryName, isDirectory: true),
            withIntermediateDirectories: true
        )
        let varRoot = projectRoot.appendingPathComponent(nativeVarDirectoryName, isDirectory: true)
        try fileManager.createDirectory(at: varRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: varRoot.appendingPathComponent("state", isDirectory: true), withIntermediateDirectories: true)
    }

    private func loadMetadata() throws -> NativeProjectMetadata {
        let data = try Data(contentsOf: metadataURL)
        return try JSONDecoder().decode(NativeProjectMetadata.self, from: data)
    }

    private func saveMetadata() throws {
        metadata.updatedAt = nativeTimestamp()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(metadata)
        try data.write(to: metadataURL)
    }

    private func handleLocked(method: PromptForgeServiceMethod, params: [String: Any]) throws -> [String: Any] {
        switch method {
        case .health:
            return ["status": "ok", "project_root": projectRoot.path]
        case .statusGet:
            return try statusPayload()
        case .settingsGet:
            return settingsPayload()
        case .settingsUpdate:
            try updateSettings(params)
            return settingsPayload()
        case .connectionsRefresh:
            let requestedProviders = params["providers"] as? [String]
            return ["auth": authPayload(refresh: true, providers: requestedProviders)]
        case .connectionsCodexDeviceAuth:
            let result = CodexCLIAuthProbe.beginDeviceAuth(binary: codexBinary)
            return [
                "instructions": result.instructions,
                "verification_uri": result.verificationURI ?? NSNull(),
                "user_code": result.userCode ?? NSNull(),
                "auth": authPayload(refresh: true, providers: [ProviderID.codex.rawValue]),
            ]
        case .connectionsCodexLoginAPIKey:
            let apiKey = try requiredString("api_key", in: params)
            let result = CodexCLIAuthProbe.loginWithAPIKey(binary: codexBinary, apiKey: apiKey)
            return [
                "success": result.ready,
                "detail": result.detail,
                "auth": authPayload(refresh: true, providers: [ProviderID.codex.rawValue]),
            ]
        case .projectOpen:
            return projectPayload()
        case .projectCreate:
            if let name = params["name"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                metadata.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                try saveMetadata()
            }
            return projectPayload()
        case .promptsList:
            return ["prompts": try listPromptPayloads()]
        case .promptsCreate:
            let promptID = try requiredString("prompt", in: params)
            let displayName = stringValue("name", in: params)
            let fromPrompt = stringValue("from_prompt", in: params)
            let destination = try createPrompt(promptID: promptID, displayName: displayName, fromPrompt: fromPrompt)
            setActivePrompt(promptID)
            return ["created": destination.path, "prompt": promptID]
        case .promptsClone:
            let source = try requiredString("source", in: params)
            let target = try requiredString("name", in: params)
            let displayName = stringValue("display_name", in: params)
            let destination = try clonePrompt(sourcePrompt: source, targetPrompt: target, displayName: displayName)
            setActivePrompt(target)
            return ["created": destination.path, "prompt": target]
        case .promptGet:
            guard let promptID = try resolvePromptRef(params: params, allowMissing: false) else {
                throw NativeProjectServiceError.invalidPayload("Choose a prompt first.")
            }
            setActivePrompt(promptID)
            return ["prompt": try promptPayload(for: promptID)]
        case .promptSave:
            guard let promptID = try resolvePromptRef(params: params, allowMissing: false) else {
                throw NativeProjectServiceError.invalidPayload("Choose a prompt first.")
            }
            try savePrompt(promptID: promptID, params: params)
            setActivePrompt(promptID)
            return [
                "prompt": try promptPayload(for: promptID),
                "insights": emptyInsightsPayload(),
            ]
        case .insightsLatest:
            return ["insights": emptyInsightsPayload()]
        case .scenariosList:
            return ["suites": []]
        case .reviewLatest:
            return ["reviews": []]
        case .builderActions:
            return ["actions": []]
        case .decisionsList:
            return ["decisions": []]
        default:
            throw NativeProjectServiceError.unsupportedMethod(method.rawValue)
        }
    }

    private func projectPayload() -> [String: Any] {
        [
            "root": projectRoot.path,
            "metadata": dictionary(from: metadata),
        ]
    }

    private func statusPayload() throws -> [String: Any] {
        let promptID = try resolvePromptRef(params: [:], allowMissing: true)
        return [
            "project": projectPayload(),
            "active_prompt": promptID ?? NSNull(),
            "active_session": NSNull(),
            "auth": authPayload(refresh: false, providers: nil),
        ]
    }

    private func settingsPayload() -> [String: Any] {
        [
            "project": projectPayload(),
            "settings": [
                "name": metadata.name,
                "quick_benchmark_dataset": metadata.quickBenchmarkDataset,
                "full_evaluation_dataset": metadata.fullEvaluationDataset,
                "quick_benchmark_repeats": metadata.quickBenchmarkRepeats,
                "full_evaluation_repeats": metadata.fullEvaluationRepeats,
                "preferred_provider": metadata.preferredProvider,
                "preferred_judge_provider": metadata.preferredJudgeProvider ?? metadata.preferredProvider,
                "preferred_generation_model": metadata.preferredGenerationModel,
                "preferred_judge_model": metadata.preferredJudgeModel,
                "preferred_agent_model": metadata.preferredAgentModel,
                "builder_permission_mode": metadata.builderPermissionMode,
                "builder_research_policy": metadata.builderResearchPolicy,
            ],
            "auth": authPayload(refresh: false, providers: nil),
        ]
    }

    private func updateSettings(_ params: [String: Any]) throws {
        if let name = stringValue("name", in: params), !name.isEmpty {
            metadata.name = name
        }
        if let dataset = stringValue("quick_benchmark_dataset", in: params), !dataset.isEmpty {
            metadata.quickBenchmarkDataset = dataset
        }
        if let dataset = stringValue("full_evaluation_dataset", in: params), !dataset.isEmpty {
            metadata.fullEvaluationDataset = dataset
        }
        if let repeats = params["quick_benchmark_repeats"] as? Int {
            metadata.quickBenchmarkRepeats = max(1, repeats)
        }
        if let repeats = params["full_evaluation_repeats"] as? Int {
            metadata.fullEvaluationRepeats = max(1, repeats)
        }
        if let provider = stringValue("preferred_provider", in: params), !provider.isEmpty {
            metadata.preferredProvider = provider
        }
        if let judgeProvider = stringValue("preferred_judge_provider", in: params) {
            metadata.preferredJudgeProvider = judgeProvider.isEmpty ? metadata.preferredProvider : judgeProvider
        }
        if let model = stringValue("preferred_generation_model", in: params), !model.isEmpty {
            metadata.preferredGenerationModel = model
        }
        if let model = stringValue("preferred_judge_model", in: params), !model.isEmpty {
            metadata.preferredJudgeModel = model
        }
        if let model = stringValue("preferred_agent_model", in: params), !model.isEmpty {
            metadata.preferredAgentModel = model
        }
        if let mode = stringValue("builder_permission_mode", in: params), !mode.isEmpty {
            metadata.builderPermissionMode = mode
        }
        if let policy = stringValue("builder_research_policy", in: params), !policy.isEmpty {
            metadata.builderResearchPolicy = policy
        }
        try saveMetadata()
    }

    private func authPayload(refresh: Bool, providers: [String]?) -> [String: Any] {
        let connections = connectionPayload(refresh: refresh, providers: providers)
        let providerName = metadata.preferredProvider
        let judgeName = metadata.preferredJudgeProvider ?? providerName
        let provider = connections[providerName] ?? defaultConnectionStatus(for: providerName)
        let judge = connections[judgeName] ?? defaultConnectionStatus(for: judgeName)
        return [
            "provider": [
                "name": providerName,
                "ready": provider["ready"] as? Bool ?? false,
                "detail": provider["detail"] as? String ?? "",
            ],
            "judge": [
                "name": judgeName,
                "ready": judge["ready"] as? Bool ?? false,
                "detail": judge["detail"] as? String ?? "",
            ],
            "connections": connections,
        ]
    }

    private func connectionPayload(refresh: Bool, providers: [String]?) -> [String: [String: Any]] {
        let requested = Array(Set(providers ?? [ProviderID.openAI.rawValue, ProviderID.openRouter.rawValue, ProviderID.codex.rawValue])).sorted()
        if refresh {
            for provider in requested {
                connectionCache[provider] = probeConnectionStatus(for: provider)
            }
        }
        return requested.reduce(into: [String: [String: Any]]()) { result, provider in
            result[provider] = connectionCache[provider] ?? defaultConnectionStatus(for: provider)
        }
    }

    private func defaultConnectionStatus(for provider: String) -> [String: Any] {
        switch provider {
        case ProviderID.openAI.rawValue:
            let ready = KeychainSecretStore.has(key: "OPENAI_API_KEY")
            return [
                "name": provider,
                "ready": ready,
                "detail": ready ? "OPENAI_API_KEY is set" : "OPENAI_API_KEY is missing",
            ]
        case ProviderID.openRouter.rawValue:
            let ready = KeychainSecretStore.has(key: "OPENROUTER_API_KEY")
            return [
                "name": provider,
                "ready": ready,
                "detail": ready ? "OPENROUTER_API_KEY is set" : "OPENROUTER_API_KEY is missing",
            ]
        default:
            return [
                "name": provider,
                "ready": false,
                "detail": "Codex status not checked yet. Open Settings to refresh connections.",
                "source": codexBinary,
            ]
        }
    }

    private func probeConnectionStatus(for provider: String) -> [String: Any] {
        switch provider {
        case ProviderID.openAI.rawValue:
            return defaultConnectionStatus(for: provider)
        case ProviderID.openRouter.rawValue:
            return defaultConnectionStatus(for: provider)
        default:
            let status = CodexCLIAuthProbe.loginStatus(binary: codexBinary)
            return [
                "name": provider,
                "ready": status.ready,
                "detail": status.detail,
                "source": status.source,
            ]
        }
    }

    private func listPromptPayloads() throws -> [[String: Any]] {
        let children = try fileManager.contentsOfDirectory(
            at: promptDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        return children
            .filter { url in
                ((try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false) == true
            }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            .compactMap { url in
                guard let manifest = try? loadManifest(at: url) else {
                    return nil
                }
                return [
                    "version": manifest.version,
                    "name": manifest.name,
                    "description": manifest.description,
                    "root": url.path,
                    "session_id": NSNull(),
                ]
            }
    }

    private func createPrompt(promptID: String, displayName: String?, fromPrompt: String?) throws -> URL {
        let destination = promptDirectory.appendingPathComponent(promptID, isDirectory: true)
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw NativeProjectServiceError.invalidPayload("Prompt already exists: \(promptID)")
        }

        if let fromPrompt, !fromPrompt.isEmpty {
            let sourceRoot = try promptURL(for: fromPrompt)
            try fileManager.copyItem(at: sourceRoot, to: destination)
            let manifestURL = destination.appendingPathComponent("manifest.yaml")
            let existingManifest = (try? String(contentsOf: manifestURL, encoding: .utf8)) ?? ""
            let updatedManifest = rewriteManifest(existingManifest, version: promptID, name: displayName ?? defaultPromptName(for: promptID))
            try updatedManifest.write(to: manifestURL, atomically: true, encoding: .utf8)
            let parsedManifest = try loadManifest(at: destination)
            try ensurePromptBrief(at: destination, description: parsedManifest.description)
            return destination
        }

        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        let manifest = """
        apiVersion: 1
        version: \(promptID)
        name: \(yamlScalar(displayName ?? defaultPromptName(for: promptID)))
        description: "New prompt created from the app workspace."
        output_format: markdown
        required_sections: []
        """
        try manifest.appending("\n").write(to: destination.appendingPathComponent("manifest.yaml"), atomically: true, encoding: .utf8)
        try """
        You are a focused assistant.

        Follow the user's request exactly, keep the answer concise, and do not invent facts.
        """.appending("\n").write(to: destination.appendingPathComponent("system.md"), atomically: true, encoding: .utf8)
        try """
        Use the provided input payload to answer the request.

        {{ input | tojson(indent=2) if input is mapping else input }}
        """.appending("\n").write(to: destination.appendingPathComponent("user_template.md"), atomically: true, encoding: .utf8)
        try """
        {
          "type": "object",
          "additionalProperties": true
        }
        """.appending("\n").write(to: destination.appendingPathComponent("variables.schema.json"), atomically: true, encoding: .utf8)

        let brief = NativePromptBrief(
            purpose: "What this prompt is for in \(displayName ?? promptID).",
            expectedBehavior: "Describe the behavior, tone, and output shape you expect from the prompt.",
            successCriteria: "Describe what a good answer must include and what should be avoided."
        )
        try savePromptBrief(brief, at: destination)
        return destination
    }

    private func clonePrompt(sourcePrompt: String, targetPrompt: String, displayName: String?) throws -> URL {
        try createPrompt(promptID: targetPrompt, displayName: displayName, fromPrompt: sourcePrompt)
    }

    private func savePrompt(promptID: String, params: [String: Any]) throws {
        let promptRoot = try promptURL(for: promptID)
        let systemPrompt = try requiredString("system_prompt", in: params)
        let userTemplate = try requiredString("user_template", in: params)
        try systemPrompt.appending("\n").write(to: promptRoot.appendingPathComponent("system.md"), atomically: true, encoding: .utf8)
        try userTemplate.appending("\n").write(to: promptRoot.appendingPathComponent("user_template.md"), atomically: true, encoding: .utf8)

        let promptBlockPayloads: [[String: Any]] = params["prompt_blocks"] as? [[String: Any]] ?? []
        let promptBlocks = promptBlockPayloads.compactMap { payload -> NativePromptBlock? in
            guard
                let blockID = payload["block_id"] as? String,
                let title = payload["title"] as? String,
                let body = payload["body"] as? String
            else {
                return nil
            }
            return NativePromptBlock(
                blockID: blockID,
                title: title,
                body: body,
                target: payload["target"] as? String ?? "system",
                enabled: payload["enabled"] as? Bool ?? true
            )
        }

        let brief = NativePromptBrief(
            purpose: stringValue("purpose", in: params) ?? "",
            expectedBehavior: stringValue("expected_behavior", in: params) ?? "",
            successCriteria: stringValue("success_criteria", in: params) ?? "",
            baselinePromptRef: stringValue("baseline_prompt_ref", in: params) ?? "",
            primaryScenarioSuites: params["primary_scenario_suites"] as? [String] ?? [],
            owner: stringValue("owner", in: params) ?? "",
            audience: stringValue("audience", in: params) ?? "",
            releaseNotes: stringValue("release_notes", in: params) ?? "",
            builderAgentModel: stringValue("builder_agent_model", in: params) ?? metadata.preferredAgentModel,
            builderPermissionMode: stringValue("builder_permission_mode", in: params) ?? metadata.builderPermissionMode,
            researchPolicy: stringValue("research_policy", in: params) ?? metadata.builderResearchPolicy,
            promptBlocks: promptBlocks
        )
        try savePromptBrief(brief, at: promptRoot)
    }

    private func promptPayload(for promptID: String) throws -> [String: Any] {
        let promptRoot = try promptURL(for: promptID)
        let manifest = try loadManifest(at: promptRoot)
        let brief = try loadPromptBrief(at: promptRoot, description: manifest.description)
        let systemPrompt = ((try? String(contentsOf: promptRoot.appendingPathComponent("system.md"), encoding: .utf8)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let userTemplate = ((try? String(contentsOf: promptRoot.appendingPathComponent("user_template.md"), encoding: .utf8)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return [
            "version": manifest.version,
            "name": manifest.name,
            "description": manifest.description,
            "root": promptRoot.path,
            "system_prompt": systemPrompt,
            "user_template": userTemplate,
            "purpose": brief.purpose,
            "expected_behavior": brief.expectedBehavior,
            "success_criteria": brief.successCriteria,
            "baseline_prompt_ref": brief.baselinePromptRef,
            "primary_scenario_suites": brief.primaryScenarioSuites,
            "owner": brief.owner,
            "audience": brief.audience,
            "release_notes": brief.releaseNotes,
            "builder_agent_model": brief.builderAgentModel,
            "builder_permission_mode": brief.builderPermissionMode,
            "research_policy": brief.researchPolicy,
            "prompt_blocks": brief.promptBlocks.map { dictionary(from: $0) },
            "files": promptFiles(at: promptRoot),
            "session_id": NSNull(),
        ]
    }

    private func promptFiles(at promptRoot: URL) -> [String] {
        let preferredOrder = ["prompt.json", "system.md", "user_template.md", "manifest.yaml", "variables.schema.json"]
        var files = preferredOrder.filter { fileManager.fileExists(atPath: promptRoot.appendingPathComponent($0).path) }
        let additional = ((try? fileManager.contentsOfDirectory(at: promptRoot, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])) ?? [])
            .filter { ((try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false) == true }
            .map(\.lastPathComponent)
            .filter { !files.contains($0) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        files.append(contentsOf: additional)
        return files
    }

    private func resolvePromptRef(params: [String: Any], allowMissing: Bool) throws -> String? {
        let prompts = try listPromptPayloads()
        let promptIDs = prompts.compactMap { $0["version"] as? String }
        if promptIDs.isEmpty {
            if allowMissing {
                return nil
            }
            throw NativeProjectServiceError.invalidPayload("No prompts are available in this project.")
        }

        if let explicit = stringValue("prompt", in: params) {
            guard promptIDs.contains(explicit) else {
                throw NativeProjectServiceError.promptNotFound(explicit)
            }
            return explicit
        }

        if let lastOpened = metadata.lastOpenedPrompt, promptIDs.contains(lastOpened) {
            return lastOpened
        }

        let fallback = promptIDs[0]
        if metadata.lastOpenedPrompt != fallback {
            setActivePrompt(fallback)
        }
        return fallback
    }

    private func promptURL(for promptID: String) throws -> URL {
        let url = promptDirectory.appendingPathComponent(promptID, isDirectory: true)
        guard fileManager.fileExists(atPath: url.path) else {
            throw NativeProjectServiceError.promptNotFound(promptID)
        }
        return url
    }

    private func setActivePrompt(_ promptID: String) {
        metadata.lastOpenedPrompt = promptID
        try? saveMetadata()
    }

    private func loadManifest(at promptRoot: URL) throws -> NativePromptManifest {
        let manifestURL = promptRoot.appendingPathComponent("manifest.yaml")
        let contents = try String(contentsOf: manifestURL, encoding: .utf8)
        let values = parseManifestValues(contents)
        let version = values["version"] ?? promptRoot.lastPathComponent
        let name = values["name"] ?? defaultPromptName(for: version)
        let description = values["description"] ?? ""
        return NativePromptManifest(version: version, name: name, description: description)
    }

    private func loadPromptBrief(at promptRoot: URL, description: String) throws -> NativePromptBrief {
        let briefURL = promptRoot.appendingPathComponent("prompt.json")
        guard fileManager.fileExists(atPath: briefURL.path) else {
            let brief = NativePromptBrief(purpose: description)
            try savePromptBrief(brief, at: promptRoot)
            return brief
        }
        let data = try Data(contentsOf: briefURL)
        return try JSONDecoder().decode(NativePromptBrief.self, from: data)
    }

    private func ensurePromptBrief(at promptRoot: URL, description: String) throws {
        _ = try loadPromptBrief(at: promptRoot, description: description)
    }

    private func savePromptBrief(_ brief: NativePromptBrief, at promptRoot: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(brief)
        let briefURL = promptRoot.appendingPathComponent("prompt.json")
        if let json = String(data: data, encoding: .utf8) {
            try json.appending("\n").write(to: briefURL, atomically: true, encoding: .utf8)
        } else {
            try data.write(to: briefURL)
        }
    }

    private func requiredString(_ key: String, in params: [String: Any]) throws -> String {
        guard let value = stringValue(key, in: params), !value.isEmpty else {
            throw NativeProjectServiceError.invalidPayload("Missing \(key).")
        }
        return value
    }

    private func stringValue(_ key: String, in params: [String: Any]) -> String? {
        guard let value = params[key] else {
            return nil
        }
        if value is NSNull {
            return nil
        }
        let string = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
        return string.isEmpty ? nil : string
    }

    private func emptyInsightsPayload() -> [String: Any] {
        [
            "session_id": NSNull(),
            "latest_revision_id": NSNull(),
            "status_rows": [],
            "diff_rows": [],
            "weak_cases": [],
            "failures": [],
            "pending_edits": [],
            "builder_actions": [],
            "reviews": [],
            "decisions": [],
        ]
    }
}

private enum CodexCLIAuthProbe {
    struct Status {
        let ready: Bool
        let detail: String
        let source: String
    }

    struct DeviceAuthResult {
        let verificationURI: String?
        let userCode: String?
        let instructions: String
    }

    static func loginStatus(binary: String) -> Status {
        guard let resolved = resolve(binary: binary) else {
            return Status(ready: false, detail: "Codex CLI not found: \(binary)", source: binary)
        }

        do {
            let result = try run(binary: resolved, arguments: ["login", "status"])
            return Status(
                ready: result.terminationStatus == 0,
                detail: result.output.isEmpty ? "Codex CLI found at \(resolved)" : result.output,
                source: resolved
            )
        } catch {
            return Status(ready: false, detail: "Codex status unavailable: \(error.localizedDescription)", source: resolved)
        }
    }

    static func loginWithAPIKey(binary: String, apiKey: String) -> Status {
        guard let resolved = resolve(binary: binary) else {
            return Status(ready: false, detail: "Codex CLI not found: \(binary)", source: binary)
        }
        let normalizedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedKey.isEmpty else {
            return Status(ready: false, detail: "OpenAI API key is required for Codex API-key login.", source: resolved)
        }

        do {
            let result = try run(
                binary: resolved,
                arguments: ["login", "--with-api-key"],
                stdin: normalizedKey + "\n"
            )
            if result.terminationStatus != 0 {
                return Status(
                    ready: false,
                    detail: result.output.isEmpty ? "Codex login failed." : result.output,
                    source: resolved
                )
            }
            return loginStatus(binary: resolved)
        } catch {
            return Status(ready: false, detail: "Codex login failed: \(error.localizedDescription)", source: resolved)
        }
    }

    static func beginDeviceAuth(binary: String) -> DeviceAuthResult {
        guard let resolved = resolve(binary: binary) else {
            return DeviceAuthResult(
                verificationURI: nil,
                userCode: nil,
                instructions: "Codex CLI not found: \(binary)"
            )
        }

        do {
            let result = try run(binary: resolved, arguments: ["login", "--device-auth"])
            guard result.terminationStatus == 0 else {
                return DeviceAuthResult(
                    verificationURI: nil,
                    userCode: nil,
                    instructions: result.output.isEmpty ? "Codex device auth failed." : result.output
                )
            }

            let verificationURI = firstMatch(in: result.output, pattern: #"https?://\S+"#)
            let userCode = firstMatch(in: result.output, pattern: #"\b([A-Z0-9]{4,}(?:-[A-Z0-9]{4,})+)\b"#, captureGroup: 1)
            if let verificationURI, let userCode {
                return DeviceAuthResult(
                    verificationURI: verificationURI,
                    userCode: userCode,
                    instructions: "Open \(verificationURI) and enter code \(userCode)."
                )
            }

            return DeviceAuthResult(
                verificationURI: verificationURI,
                userCode: userCode,
                instructions: result.output.isEmpty ? "Codex device auth started." : result.output
            )
        } catch {
            return DeviceAuthResult(
                verificationURI: nil,
                userCode: nil,
                instructions: "Could not start Codex device auth: \(error.localizedDescription)"
            )
        }
    }

    private static func resolve(binary: String) -> String? {
        let expanded = NSString(string: binary).expandingTildeInPath
        if expanded.contains("/") {
            return FileManager.default.isExecutableFile(atPath: expanded) ? URL(fileURLWithPath: expanded).standardizedFileURL.path : nil
        }

        let pathEntries = (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
            .split(separator: ":")
            .map(String.init)
        for entry in pathEntries {
            let candidate = URL(fileURLWithPath: entry).appendingPathComponent(expanded).path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func run(binary: String, arguments: [String], stdin: String? = nil) throws -> (terminationStatus: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        if let stdin {
            let inputPipe = Pipe()
            process.standardInput = inputPipe
            try process.run()
            if let data = stdin.data(using: .utf8) {
                inputPipe.fileHandleForWriting.write(data)
            }
            try? inputPipe.fileHandleForWriting.close()
        } else {
            try process.run()
        }

        process.waitUntilExit()
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return (process.terminationStatus, output)
    }

    private static func firstMatch(in text: String, pattern: String, captureGroup: Int = 0) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), captureGroup < match.numberOfRanges else {
            return nil
        }
        let matchRange = match.range(at: captureGroup)
        guard let range = Range(matchRange, in: text) else {
            return nil
        }
        return String(text[range])
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

private func nativeTimestamp() -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: Date())
}

private func dictionary<T: Encodable>(from value: T) -> [String: Any] {
    let encoder = JSONEncoder()
    guard
        let data = try? encoder.encode(value),
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
        return [:]
    }
    return object
}

private func parseManifestValues(_ contents: String) -> [String: String] {
    var values: [String: String] = [:]
    for rawLine in contents.components(separatedBy: .newlines) {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix("-") else {
            continue
        }
        guard let separator = line.firstIndex(of: ":") else {
            continue
        }
        let key = line[..<separator].trimmingCharacters(in: .whitespaces)
        let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
        values[key] = unquoteYAMLScalar(String(value))
    }
    return values
}

private func rewriteManifest(_ contents: String, version: String, name: String) -> String {
    var sawVersion = false
    var sawName = false
    let lines = contents.components(separatedBy: .newlines).map { rawLine -> String in
        let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("version:") {
            sawVersion = true
            return "version: \(version)"
        }
        if trimmed.hasPrefix("name:") {
            sawName = true
            return "name: \(yamlScalar(name))"
        }
        return rawLine
    }

    var rewritten = lines
    if !sawVersion {
        rewritten.append("version: \(version)")
    }
    if !sawName {
        rewritten.append("name: \(yamlScalar(name))")
    }
    return rewritten.joined(separator: "\n").trimmingCharacters(in: .newlines) + "\n"
}

private func defaultPromptName(for version: String) -> String {
    let parts = version
        .replacingOccurrences(of: "_", with: "-")
        .split(separator: "-")
        .map(String.init)
        .filter { !$0.isEmpty }
    if parts.isEmpty {
        return "Prompt"
    }
    return parts.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
}

private func yamlScalar(_ value: String) -> String {
    if value.rangeOfCharacter(from: CharacterSet(charactersIn: ":\n#\"")) != nil {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
    return value
}

private func unquoteYAMLScalar(_ value: String) -> String {
    guard value.count >= 2 else {
        return value
    }
    if (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
        return String(value.dropFirst().dropLast())
    }
    return value
}
