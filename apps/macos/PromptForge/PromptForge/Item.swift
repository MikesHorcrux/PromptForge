import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class PromptForgeAppModel: ObservableObject {
    @Published var projectPath: String?
    @Published var projectName: String = "PromptForge"
    @Published var draftMessage: String = ""
    @Published var prompts: [PromptSummaryModel] = []
    @Published var selectedPrompt: String?
    @Published var selectedSuiteID: String?
    @Published var selectedScenarioCaseID: String?
    @Published var selectedReviewID: String?
    @Published var selectedReviewCaseID: String?
    @Published var selectedWorkspaceMode: PromptWorkspaceMode = .studio
    @Published var currentPromptName: String = ""
    @Published var currentPromptDescription: String = ""
    @Published var promptRootPath: String = ""
    @Published var systemPrompt: String = ""
    @Published var userTemplate: String = ""
    @Published var promptDraft: PromptWorkspaceDraft = .init()
    @Published var promptFiles: [String] = []
    @Published var transcript: [TranscriptEntry] = []
    @Published var benchmarkRows: [(String, String)] = []
    @Published var weakCases: [CaseIssue] = []
    @Published var failureCases: [CaseIssue] = []
    @Published var pendingProposal: PreparedProposal?
    @Published var providerLine: String = "provider --"
    @Published var authLine: String = "auth unknown"
    @Published var sessionLine: String = "session --"
    @Published var latestScoreLine: String = "--"
    @Published var isBusy: Bool = false
    @Published var busyLabel: String = ""
    @Published var launchError: String?
    @Published var showSettings: Bool = false
    @Published var showCommandBar: Bool = false
    @Published var settingsMode: String = "settings"
    @Published var settingsDraft: AppSettingsDraft = .init()
    @Published var openAIKeyDraft: String = ""
    @Published var openRouterKeyDraft: String = ""
    @Published var settingsNotice: String?
    @Published var settingsError: String?
    @Published var connectionStatuses: [ProviderConnectionStatus] = []
    @Published var promptSaveNotice: String?
    @Published var scenarioSuites: [ScenarioSuiteModel] = []
    @Published var scenarioDraft: ScenarioSuiteModel?
    @Published var builderActions: [BuilderActionModel] = []
    @Published var reviews: [ReviewSummaryModel] = []
    @Published var decisions: [DecisionRecordModel] = []
    @Published var latestPlaygroundRun: PlaygroundRunModel?
    @Published var playgroundInputJSON: String = "{\n  \"customer_name\": \"Avery\",\n  \"customer_issue\": \"Wants a refund for an unopened grinder purchased 18 days ago.\",\n  \"goal\": \"Confirm eligibility and explain the next step.\",\n  \"tone\": \"warm and clear\",\n  \"policy_snippet\": \"Refunds are available within 30 days for unused items with proof of purchase.\"\n}"
    @Published var playgroundContext: String = ""
    @Published var playgroundSampleCount: Int = 1
    @Published var scenarioNotice: String?

    private var helper: (any PromptForgeAgentTransport)?
    private var engineRoot: String?
    private var eventTask: Task<Void, Never>?
    private var eventCursor: Int = 0
    private var projectScopeURL: URL?
    private var savedPromptDraft: PromptWorkspaceDraft = .init()

    init(initialProjectPath: String?, initialEngineRoot: String?) {
        self.engineRoot = initialEngineRoot ?? UserDefaults.standard.string(forKey: "PromptForgeEngineRoot")
        self.projectPath = nil
        if let initialProjectPath {
            Task {
                await openProject(at: initialProjectPath, engineRoot: initialEngineRoot)
            }
        } else if let bookmarkedProject = SecurityScopedProjectStore.resolve() {
            Task {
                await openProject(url: bookmarkedProject, engineRoot: initialEngineRoot ?? self.engineRoot)
            }
        }
    }

    var savedProjectHint: String? {
        SecurityScopedProjectStore.savedPath()
    }

    var isOnboarding: Bool {
        settingsMode == "onboarding"
    }

    var promptHasUnsavedChanges: Bool {
        promptDraft != savedPromptDraft
    }

    var promptDiffPreview: String {
        var sections: [String] = []
        let draftBlocks = promptDraft.promptBlocks.map { "\($0.title) [\($0.target)]\n\($0.body)" }.joined(separator: "\n\n")
        let savedBlocks = savedPromptDraft.promptBlocks.map { "\($0.title) [\($0.target)]\n\($0.body)" }.joined(separator: "\n\n")
        sections.append(diffSection(title: "Purpose", before: savedPromptDraft.purpose, after: promptDraft.purpose))
        sections.append(diffSection(title: "Expected Behavior", before: savedPromptDraft.expectedBehavior, after: promptDraft.expectedBehavior))
        sections.append(diffSection(title: "Success Criteria", before: savedPromptDraft.successCriteria, after: promptDraft.successCriteria))
        sections.append(diffSection(title: "Prompt Blocks", before: savedBlocks, after: draftBlocks))
        sections.append(diffSection(title: "System Prompt", before: savedPromptDraft.systemPrompt, after: promptDraft.systemPrompt))
        sections.append(diffSection(title: "User Template", before: savedPromptDraft.userTemplate, after: promptDraft.userTemplate))
        return sections.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    var effectiveBuilderTools: [String] {
        var tools = ["Chat", "Prompt Files", "Diffs", "Playground", "Scenario Runs"]
        if promptDraft.researchPolicy.lowercased().contains("allow") || promptDraft.researchPolicy.lowercased().contains("external") {
            tools.append("External Research")
        }
        if promptDraft.builderPermissionMode.lowercased().contains("auto") {
            tools.append("Direct Apply")
        } else {
            tools.append("Proposal Apply")
        }
        return tools
    }

    var selectedPromptSummary: PromptSummaryModel? {
        guard let selectedPrompt else { return nil }
        return prompts.first(where: { $0.version == selectedPrompt })
    }

    var recentTranscript: [TranscriptEntry] {
        Array(transcript.suffix(4))
    }

    var shouldAutoApplyEdits: Bool {
        promptDraft.builderPermissionMode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "auto_apply"
    }

    var selectedSuite: ScenarioSuiteModel? {
        guard let selectedSuiteID else { return scenarioSuites.first }
        return scenarioSuites.first(where: { $0.suiteID == selectedSuiteID }) ?? scenarioSuites.first
    }

    var activeScenarioSuite: ScenarioSuiteModel? {
        scenarioDraft ?? selectedSuite
    }

    var selectedScenarioCase: ScenarioCaseModel? {
        guard let suite = activeScenarioSuite else { return nil }
        guard let selectedScenarioCaseID else { return suite.cases.first }
        return suite.cases.first(where: { $0.caseID == selectedScenarioCaseID }) ?? suite.cases.first
    }

    var latestReview: ReviewSummaryModel? {
        if let selectedReviewID {
            return reviews.first(where: { $0.reviewID == selectedReviewID }) ?? reviews.last
        }
        return reviews.last
    }

    var selectedReviewCase: ReviewCaseModel? {
        guard let review = latestReview else { return nil }
        guard let selectedReviewCaseID else { return review.cases.first }
        return review.cases.first(where: { $0.caseID == selectedReviewCaseID }) ?? review.cases.first
    }

    private func withBusyState<T>(_ label: String, operation: () async throws -> T) async rethrows -> T {
        isBusy = true
        busyLabel = label
        defer {
            isBusy = false
            busyLabel = ""
        }
        return try await operation()
    }

    func chooseProjectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                await openProject(url: url)
            }
        }
    }

    private func beginProjectScope(for url: URL) -> Bool {
        projectScopeURL?.stopAccessingSecurityScopedResource()
        projectScopeURL = nil
        guard url.startAccessingSecurityScopedResource() else {
            return false
        }
        projectScopeURL = url
        return true
    }

    private func resolveEngineRoot(projectURL: URL, explicitEngineRoot: String?) -> EngineRuntimeSelection? {
        EngineRuntimeLocator.resolve(
            projectURL: projectURL,
            explicitEngineRoot: explicitEngineRoot,
            savedEngineRoot: engineRoot
        )
    }

    func createPromptShortcut() {
        guard let creation = promptCreationRequest() else {
            return
        }
        Task {
            await createPrompt(creation.version, displayName: creation.displayName, fromPrompt: nil)
        }
    }

    func importPrompt() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a prompt folder to import."
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                await importPrompt(from: url)
            }
        }
    }

    private func importPrompt(from url: URL) async {
        guard let helper else {
            appendTranscript(.warning, "Import prompt", "Open a project before importing a prompt.")
            return
        }
        do {
            try await withBusyState("Importing prompt") {
                let result = try await helper.send(
                    method: "prompts.import",
                    params: ["source_path": url.path]
                )
                try await refreshPrompts()
                if let prompt = result["prompt"] as? String {
                    await openPrompt(prompt, announce: true)
                }
            }
        } catch {
            appendTranscript(.warning, "Import prompt", error.localizedDescription)
        }
    }

    func createScenarioShortcut() {
        Task {
            guard let helper, let prompt = selectedPrompt else { return }
            do {
                try await withBusyState("Creating test suite") {
                    let suiteID = "suite-\(Int(Date().timeIntervalSince1970))"
                    _ = try await helper.send(
                        method: "scenarios.create",
                        params: [
                            "prompt": prompt,
                            "suite_id": suiteID,
                            "name": "New Test Suite",
                            "description": "New test suite created from the app.",
                        ]
                    )
                    try await refreshScenarioSuites()
                    selectSuite(suiteID)
                    selectedWorkspaceMode = .tests
                }
            } catch {
                appendTranscript(.warning, "Tests", error.localizedDescription)
            }
        }
    }

    func openCommandBar() {
        showCommandBar = true
    }

    func closeCommandBar() {
        showCommandBar = false
    }

    func savePromptWorkspace() {
        Task {
            _ = await persistPromptWorkspace()
        }
    }

    func runQuickBenchmark() {
        Task {
            await runHelperMethod(PromptForgeServiceMethod.benchRunQuick.rawValue)
        }
    }

    func submitDraft() {
        let text = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draftMessage = ""
        submitText(text)
    }

    func submitText(_ text: String) {
        Task {
            await handleInput(text)
        }
    }

    func openSettings(onboarding: Bool = false) {
        Task {
            await loadSettings(openingMode: onboarding ? "onboarding" : "settings")
        }
    }

    func openProject(at path: String, engineRoot: String? = nil) async {
        await openProject(url: URL(fileURLWithPath: path), engineRoot: engineRoot)
    }

    func openProject(url: URL, engineRoot: String? = nil) async {
        isBusy = true
        busyLabel = "Opening project"
        launchError = nil
        pendingProposal = nil
        promptSaveNotice = nil
        eventTask?.cancel()
        eventTask = nil
        eventCursor = 0
        helper?.shutdown()
        resetPromptWorkspaceState()
        let path = url.path
        guard beginProjectScope(for: url) else {
            launchError = "PromptForge needs folder access to open this project. Choose the project folder again to re-grant access."
            isBusy = false
            busyLabel = ""
            return
        }
        SecurityScopedProjectStore.save(url: url)
        let resolvedEngineRuntime = resolveEngineRoot(projectURL: url, explicitEngineRoot: engineRoot)
        if resolvedEngineRuntime == nil && !EngineRuntimeLocator.allowsDevelopmentRuntimeFallback {
            let detail = EngineRuntimeLocator.missingRuntimeMessage
            launchError = detail
            appendTranscript(.warning, "Runtime", detail)
            isBusy = false
            busyLabel = ""
            return
        }
        do {
            helper = try PromptForgeTransportFactory.makeTransport(
                projectRoot: path,
                runtimeSelection: resolvedEngineRuntime
            )
            self.engineRoot = resolvedEngineRuntime?.rootPath
            UserDefaults.standard.set(path, forKey: "PromptForgeProjectPath")
            if let resolvedEngineRuntime {
                UserDefaults.standard.set(resolvedEngineRuntime.rootPath, forKey: "PromptForgeEngineRoot")
            }
            projectPath = path
            selectedWorkspaceMode = .studio
            transcript.removeAll()
            appendTranscript(.system, "Project", "Opened \(path)")
            appendTranscript(.system, "Runtime", "Using \(helper?.backend.displayName ?? "local helper").")
            if resolvedEngineRuntime == nil {
                appendTranscript(
                    .warning,
                    "Runtime",
                    "Bundled engine not found. Project, settings, and prompt editing run natively; evals and agent actions still require the packaged engine."
                )
            }
            _ = try await helper?.send(method: "project.open") ?? [:]
            startEventStream()
            try await refreshStatus()
            try await refreshPrompts()
            if let prompt = selectedPrompt ?? prompts.first?.version {
                await openPrompt(prompt, announce: false)
            } else {
                appendTranscript(.system, "Project", "No prompts found. Create or import a prompt to get started.")
            }
            if !UserDefaults.standard.bool(forKey: "PromptForgeCompletedOnboarding") {
                await loadSettings(openingMode: "onboarding")
            }
        } catch {
            helper?.shutdown()
            helper = nil
            projectPath = nil
            launchError = error.localizedDescription
            appendTranscript(.warning, "Launch error", error.localizedDescription)
        }
        isBusy = false
        busyLabel = ""
    }

    func saveSettings() {
        Task {
            await persistSettings()
        }
    }

    func authenticateCodexWithOpenAIKey() {
        Task {
            await runCodexAPIKeyLogin()
        }
    }

    func beginCodexDeviceAuth() {
        Task {
            await runCodexDeviceAuth()
        }
    }

    private func runCodexAPIKeyLogin() async {
        guard let helper else {
            settingsError = "Open a project before signing into Codex."
            return
        }
        settingsError = nil
        settingsNotice = nil
        isBusy = true
        defer { isBusy = false }

        let draftKey = openAIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedKey = draftKey.isEmpty ? (KeychainSecretStore.read(key: "OPENAI_API_KEY") ?? "") : draftKey
        let apiKey = resolvedKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            settingsError = "Add an OpenAI API key first, then retry Codex sign-in."
            return
        }
        if !draftKey.isEmpty {
            _ = KeychainSecretStore.write(key: "OPENAI_API_KEY", value: apiKey)
            openAIKeyDraft = ""
        }

        do {
            let payload = try await helper.send(
                method: "connections.codex.login_api_key",
                params: ["api_key": apiKey]
            )
            if let authPayload = payload["auth"] as? [String: Any] {
                applyConnectionPayload(authPayload)
            }
            let success = payload["success"] as? Bool ?? false
            let detail = payload["detail"] as? String ?? "Codex login finished."
            if success {
                settingsNotice = detail
            } else {
                settingsError = detail
            }
        } catch {
            settingsError = error.localizedDescription
        }
    }

    private func runCodexDeviceAuth() async {
        guard let helper else {
            settingsError = "Open a project before signing into Codex."
            return
        }
        settingsError = nil
        settingsNotice = nil
        isBusy = true
        defer { isBusy = false }

        do {
            let payload = try await helper.send(method: "connections.codex.device_auth")
            if let authPayload = payload["auth"] as? [String: Any] {
                applyConnectionPayload(authPayload)
            }
            let verificationURI = payload["verification_uri"] as? String
            let userCode = payload["user_code"] as? String
            let instructions = payload["instructions"] as? String ?? "Codex device sign-in started."

            if let verificationURI, let url = URL(string: verificationURI) {
                _ = NSWorkspace.shared.open(url)
            }

            if let verificationURI, let userCode {
                settingsNotice = "Open \(verificationURI) and enter code \(userCode). Refresh status after you finish sign-in."
            } else {
                settingsNotice = instructions
            }
        } catch {
            settingsError = error.localizedDescription
        }
    }

    func clearKey(kind: String) {
        switch kind {
        case "openai":
            _ = KeychainSecretStore.delete(key: "OPENAI_API_KEY")
            openAIKeyDraft = ""
        case "openrouter":
            _ = KeychainSecretStore.delete(key: "OPENROUTER_API_KEY")
            openRouterKeyDraft = ""
        default:
            break
        }
        refreshLocalConnectionStatuses()
    }

    func openPrompt(_ prompt: String, announce: Bool) async {
        guard let helper else { return }
        do {
            try await withBusyState("Opening prompt") {
                let promptResult = try await helper.send(method: "prompt.get", params: ["prompt": prompt])
                applyPromptPayload(promptResult)
                let insightResult = try await helper.send(method: "insights.latest", params: ["prompt": prompt])
                applyInsightsPayload(insightResult)
                try await refreshScenarioSuites()
                try await refreshReviews()
                try await refreshBuilderActions()
                try await refreshDecisions()
                try await refreshStatus()
                scenarioNotice = nil
                if announce {
                    appendTranscript(.system, "Prompt", "Opened prompt \(prompt)")
                }
            }
        } catch {
            appendTranscript(.warning, "Prompt", error.localizedDescription)
        }
    }

    private func handleInput(_ rawText: String) async {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        appendTranscript(.user, "You", text)
        if text.hasPrefix("/") {
            await handleSlashCommand(text)
            return
        }
        await agentChat(text)
    }

    private func agentChat(_ request: String) async {
        guard let prompt = selectedPrompt, let helper else {
            appendTranscript(.warning, "Agent", "Choose a project and a prompt first.")
            return
        }
        guard await persistPromptWorkspace(showNoChangeNotice: false) else {
            return
        }
        do {
            try await withBusyState("Asking agent") {
                let result = try await helper.send(
                    method: "agent.chat",
                    params: ["prompt": prompt, "request": request]
                )
                let chatPayload = result["chat"] as? [String: Any] ?? [:]
                let message = chatPayload["message"] as? String ?? ""

                if let proposal = proposalFromResult(result) {
                    if shouldAutoApplyEdits {
                        let summary = proposal.summary.isEmpty ? message : proposal.summary
                        appendTranscript(.agent, "Applying edit", summary)
                        try await autoApplyProposal(proposal, prompt: prompt)
                    } else {
                        pendingProposal = proposal
                        let changedFiles = proposal.changedFiles.isEmpty ? "No file changes." : "Files: \(proposal.changedFiles.joined(separator: ", "))"
                        let summary = proposal.summary.isEmpty ? message : proposal.summary
                        appendTranscript(.agent, "Proposal \(proposal.proposalID)", "\(summary)\n\n\(changedFiles)")
                        if !proposal.diffPreview.isEmpty {
                            appendTranscript(.result, "Diff preview", proposal.diffPreview)
                        }
                    }
                } else if !message.isEmpty {
                    appendTranscript(.agent, "Agent", message)
                } else {
                    throw HelperClientError.missingField("The helper did not return a message.")
                }

                if result["revision"] != nil || result["insights"] != nil {
                    applyResultPayload(result)
                }
            }
        } catch {
            appendTranscript(.warning, "Chat failed", error.localizedDescription)
        }
    }

    private func coachPrompt(_ request: String) async {
        guard let prompt = selectedPrompt, let helper else {
            appendTranscript(.warning, "Agent", "Choose a project and a prompt first.")
            return
        }
        guard await persistPromptWorkspace(showNoChangeNotice: false) else {
            return
        }
        do {
            try await withBusyState("Generating guidance") {
                let result = try await helper.send(
                    method: "coach.reply",
                    params: ["prompt": prompt, "request": request]
                )
                guard let reply = result["reply"] as? String, !reply.isEmpty else {
                    throw HelperClientError.missingField("The helper did not return a reply.")
                }
                appendTranscript(.agent, "Coach", reply)
            }
        } catch {
            appendTranscript(.warning, "Chat failed", error.localizedDescription)
        }
    }

    private func prepareEditProposal(_ request: String) async {
        guard let prompt = selectedPrompt, let helper else {
            appendTranscript(.warning, "Agent", "Choose a project and a prompt first.")
            return
        }
        guard await persistPromptWorkspace(showNoChangeNotice: false) else {
            return
        }
        do {
            try await withBusyState("Preparing edit") {
                let result = try await helper.send(
                    method: "agent.prepare_edit",
                    params: ["prompt": prompt, "request": request]
                )
                guard let proposal = proposalFromResult(result) else {
                    throw HelperClientError.missingField("The helper did not return a proposal.")
                }
                if shouldAutoApplyEdits {
                    appendTranscript(.agent, "Applying edit", proposal.summary)
                    try await autoApplyProposal(proposal, prompt: prompt)
                } else {
                    pendingProposal = proposal
                    let changedFiles = proposal.changedFiles.isEmpty ? "No file changes." : "Files: \(proposal.changedFiles.joined(separator: ", "))"
                    appendTranscript(.agent, "Proposal \(proposal.proposalID)", "\(proposal.summary)\n\n\(changedFiles)")
                    appendTranscript(.result, "Diff preview", proposal.diffPreview.isEmpty ? "No diff was produced." : proposal.diffPreview)
                }
            }
        } catch {
            appendTranscript(.warning, "Proposal failed", error.localizedDescription)
        }
    }

    private func autoApplyProposal(_ proposal: PreparedProposal, prompt: String) async throws {
        guard let helper else { return }
        let result = try await helper.send(
            method: "agent.apply_prepared_edit",
            params: ["prompt": prompt, "proposal_id": proposal.proposalID]
        )
        pendingProposal = nil
        if !proposal.diffPreview.isEmpty {
            appendTranscript(.result, "Applied diff", proposal.diffPreview)
        }
        applyResultPayload(result)
        await openPrompt(prompt, announce: false)
    }

    private func startEventStream() {
        guard let helper else { return }
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    let response = try await helper.subscribe(after: eventCursor)
                    await MainActor.run {
                        self.eventCursor = max(self.eventCursor, response.cursor)
                        self.consume(events: response.events)
                    }
                } catch {
                    if Task.isCancelled {
                        return
                    }
                    await MainActor.run {
                        self.appendTranscript(.warning, "Event stream", error.localizedDescription)
                    }
                    return
                }
            }
        }
    }

    private func consume(events: [HelperEvent]) {
        for event in events {
            guard let method = event.payload["method"] else {
                continue
            }
            switch event.type {
            case "request.started":
                if let line = streamStartLine(for: method) {
                    appendTranscript(.system, "Activity", line)
                }
            case "request.completed":
                if let line = streamCompletedLine(for: method) {
                    appendTranscript(.result, "Activity", line)
                }
            case "request.failed":
                let detail = event.payload["error"] ?? "Unknown helper error."
                appendTranscript(.warning, "Activity", "\(method) failed: \(detail)")
            default:
                break
            }
        }
    }

    private func streamStartLine(for method: String) -> String? {
        switch method {
        case "agent.chat":
            return "Agent is working through your request."
        case "coach.reply":
            return "Thinking through prompt guidance."
        case "agent.prepare_edit":
            return "Preparing staged edit proposal."
        case "agent.apply_prepared_edit":
            return "Applying staged edit."
        case "bench.run_quick":
            return "Running quick check."
        case "eval.run_full":
            return "Running full evaluation."
        case "prompts.create":
            return "Creating prompt."
        case "prompts.clone":
            return "Cloning prompt."
        case "prompts.export":
            return "Exporting prompt."
        case "revisions.restore":
            return "Restoring prompt revision."
        default:
            return nil
        }
    }

    private func streamCompletedLine(for method: String) -> String? {
        switch method {
        case "agent.chat":
            return "Agent finished the request."
        case "coach.reply":
            return "Returned prompt guidance."
        case "agent.prepare_edit":
            return "Prepared staged edit proposal."
        case "agent.apply_prepared_edit":
            return "Applied staged edit."
        case "bench.run_quick":
            return "Quick check finished."
        case "eval.run_full":
            return "Full evaluation finished."
        case "prompts.create":
            return "Prompt created."
        case "prompts.clone":
            return "Prompt cloned."
        case "prompts.export":
            return "Prompt exported."
        case "revisions.restore":
            return "Prompt revision restored."
        default:
            return nil
        }
    }

    private func handleSlashCommand(_ commandLine: String) async {
        let parts = commandLine.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let command = parts.first?.lowercased() else { return }
        switch command {
        case "/help":
            appendTranscript(
                .system,
                "Commands",
                """
                /prompts
                /open <name>
                /new <name>
                /clone <source> <name>
                /status
                /coach <request>
                /edit <request>
                /save
                /prompt
                /template
                /bench
                /full
                /diff
                /failures
                /apply
                /discard
                /undo
                /export <name>

                Any message without a slash is treated as agent chat for the active prompt.
                """
            )
        case "/coach":
            let request = String(commandLine.dropFirst(command.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !request.isEmpty else {
                appendTranscript(.warning, "Command", "Usage: /coach <request>")
                return
            }
            await coachPrompt(request)
        case "/edit":
            let request = String(commandLine.dropFirst(command.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !request.isEmpty else {
                appendTranscript(.warning, "Command", "Usage: /edit <request>")
                return
            }
            await prepareEditProposal(request)
        case "/save":
            _ = await persistPromptWorkspace()
        case "/prompts":
            let list = prompts.map { "\($0.version)  \( $0.name )" }.joined(separator: "\n")
            appendTranscript(.system, "Prompts", list.isEmpty ? "No prompts in this project." : list)
        case "/open":
            guard parts.count >= 2 else {
                appendTranscript(.warning, "Command", "Usage: /open <name>")
                return
            }
            await openPrompt(parts[1], announce: true)
        case "/new":
            guard parts.count >= 2 else {
                appendTranscript(.warning, "Command", "Usage: /new <name>")
                return
            }
            await createPrompt(parts[1], fromPrompt: nil)
        case "/clone":
            guard parts.count >= 3 else {
                appendTranscript(.warning, "Command", "Usage: /clone <source> <name>")
                return
            }
            await clonePrompt(source: parts[1], target: parts[2])
        case "/status":
            do {
                try await refreshStatus()
                appendTranscript(
                    .system,
                    "Status",
                    "\(providerLine)\n\(authLine)\n\(sessionLine)\nLatest score: \(latestScoreLine)"
                )
            } catch {
                appendTranscript(.warning, "Status", error.localizedDescription)
            }
        case "/prompt":
            appendTranscript(.system, "System prompt", promptDraft.systemPrompt)
        case "/template":
            appendTranscript(.system, "User template", promptDraft.userTemplate)
        case "/bench":
            await runHelperMethod(PromptForgeServiceMethod.benchRunQuick.rawValue)
        case "/full":
            await runHelperMethod("eval.run_full")
        case "/diff":
            if let pendingProposal {
                appendTranscript(.system, "Pending diff", pendingProposal.diffPreview)
            } else {
                let diffText = benchmarkRows
                    .filter { $0.0 != "Latest score" }
                    .map { "\($0.0): \($0.1)" }
                    .joined(separator: "\n")
                appendTranscript(.system, "Latest quick-check delta", diffText.isEmpty ? "No diff available yet." : diffText)
            }
        case "/failures":
            let failureText = failureCases
                .map { "\($0.caseID) | score \($0.score) | \($0.reasons)\n\($0.summary)" }
                .joined(separator: "\n\n")
            appendTranscript(.system, "Failures", failureText.isEmpty ? "No hard-failing cases." : failureText)
        case "/apply":
            await applyPendingProposal()
        case "/discard":
            await discardPendingProposal()
        case "/undo":
            await undoLatestRevision()
        case "/export":
            guard parts.count >= 2 else {
                appendTranscript(.warning, "Command", "Usage: /export <name>")
                return
            }
            await exportPrompt(named: parts[1])
        default:
            appendTranscript(.warning, "Command", "Unknown command: \(command)")
        }
    }

    private func createPrompt(_ name: String, displayName: String? = nil, fromPrompt: String?) async {
        guard let helper else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            _ = try await helper.send(
                method: "prompts.create",
                params: [
                    "prompt": name,
                    "name": displayName as Any,
                    "from_prompt": fromPrompt as Any,
                ]
            )
            try await refreshPrompts()
            await openPrompt(name, announce: true)
            selectedWorkspaceMode = .studio
        } catch {
            appendTranscript(.warning, "Create prompt", error.localizedDescription)
        }
    }

    private func promptCreationRequest() -> (version: String, displayName: String)? {
        let alert = NSAlert()
        alert.messageText = "New Prompt"
        alert.informativeText = "Choose a name for the prompt. PromptForge will create a clean internal id automatically."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        input.placeholderString = "Support Policy Responder"
        input.stringValue = suggestedPromptName()
        alert.accessoryView = input

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            return nil
        }

        let displayName = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !displayName.isEmpty else {
            appendTranscript(.warning, "Create prompt", "Prompt name cannot be empty.")
            return nil
        }

        return (
            version: uniquePromptVersion(for: displayName),
            displayName: displayName
        )
    }

    private func suggestedPromptName() -> String {
        let existingNames = Set(prompts.map(\.name))
        var index = prompts.count + 1
        while true {
            let candidate = "Untitled Prompt \(index)"
            if !existingNames.contains(candidate) {
                return candidate
            }
            index += 1
        }
    }

    private func uniquePromptVersion(for displayName: String) -> String {
        let existingVersions = Set(prompts.map(\.version))
        let base = slugifyPromptVersion(displayName)
        var candidate = base
        var suffix = 2
        while existingVersions.contains(candidate) {
            candidate = "\(base)-\(suffix)"
            suffix += 1
        }
        return candidate
    }

    private func slugifyPromptVersion(_ value: String) -> String {
        let lowered = value.lowercased()
        let pieces = lowered.components(separatedBy: CharacterSet.alphanumerics.inverted)
        let slug = pieces
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return slug.isEmpty ? "prompt" : slug
    }

    private func clonePrompt(source: String, target: String) async {
        guard let helper else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            _ = try await helper.send(
                method: "prompts.clone",
                params: ["source": source, "name": target]
            )
            try await refreshPrompts()
            await openPrompt(target, announce: true)
            selectedWorkspaceMode = .studio
        } catch {
            appendTranscript(.warning, "Clone prompt", error.localizedDescription)
        }
    }

    private func applyPendingProposal() async {
        guard let helper, let prompt = selectedPrompt, let pendingProposal else {
            appendTranscript(.warning, "Apply", "There is no pending proposal to apply.")
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let result = try await helper.send(
                method: "agent.apply_prepared_edit",
                params: ["prompt": prompt, "proposal_id": pendingProposal.proposalID]
            )
            self.pendingProposal = nil
            applyResultPayload(result)
            await openPrompt(prompt, announce: false)
        } catch {
            appendTranscript(.warning, "Apply", error.localizedDescription)
        }
    }

    private func discardPendingProposal() async {
        guard let helper, let prompt = selectedPrompt, let pendingProposal else {
            appendTranscript(.warning, "Discard", "There is no pending proposal to discard.")
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            _ = try await helper.send(
                method: "agent.discard_prepared_edit",
                params: ["prompt": prompt, "proposal_id": pendingProposal.proposalID]
            )
            self.pendingProposal = nil
            appendTranscript(.system, "Discarded", "Proposal \(pendingProposal.proposalID) was discarded.")
        } catch {
            appendTranscript(.warning, "Discard", error.localizedDescription)
        }
    }

    private func runHelperMethod(_ method: String) async {
        guard let helper, let prompt = selectedPrompt else {
            appendTranscript(.warning, "Agent", "Choose a prompt first.")
            return
        }
        guard await persistPromptWorkspace(showNoChangeNotice: false) else {
            return
        }
        do {
            let label = method == PromptForgeServiceMethod.benchRunQuick.rawValue ? "Running quick check" : "Running evaluation"
            try await withBusyState(label) {
                let result = try await helper.send(method: method, params: ["prompt": prompt])
                applyResultPayload(result)
                await openPrompt(prompt, announce: false)
            }
        } catch {
            appendTranscript(.warning, method, error.localizedDescription)
        }
    }

    private func undoLatestRevision() async {
        guard let helper, let prompt = selectedPrompt else {
            appendTranscript(.warning, "Undo", "Choose a prompt first.")
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let result = try await helper.send(method: "revisions.list", params: ["prompt": prompt])
            guard let revisions = result["revisions"] as? [[String: Any]], revisions.count >= 2 else {
                appendTranscript(.warning, "Undo", "There is no earlier revision to restore.")
                return
            }
            guard let revisionID = revisions[revisions.count - 2]["revision_id"] as? String else {
                throw HelperClientError.missingField("The helper did not return a revision id.")
            }
            let restore = try await helper.send(
                method: "revisions.restore",
                params: ["prompt": prompt, "revision_id": revisionID]
            )
            applyResultPayload(restore)
            await openPrompt(prompt, announce: false)
        } catch {
            appendTranscript(.warning, "Undo", error.localizedDescription)
        }
    }

    private func exportPrompt(named name: String) async {
        guard let helper, let prompt = selectedPrompt else {
            appendTranscript(.warning, "Export", "Choose a prompt first.")
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let result = try await helper.send(
                method: "prompts.export",
                params: ["prompt": prompt, "name": name]
            )
            let exportedPath = result["exported"] as? String ?? name
            try await refreshPrompts()
            appendTranscript(.result, "Exported", "Saved prompt to \(exportedPath)")
        } catch {
            appendTranscript(.warning, "Export", error.localizedDescription)
        }
    }

    private func loadSettings(openingMode: String) async {
        guard let helper else {
            settingsError = "Open a project before editing settings."
            return
        }
        isBusy = true
        settingsError = nil
        settingsNotice = nil
        defer { isBusy = false }
        do {
            let payload = try await helper.send(method: "settings.get")
            applySettingsPayload(payload)
            settingsMode = openingMode
            showSettings = true
            Task {
                await refreshConnectionStatuses(showBusy: false, surfaceErrorsInTranscript: false)
            }
        } catch {
            settingsError = error.localizedDescription
            appendTranscript(.warning, "Settings", error.localizedDescription)
        }
    }

    private func persistSettings() async {
        guard let helper else {
            settingsError = "Open a project before saving settings."
            return
        }
        isBusy = true
        settingsError = nil
        settingsNotice = nil
        defer { isBusy = false }

        let openAIKey = openAIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let openRouterKey = openRouterKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !openAIKey.isEmpty {
            _ = KeychainSecretStore.write(key: "OPENAI_API_KEY", value: openAIKey)
            openAIKeyDraft = ""
        }
        if !openRouterKey.isEmpty {
            _ = KeychainSecretStore.write(key: "OPENROUTER_API_KEY", value: openRouterKey)
            openRouterKeyDraft = ""
        }

        do {
            let onboardingMode = isOnboarding
            let currentProjectPath = projectPath
            let currentEngineRoot = engineRoot
            let payload = try await helper.send(
                method: "settings.update",
                params: [
                    "name": settingsDraft.projectName,
                    "preferred_provider": settingsDraft.provider,
                    "preferred_judge_provider": settingsDraft.judgeProvider,
                    "preferred_generation_model": settingsDraft.generationModel,
                    "preferred_judge_model": settingsDraft.judgeModel,
                    "preferred_agent_model": settingsDraft.agentModel,
                    "quick_benchmark_dataset": settingsDraft.quickBenchmarkDataset,
                    "full_evaluation_dataset": settingsDraft.fullEvaluationDataset,
                    "quick_benchmark_repeats": settingsDraft.quickBenchmarkRepeats,
                    "full_evaluation_repeats": settingsDraft.fullEvaluationRepeats,
                    "builder_permission_mode": settingsDraft.builderPermissionMode,
                    "builder_research_policy": settingsDraft.builderResearchPolicy,
                ]
            )
            applySettingsPayload(payload)
            settingsNotice = "Settings saved."
            if onboardingMode {
                UserDefaults.standard.set(true, forKey: "PromptForgeCompletedOnboarding")
            }
            showSettings = false
            if let currentProjectPath {
                await openProject(at: currentProjectPath, engineRoot: currentEngineRoot)
            }
        } catch {
            settingsError = error.localizedDescription
        }
    }

    private func persistPromptWorkspace(showNoChangeNotice: Bool = true) async -> Bool {
        guard let helper, let prompt = selectedPrompt else {
            appendTranscript(.warning, "Save prompt", "Choose a prompt before saving.")
            return false
        }
        guard promptHasUnsavedChanges else {
            if showNoChangeNotice {
                promptSaveNotice = "No prompt changes to save."
            }
            return true
        }
        isBusy = true
        promptSaveNotice = nil
        defer { isBusy = false }
        do {
            let result = try await helper.send(
                method: "prompt.save",
                params: [
                    "prompt": prompt,
                    "system_prompt": promptDraft.systemPrompt,
                    "user_template": promptDraft.userTemplate,
                    "purpose": promptDraft.purpose,
                    "expected_behavior": promptDraft.expectedBehavior,
                    "success_criteria": promptDraft.successCriteria,
                    "baseline_prompt_ref": promptDraft.baselinePromptRef,
                    "primary_scenario_suites": promptDraft.primaryScenarioSuites,
                    "owner": promptDraft.owner,
                    "audience": promptDraft.audience,
                    "release_notes": promptDraft.releaseNotes,
                    "builder_agent_model": promptDraft.builderAgentModel,
                    "builder_permission_mode": promptDraft.builderPermissionMode,
                    "research_policy": promptDraft.researchPolicy,
                    "prompt_blocks": promptDraft.promptBlocks.map { block in
                        [
                            "block_id": block.blockID,
                            "title": block.title,
                            "body": block.body,
                            "target": block.target,
                            "enabled": block.enabled,
                        ]
                    },
                ]
            )
            applyPromptPayload(result)
            applyResultPayload(result)
            promptSaveNotice = "Saved prompt workspace."
            appendTranscript(.result, "Prompt saved", "Saved overview fields and prompt files for \(prompt).")
            return true
        } catch {
            promptSaveNotice = error.localizedDescription
            appendTranscript(.warning, "Save prompt", error.localizedDescription)
            return false
        }
    }

    private func applySettingsPayload(_ payload: [String: Any]) {
        if let settingsPayload = payload["settings"] as? [String: Any] {
            settingsDraft = AppSettingsDraft(
                projectName: settingsPayload["name"] as? String ?? projectName,
                provider: settingsPayload["preferred_provider"] as? String ?? "openai",
                judgeProvider: settingsPayload["preferred_judge_provider"] as? String ?? settingsDraft.provider,
                generationModel: settingsPayload["preferred_generation_model"] as? String ?? "gpt-5.4",
                judgeModel: settingsPayload["preferred_judge_model"] as? String ?? "gpt-5-mini",
                agentModel: settingsPayload["preferred_agent_model"] as? String ?? "gpt-5-mini",
                quickBenchmarkDataset: settingsPayload["quick_benchmark_dataset"] as? String ?? "datasets/core.jsonl",
                fullEvaluationDataset: settingsPayload["full_evaluation_dataset"] as? String ?? "datasets/core.jsonl",
                quickBenchmarkRepeats: settingsPayload["quick_benchmark_repeats"] as? Int ?? 1,
                fullEvaluationRepeats: settingsPayload["full_evaluation_repeats"] as? Int ?? 1,
                builderPermissionMode: settingsPayload["builder_permission_mode"] as? String ?? "proposal_only",
                builderResearchPolicy: settingsPayload["builder_research_policy"] as? String ?? "prompt_only"
            )
        }
        if let authPayload = payload["auth"] as? [String: Any] {
            applyConnectionPayload(authPayload)
        }
    }

    private func applyConnectionPayload(_ authPayload: [String: Any]) {
        let rawConnections = authPayload["connections"] as? [String: Any] ?? [:]
        let connectionPayloads = rawConnections.reduce(into: [String: [String: Any]]()) { partialResult, item in
            if let payload = item.value as? [String: Any] {
                partialResult[item.key] = payload
            }
        }
        let openAIKeyLoaded = KeychainSecretStore.has(key: "OPENAI_API_KEY")
        let openRouterKeyLoaded = KeychainSecretStore.has(key: "OPENROUTER_API_KEY")
        connectionStatuses = [
            ProviderConnectionStatus(
                id: "openai",
                label: "OpenAI",
                ready: (connectionPayloads["openai"]?["ready"] as? Bool ?? false) || openAIKeyLoaded,
                detail: connectionPayloads["openai"]?["detail"] as? String ?? (openAIKeyLoaded ? "API key available." : "API key missing."),
                source: openAIKeyLoaded ? "Keychain" : "Not loaded"
            ),
            ProviderConnectionStatus(
                id: "openrouter",
                label: "OpenRouter",
                ready: (connectionPayloads["openrouter"]?["ready"] as? Bool ?? false) || openRouterKeyLoaded,
                detail: connectionPayloads["openrouter"]?["detail"] as? String ?? (openRouterKeyLoaded ? "API key available." : "API key missing."),
                source: openRouterKeyLoaded ? "Keychain" : "Not loaded"
            ),
            ProviderConnectionStatus(
                id: "codex",
                label: "Codex",
                ready: connectionPayloads["codex"]?["ready"] as? Bool ?? false,
                detail: connectionPayloads["codex"]?["detail"] as? String ?? "Codex status unknown.",
                source: connectionPayloads["codex"]?["source"] as? String ?? "System CLI"
            ),
        ]
    }

    private func refreshLocalConnectionStatuses() {
        applyConnectionPayload([:])
    }

    private func resetPromptWorkspaceState() {
        prompts = []
        selectedPrompt = nil
        selectedSuiteID = nil
        selectedScenarioCaseID = nil
        selectedReviewID = nil
        selectedReviewCaseID = nil
        currentPromptName = ""
        currentPromptDescription = ""
        promptRootPath = ""
        systemPrompt = ""
        userTemplate = ""
        promptDraft = .init()
        savedPromptDraft = .init()
        promptFiles = []
        benchmarkRows = []
        weakCases = []
        failureCases = []
        pendingProposal = nil
        scenarioSuites = []
        scenarioDraft = nil
        builderActions = []
        reviews = []
        decisions = []
        latestPlaygroundRun = nil
        promptSaveNotice = nil
        sessionLine = "session --"
        latestScoreLine = "--"
    }

    func refreshConnectionStatuses() {
        Task {
            await refreshConnectionStatuses(showBusy: false, surfaceErrorsInTranscript: false)
        }
    }

    private func refreshConnectionStatuses(showBusy: Bool, surfaceErrorsInTranscript: Bool) async {
        guard let helper else { return }
        if showBusy {
            isBusy = true
        }
        settingsError = nil
        defer {
            if showBusy {
                isBusy = false
            }
        }
        do {
            let payload = try await helper.send(method: "connections.refresh")
            if let authPayload = payload["auth"] as? [String: Any] {
                applyConnectionPayload(authPayload)
            }
        } catch {
            settingsError = error.localizedDescription
            if surfaceErrorsInTranscript {
                appendTranscript(.warning, "Connections", error.localizedDescription)
            }
        }
    }

    private func refreshPrompts() async throws {
        guard let helper else { return }
        let promptResult = try await helper.send(method: "prompts.list")
        guard let promptPayloads = promptResult["prompts"] as? [[String: Any]] else {
            throw HelperClientError.missingField("The helper did not return a prompt list.")
        }
        prompts = promptPayloads.compactMap { payload in
            guard let version = payload["version"] as? String else { return nil }
            let name = payload["name"] as? String ?? version
            let description = payload["description"] as? String ?? ""
            return PromptSummaryModel(version: version, name: name, description: description)
        }
        if prompts.isEmpty {
            resetPromptWorkspaceState()
            return
        }
        let promptVersions = Set(prompts.map(\.version))
        if let selectedPrompt, !promptVersions.contains(selectedPrompt) {
            self.selectedPrompt = nil
        }
        if self.selectedPrompt == nil {
            self.selectedPrompt = prompts.first?.version
        }
    }

    private func refreshStatus() async throws {
        guard let helper else { return }
        let statusPayload = try await helper.send(method: "status.get")
        guard
            let project = statusPayload["project"] as? [String: Any],
            let metadata = project["metadata"] as? [String: Any]
        else {
            throw HelperClientError.invalidResponse
        }
        projectName = metadata["name"] as? String ?? "PromptForge Project"
        if let activePrompt = statusPayload["active_prompt"] as? String {
            let promptVersions = Set(prompts.map(\.version))
            selectedPrompt = promptVersions.contains(activePrompt) ? activePrompt : prompts.first?.version
        }
        sessionLine = "session \(statusPayload["active_session"] as? String ?? "--")"
        if
            let auth = statusPayload["auth"] as? [String: Any],
            let provider = auth["provider"] as? [String: Any],
            let judge = auth["judge"] as? [String: Any]
        {
            let providerName = provider["name"] as? String ?? "--"
            let judgeName = judge["name"] as? String ?? "--"
            providerLine = "\(providerName) -> judge \(judgeName)"
            let providerDetail = provider["detail"] as? String ?? ""
            authLine = providerDetail
            applyConnectionPayload(auth)
        }
    }

    private func refreshScenarioSuites() async throws {
        guard let helper, let prompt = selectedPrompt else {
            scenarioSuites = []
            scenarioDraft = nil
            selectedSuiteID = nil
            selectedScenarioCaseID = nil
            return
        }
        let payload = try await helper.send(method: "scenarios.list", params: ["prompt": prompt])
        let suitePayloads = payload["suites"] as? [[String: Any]] ?? []
        scenarioSuites = suitePayloads.compactMap(parseSuite(_:))
        let preferredSuiteID = selectedSuiteID ?? promptDraft.primaryScenarioSuites.first
        if let preferredSuiteID, scenarioSuites.contains(where: { $0.suiteID == preferredSuiteID }) {
            selectSuite(preferredSuiteID)
        } else {
            selectSuite(scenarioSuites.first?.suiteID)
        }
    }

    private func refreshBuilderActions() async throws {
        guard let helper, let prompt = selectedPrompt else {
            builderActions = []
            return
        }
        let payload = try await helper.send(method: "builder.actions", params: ["prompt": prompt])
        let actionPayloads = payload["actions"] as? [[String: Any]] ?? []
        builderActions = actionPayloads.compactMap(parseBuilderAction(_:))
    }

    private func refreshReviews() async throws {
        guard let helper, let prompt = selectedPrompt else {
            reviews = []
            selectedReviewID = nil
            return
        }
        let payload = try await helper.send(method: "review.latest", params: ["prompt": prompt])
        let reviewPayloads = payload["reviews"] as? [[String: Any]] ?? []
        reviews = reviewPayloads.compactMap(parseReview(_:))
        if selectedReviewID == nil {
            selectedReviewID = reviews.last?.reviewID
        }
        if selectedReviewCaseID == nil {
            selectedReviewCaseID = reviews.last?.cases.first?.caseID
        }
    }

    private func refreshDecisions() async throws {
        guard let helper, let prompt = selectedPrompt else {
            decisions = []
            return
        }
        let payload = try await helper.send(method: "decisions.list", params: ["prompt": prompt])
        let decisionPayloads = payload["decisions"] as? [[String: Any]] ?? []
        decisions = decisionPayloads.compactMap(parseDecision(_:))
    }

    func runPlayground() {
        Task {
            await triggerPlayground()
        }
    }

    func selectSuite(_ suiteID: String?) {
        selectedSuiteID = suiteID
        scenarioDraft = scenarioSuites.first(where: { $0.suiteID == suiteID }) ?? scenarioSuites.first
        selectedScenarioCaseID = scenarioDraft?.cases.first?.caseID
    }

    func createScenarioCase() {
        guard var suite = scenarioDraft ?? selectedSuite else { return }
        let caseID = "case-\(Int(Date().timeIntervalSince1970))"
        let newCase = ScenarioCaseModel(
            caseID: caseID,
            title: "New Case",
            inputJSON: "{\n  \"input\": \"Describe the scenario here\"\n}",
            contextText: "",
            tags: [],
            notes: "",
            assertions: []
        )
        suite.cases.append(newCase)
        scenarioDraft = suite
        selectedScenarioCaseID = caseID
        scenarioNotice = "Added a new scenario case."
    }

    func duplicateSelectedScenarioCase() {
        guard var suite = scenarioDraft ?? selectedSuite, let selectedScenarioCase else { return }
        let duplicateID = "\(selectedScenarioCase.caseID)-copy-\(Int(Date().timeIntervalSince1970))"
        var duplicate = selectedScenarioCase
        duplicate.title = selectedScenarioCase.title.isEmpty ? "Copied Case" : "\(selectedScenarioCase.title) Copy"
        let duplicatedCase = ScenarioCaseModel(
            caseID: duplicateID,
            title: duplicate.title,
            inputJSON: duplicate.inputJSON,
            contextText: duplicate.contextText,
            tags: duplicate.tags,
            notes: duplicate.notes,
            assertions: duplicate.assertions.enumerated().map { index, assertion in
                ScenarioAssertionModel(
                    assertionID: "\(duplicateID)-assertion-\(index)",
                    label: assertion.label,
                    kind: assertion.kind,
                    expectedText: assertion.expectedText,
                    threshold: assertion.threshold,
                    trait: assertion.trait,
                    severity: assertion.severity
                )
            }
        )
        suite.cases.append(duplicatedCase)
        scenarioDraft = suite
        selectedScenarioCaseID = duplicateID
        scenarioNotice = "Duplicated scenario case."
    }

    func deleteSelectedScenarioCase() {
        guard var suite = scenarioDraft ?? selectedSuite, let selectedScenarioCaseID else { return }
        suite.cases.removeAll { $0.caseID == selectedScenarioCaseID }
        scenarioDraft = suite
        self.selectedScenarioCaseID = suite.cases.first?.caseID
        scenarioNotice = "Removed scenario case."
    }

    func addAssertionToSelectedCase() {
        guard var suite = scenarioDraft ?? selectedSuite, let selectedScenarioCaseID else { return }
        guard let caseIndex = suite.cases.firstIndex(where: { $0.caseID == selectedScenarioCaseID }) else { return }
        let assertionID = "\(selectedScenarioCaseID)-assertion-\(suite.cases[caseIndex].assertions.count + 1)"
        suite.cases[caseIndex].assertions.append(
            ScenarioAssertionModel(
                assertionID: assertionID,
                label: "New assertion",
                kind: "required_string",
                expectedText: "",
                threshold: nil,
                trait: "",
                severity: "fail"
            )
        )
        scenarioDraft = suite
        scenarioNotice = "Added assertion."
    }

    func promotePlaygroundInputToScenario() {
        guard var suite = scenarioDraft ?? selectedSuite else {
            scenarioNotice = "Create or select a test suite first."
            return
        }
        guard parseJSONObject(from: playgroundInputJSON) != nil else {
            appendTranscript(.warning, "Tests", "Playground input must be valid JSON before promoting it to a case.")
            return
        }
        let caseID = "playground-\(Int(Date().timeIntervalSince1970))"
        let newCase = ScenarioCaseModel(
            caseID: caseID,
            title: "Playground Capture",
            inputJSON: playgroundInputJSON,
            contextText: playgroundContext,
            tags: ["playground"],
            notes: "Created from the Studio playground.",
            assertions: []
        )
        suite.cases.append(newCase)
        scenarioDraft = suite
        selectedSuiteID = suite.suiteID
        selectedScenarioCaseID = caseID
        selectedWorkspaceMode = .tests
        scenarioNotice = "Promoted the current playground input into the selected test suite."
    }

    func saveScenarioSuite() {
        Task {
            await persistScenarioSuite()
        }
    }

    func runScenarioReview() {
        Task {
            await triggerScenarioReview()
        }
    }

    func recordIterateDecision() {
        Task {
            await recordDecision(status: "iterate", summary: "Continue iterating after review.")
        }
    }

    func promoteCurrentCandidate() {
        Task {
            await promoteDecision()
        }
    }

    private func triggerPlayground() async {
        guard let helper, let prompt = selectedPrompt else {
            appendTranscript(.warning, "Playground", "Choose a prompt first.")
            return
        }
        guard let inputPayload = parseJSONObject(from: playgroundInputJSON) else {
            appendTranscript(.warning, "Playground", "Playground input must be valid JSON.")
            return
        }
        guard await persistPromptWorkspace(showNoChangeNotice: false) else {
            return
        }
        do {
            try await withBusyState("Running playground") {
                let payload = try await helper.send(
                    method: "playground.run",
                    params: [
                        "prompt": prompt,
                        "input_payload": inputPayload,
                        "context": playgroundContext,
                        "samples": playgroundSampleCount,
                        "compare_baseline": true,
                    ]
                )
                latestPlaygroundRun = parsePlaygroundRun(payload["playground"] as? [String: Any] ?? [:])
                try? await refreshBuilderActions()
                scenarioNotice = nil
            }
        } catch {
            appendTranscript(.warning, "Playground", error.localizedDescription)
        }
    }

    private func triggerScenarioReview() async {
        guard let helper, let prompt = selectedPrompt, let suiteID = selectedSuite?.suiteID else {
            appendTranscript(.warning, "Review", "Choose a prompt and test suite first.")
            return
        }
        guard await persistPromptWorkspace(showNoChangeNotice: false) else {
            return
        }
        do {
            let caseCount = selectedSuite?.cases.count ?? 0
            let label = caseCount > 0 ? "Running \(caseCount) tests" : "Running tests"
            try await withBusyState(label) {
                let payload = try await helper.send(
                    method: "review.run_suite",
                    params: ["prompt": prompt, "suite_id": suiteID]
                )
                if let reviewPayload = payload["review"] as? [String: Any], let review = parseReview(reviewPayload) {
                    reviews.append(review)
                    selectedReviewID = review.reviewID
                    selectedReviewCaseID = review.cases.first?.caseID
                    selectedWorkspaceMode = .review
                }
                try? await refreshBuilderActions()
                try? await refreshDecisions()
            }
        } catch {
            appendTranscript(.warning, "Review", error.localizedDescription)
        }
    }

    private func recordDecision(status: String, summary: String) async {
        guard let helper, let prompt = selectedPrompt else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            _ = try await helper.send(
                method: "decisions.record",
                params: [
                    "prompt": prompt,
                    "status": status,
                    "summary": summary,
                    "review_id": latestReview?.reviewID as Any,
                    "suite_id": latestReview?.suiteID as Any,
                ]
            )
            try? await refreshDecisions()
            try? await refreshBuilderActions()
        } catch {
            appendTranscript(.warning, "Decision", error.localizedDescription)
        }
    }

    private func promoteDecision() async {
        guard let helper, let prompt = selectedPrompt else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            _ = try await helper.send(
                method: "decisions.promote",
                params: [
                    "prompt": prompt,
                    "summary": "Ship current candidate to baseline.",
                    "review_id": latestReview?.reviewID as Any,
                    "suite_id": latestReview?.suiteID as Any,
                ]
            )
            try? await refreshDecisions()
            try? await refreshBuilderActions()
            try? await refreshStatus()
        } catch {
            appendTranscript(.warning, "Ship", error.localizedDescription)
        }
    }

    private func persistScenarioSuite() async {
        guard let helper, var suite = scenarioDraft ?? selectedSuite else {
            appendTranscript(.warning, "Tests", "Choose a test suite before saving.")
            return
        }
        guard let prompt = selectedPrompt else {
            appendTranscript(.warning, "Tests", "Choose a prompt before saving a test suite.")
            return
        }
        let parsedCases = suite.cases.compactMap(buildScenarioCasePayload(_:))
        guard parsedCases.count == suite.cases.count else {
            appendTranscript(.warning, "Tests", "Every test case must contain valid JSON input before saving.")
            return
        }
        if !suite.linkedPrompts.contains(prompt) {
            suite.linkedPrompts.append(prompt)
        }
        isBusy = true
        scenarioNotice = nil
        defer { isBusy = false }
        do {
            let payload = try await helper.send(
                method: "scenarios.save",
                params: [
                    "suite": [
                        "format_version": 1,
                        "suite_id": suite.suiteID,
                        "name": suite.name,
                        "description": suite.description,
                        "linked_prompts": suite.linkedPrompts,
                        "cases": parsedCases,
                        "created_at": suite.createdAt,
                        "updated_at": suite.updatedAt,
                    ]
                ]
            )
            if let savedSuite = parseSuite(payload["suite"] as? [String: Any] ?? [:]) {
                if let index = scenarioSuites.firstIndex(where: { $0.suiteID == savedSuite.suiteID }) {
                    scenarioSuites[index] = savedSuite
                } else {
                    scenarioSuites.append(savedSuite)
                    scenarioSuites.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                }
                scenarioDraft = savedSuite
                selectedSuiteID = savedSuite.suiteID
                if !savedSuite.cases.isEmpty {
                    if let selectedScenarioCaseID, savedSuite.cases.contains(where: { $0.caseID == selectedScenarioCaseID }) {
                        self.selectedScenarioCaseID = selectedScenarioCaseID
                    } else {
                        self.selectedScenarioCaseID = savedSuite.cases.first?.caseID
                    }
                } else {
                    selectedScenarioCaseID = nil
                }
            }
            scenarioNotice = "Test suite saved."
            appendTranscript(.result, "Tests", "Saved suite \(suite.name).")
        } catch {
            scenarioNotice = error.localizedDescription
            appendTranscript(.warning, "Tests", error.localizedDescription)
        }
    }

    private func applyPromptPayload(_ result: [String: Any]) {
        guard let payload = result["prompt"] as? [String: Any] else { return }
        selectedPrompt = payload["version"] as? String ?? selectedPrompt
        currentPromptName = payload["name"] as? String ?? selectedPrompt ?? ""
        currentPromptDescription = payload["description"] as? String ?? ""
        promptRootPath = payload["root"] as? String ?? ""
        systemPrompt = payload["system_prompt"] as? String ?? ""
        userTemplate = payload["user_template"] as? String ?? ""
        promptDraft = PromptWorkspaceDraft(
            purpose: payload["purpose"] as? String ?? "",
            expectedBehavior: payload["expected_behavior"] as? String ?? "",
            successCriteria: payload["success_criteria"] as? String ?? "",
            baselinePromptRef: payload["baseline_prompt_ref"] as? String ?? "",
            primaryScenarioSuites: payload["primary_scenario_suites"] as? [String] ?? [],
            owner: payload["owner"] as? String ?? "",
            audience: payload["audience"] as? String ?? "",
            releaseNotes: payload["release_notes"] as? String ?? "",
            builderAgentModel: payload["builder_agent_model"] as? String ?? "gpt-5-mini",
            builderPermissionMode: payload["builder_permission_mode"] as? String ?? "proposal_only",
            researchPolicy: payload["research_policy"] as? String ?? "prompt_only",
            promptBlocks: (payload["prompt_blocks"] as? [[String: Any]] ?? []).compactMap(parsePromptBlock(_:)),
            systemPrompt: systemPrompt,
            userTemplate: userTemplate
        )
        savedPromptDraft = promptDraft
        promptFiles = payload["files"] as? [String] ?? []
        promptSaveNotice = nil
    }

    private func applyInsightsPayload(_ result: [String: Any]) {
        let insightObject = (result["insights"] as? [String: Any]) ?? result
        if let sessionID = insightObject["session_id"] as? String {
            sessionLine = "session \(sessionID)"
        }
        if let statusRows = insightObject["status_rows"] as? [[Any]], !statusRows.isEmpty {
            benchmarkRows = statusRows.compactMap { row in
                guard row.count >= 2, let key = row[0] as? String, let value = row[1] as? String else {
                    return nil
                }
                return (key, value)
            }
            latestScoreLine = benchmarkRows.first(where: { $0.0 == "Latest score" })?.1 ?? latestScoreLine
        }
        weakCases = parseCases(insightObject["weak_cases"] as? [[String: Any]] ?? [])
        failureCases = parseCases(insightObject["failures"] as? [[String: Any]] ?? [])
    }

    private func applyResultPayload(_ result: [String: Any]) {
        if let resultPayload = result["result"] as? [String: Any] {
            let summary = resultPayload["summary"] as? String ?? "Completed."
            let diffPreview = resultPayload["diff_preview"] as? String ?? ""
            appendTranscript(.result, "Result", summary)
            if !diffPreview.isEmpty {
                appendTranscript(.result, "Diff", diffPreview)
            }
        } else if let revision = result["revision"] as? [String: Any] {
            let revisionID = revision["revision_id"] as? String ?? "revision"
            appendTranscript(.result, "Run complete", "Updated \(revisionID).")
        }
        if result["insights"] != nil {
            applyInsightsPayload(result)
        }
    }

    private func proposalFromResult(_ result: [String: Any]) -> PreparedProposal? {
        guard let proposal = result["proposal"] as? [String: Any] else { return nil }
        guard let proposalID = proposal["proposal_id"] as? String else { return nil }
        let summary = proposal["summary"] as? String ?? "Prepared a prompt proposal."
        let diffPreview = proposal["diff_preview"] as? String ?? ""
        let changedFiles = proposal["changed_files"] as? [String] ?? []
        return PreparedProposal(
            proposalID: proposalID,
            summary: summary,
            diffPreview: diffPreview,
            changedFiles: changedFiles
        )
    }

    private func parseCases(_ payload: [[String: Any]]) -> [CaseIssue] {
        payload.compactMap { item in
            guard let caseID = item["case_id"] as? String else { return nil }
            return CaseIssue(
                caseID: caseID,
                score: item["score"] as? String ?? "--",
                hardFailRate: item["hard_fail_rate"] as? String ?? "--",
                reasons: item["reasons"] as? String ?? "--",
                summary: item["summary"] as? String ?? "--"
            )
        }
    }

    private func parseSuite(_ payload: [String: Any]) -> ScenarioSuiteModel? {
        guard let suiteID = payload["suite_id"] as? String else { return nil }
        let casePayloads = payload["cases"] as? [[String: Any]] ?? []
        let cases = casePayloads.compactMap(parseScenarioCase(_:))
        return ScenarioSuiteModel(
            suiteID: suiteID,
            name: payload["name"] as? String ?? suiteID,
            description: payload["description"] as? String ?? "",
            linkedPrompts: payload["linked_prompts"] as? [String] ?? [],
            cases: cases,
            createdAt: payload["created_at"] as? String ?? "",
            updatedAt: payload["updated_at"] as? String ?? ""
        )
    }

    private func parseScenarioCase(_ payload: [String: Any]) -> ScenarioCaseModel? {
        guard let caseID = payload["case_id"] as? String else { return nil }
        let inputObject = payload["input"] as? [String: Any] ?? [:]
        let assertions = (payload["assertions"] as? [[String: Any]] ?? []).compactMap(parseScenarioAssertion(_:))
        let inputData = try? JSONSerialization.data(withJSONObject: inputObject, options: [.prettyPrinted, .sortedKeys])
        let inputJSON = inputData.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return ScenarioCaseModel(
            caseID: caseID,
            title: payload["title"] as? String ?? caseID,
            inputJSON: inputJSON,
            contextText: String(describing: payload["context"] ?? ""),
            tags: payload["tags"] as? [String] ?? [],
            notes: payload["notes"] as? String ?? "",
            assertions: assertions
        )
    }

    private func parseScenarioAssertion(_ payload: [String: Any]) -> ScenarioAssertionModel? {
        guard let assertionID = payload["assertion_id"] as? String else { return nil }
        return ScenarioAssertionModel(
            assertionID: assertionID,
            label: payload["label"] as? String ?? assertionID,
            kind: payload["kind"] as? String ?? "required_string",
            expectedText: payload["expected_text"] as? String ?? "",
            threshold: payload["threshold"] as? Double,
            trait: payload["trait"] as? String ?? "",
            severity: payload["severity"] as? String ?? "fail"
        )
    }

    private func parseBuilderAction(_ payload: [String: Any]) -> BuilderActionModel? {
        guard let actionID = payload["action_id"] as? String else { return nil }
        return BuilderActionModel(
            actionID: actionID,
            kind: payload["kind"] as? String ?? "chat",
            title: payload["title"] as? String ?? "Action",
            details: payload["details"] as? String ?? "",
            files: payload["files"] as? [String] ?? [],
            tools: payload["tools"] as? [String] ?? [],
            usedResearch: payload["used_research"] as? Bool ?? false,
            permissionMode: payload["permission_mode"] as? String ?? "proposal_only",
            createdAt: payload["created_at"] as? String ?? ""
        )
    }

    private func parsePlaygroundRun(_ payload: [String: Any]) -> PlaygroundRunModel? {
        guard let runID = payload["run_id"] as? String else { return nil }
        let candidateSamples = (payload["candidate_samples"] as? [[String: Any]] ?? []).compactMap(parsePlaygroundSample(_:))
        let baselineSamples = (payload["baseline_samples"] as? [[String: Any]] ?? []).compactMap(parsePlaygroundSample(_:))
        let inputObject = payload["input_payload"] as? [String: Any] ?? [:]
        let inputData = try? JSONSerialization.data(withJSONObject: inputObject, options: [.prettyPrinted, .sortedKeys])
        return PlaygroundRunModel(
            runID: runID,
            createdAt: payload["created_at"] as? String ?? "",
            inputJSON: inputData.flatMap { String(data: $0, encoding: .utf8) } ?? "{}",
            contextText: String(describing: payload["context"] ?? ""),
            candidateSamples: candidateSamples,
            baselineSamples: baselineSamples
        )
    }

    private func parsePlaygroundSample(_ payload: [String: Any]) -> PlaygroundSampleModel? {
        guard let sampleID = payload["sample_id"] as? String else { return nil }
        let usage = payload["usage"] as? [String: Any] ?? [:]
        let totalTokens = usage["total_tokens"] as? Int ?? 0
        return PlaygroundSampleModel(
            sampleID: sampleID,
            outputText: payload["output_text"] as? String ?? "",
            latencyMS: payload["latency_ms"] as? Int ?? 0,
            totalTokens: totalTokens
        )
    }

    private func parseReview(_ payload: [String: Any]) -> ReviewSummaryModel? {
        guard let reviewID = payload["review_id"] as? String else { return nil }
        let cases = (payload["cases"] as? [[String: Any]] ?? []).compactMap(parseReviewCase(_:))
        let diff = payload["diff"] as? [String: Any] ?? [:]
        return ReviewSummaryModel(
            reviewID: reviewID,
            suiteID: payload["suite_id"] as? String ?? "",
            suiteName: payload["suite_name"] as? String ?? "Review",
            createdAt: payload["created_at"] as? String ?? "",
            revisionID: payload["revision_id"] as? String ?? "",
            scoreDelta: diff["mean_score_delta"] as? Double,
            passRateDelta: diff["pass_rate_delta"] as? Double,
            cases: cases
        )
    }

    private func parseReviewCase(_ payload: [String: Any]) -> ReviewCaseModel? {
        guard let caseID = payload["case_id"] as? String else { return nil }
        let assertions = (payload["assertions"] as? [[String: Any]] ?? []).compactMap(parseReviewAssertion(_:))
        return ReviewCaseModel(
            caseID: caseID,
            title: payload["title"] as? String ?? caseID,
            candidateScore: payload["candidate_score"] as? Double,
            baselineScore: payload["baseline_score"] as? Double,
            regression: payload["regression"] as? Bool ?? false,
            flaky: payload["flaky"] as? Bool ?? false,
            candidateOutput: payload["candidate_output"] as? String ?? "",
            baselineOutput: payload["baseline_output"] as? String ?? "",
            diffPreview: payload["diff_preview"] as? String ?? "",
            hardFailReasons: payload["hard_fail_reasons"] as? [String] ?? [],
            assertions: assertions,
            likelyChangedFiles: payload["likely_changed_files"] as? [String] ?? []
        )
    }

    private func parseReviewAssertion(_ payload: [String: Any]) -> ReviewAssertionModel? {
        guard let assertionID = payload["assertion_id"] as? String else { return nil }
        return ReviewAssertionModel(
            assertionID: assertionID,
            label: payload["label"] as? String ?? assertionID,
            status: payload["status"] as? String ?? "passed",
            detail: payload["detail"] as? String ?? ""
        )
    }

    private func parseDecision(_ payload: [String: Any]) -> DecisionRecordModel? {
        guard let decisionID = payload["decision_id"] as? String else { return nil }
        return DecisionRecordModel(
            decisionID: decisionID,
            status: payload["status"] as? String ?? "iterate",
            summary: payload["summary"] as? String ?? "",
            rationale: payload["rationale"] as? String ?? "",
            createdAt: payload["created_at"] as? String ?? ""
        )
    }

    private func parsePromptBlock(_ payload: [String: Any]) -> PromptBlockModel? {
        guard let blockID = payload["block_id"] as? String else { return nil }
        return PromptBlockModel(
            blockID: blockID,
            title: payload["title"] as? String ?? "Block",
            body: payload["body"] as? String ?? "",
            target: payload["target"] as? String ?? "system",
            enabled: payload["enabled"] as? Bool ?? true
        )
    }

    private func parseJSONObject(from text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object
    }

    private func buildScenarioCasePayload(_ scenarioCase: ScenarioCaseModel) -> [String: Any]? {
        guard let input = parseJSONObject(from: scenarioCase.inputJSON) else { return nil }
        return [
            "case_id": scenarioCase.caseID,
            "title": scenarioCase.title,
            "input": input,
            "context": scenarioCase.contextText.isEmpty ? NSNull() : scenarioCase.contextText,
            "assertions": scenarioCase.assertions.map { assertion in
                var payload: [String: Any] = [
                    "assertion_id": assertion.assertionID,
                    "label": assertion.label,
                    "kind": assertion.kind,
                    "severity": assertion.severity,
                ]
                if !assertion.expectedText.isEmpty {
                    payload["expected_text"] = assertion.expectedText
                }
                if let threshold = assertion.threshold {
                    payload["threshold"] = threshold
                }
                if !assertion.trait.isEmpty {
                    payload["trait"] = assertion.trait
                }
                return payload
            },
            "tags": scenarioCase.tags,
            "notes": scenarioCase.notes,
        ]
    }

    private func appendTranscript(_ role: TranscriptRole, _ title: String, _ body: String) {
        transcript.append(TranscriptEntry(role: role, title: title, body: body))
    }

    private func diffSection(title: String, before: String, after: String) -> String {
        let normalizedBefore = before.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAfter = after.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedBefore == normalizedAfter {
            return ""
        }
        let diff = unifiedDiff(
            from: normalizedBefore,
            to: normalizedAfter,
            fromLabel: "saved/\(title)",
            toLabel: "draft/\(title)"
        )
        return diff.isEmpty ? "" : "\(title)\n\(diff)"
    }

    private func unifiedDiff(from before: String, to after: String, fromLabel: String, toLabel: String) -> String {
        let beforeLines = before.isEmpty ? [] : before.components(separatedBy: .newlines)
        let afterLines = after.isEmpty ? [] : after.components(separatedBy: .newlines)
        let lcs = longestCommonSubsequence(beforeLines, afterLines)
        var lines: [String] = ["--- \(fromLabel)", "+++ \(toLabel)"]
        var beforeIndex = 0
        var afterIndex = 0
        for (commonBefore, commonAfter) in lcs {
            while beforeIndex < commonBefore {
                lines.append("-\(beforeLines[beforeIndex])")
                beforeIndex += 1
            }
            while afterIndex < commonAfter {
                lines.append("+\(afterLines[afterIndex])")
                afterIndex += 1
            }
            lines.append(" \(beforeLines[commonBefore])")
            beforeIndex = commonBefore + 1
            afterIndex = commonAfter + 1
        }
        while beforeIndex < beforeLines.count {
            lines.append("-\(beforeLines[beforeIndex])")
            beforeIndex += 1
        }
        while afterIndex < afterLines.count {
            lines.append("+\(afterLines[afterIndex])")
            afterIndex += 1
        }
        return lines.joined(separator: "\n")
    }

    private func longestCommonSubsequence(_ before: [String], _ after: [String]) -> [(Int, Int)] {
        guard !before.isEmpty, !after.isEmpty else { return [] }
        var table = Array(repeating: Array(repeating: 0, count: after.count + 1), count: before.count + 1)
        for beforeIndex in before.indices.reversed() {
            for afterIndex in after.indices.reversed() {
                if before[beforeIndex] == after[afterIndex] {
                    table[beforeIndex][afterIndex] = table[beforeIndex + 1][afterIndex + 1] + 1
                } else {
                    table[beforeIndex][afterIndex] = max(table[beforeIndex + 1][afterIndex], table[beforeIndex][afterIndex + 1])
                }
            }
        }

        var matches: [(Int, Int)] = []
        var beforeIndex = 0
        var afterIndex = 0
        while beforeIndex < before.count, afterIndex < after.count {
            if before[beforeIndex] == after[afterIndex] {
                matches.append((beforeIndex, afterIndex))
                beforeIndex += 1
                afterIndex += 1
            } else if table[beforeIndex + 1][afterIndex] >= table[beforeIndex][afterIndex + 1] {
                beforeIndex += 1
            } else {
                afterIndex += 1
            }
        }
        return matches
    }
}
