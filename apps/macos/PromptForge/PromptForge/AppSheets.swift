import SwiftUI

struct CommandPaletteSheet: View {
    @EnvironmentObject private var model: PromptForgeAppModel
    @State private var query: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Command Bar")
                    .font(.system(size: 24, weight: .semibold))
                Spacer()
                Button("Close") {
                    model.closeCommandBar()
                }
                .buttonStyle(.bordered)
            }

            TextField("Search commands", text: $query)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    if let first = filteredCommands.first(where: \.isEnabled) {
                        run(first)
                    }
                }

            List(filteredCommands) { command in
                Button {
                    run(command)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(command.title)
                            .font(.body.weight(.semibold))
                        Text(command.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!command.isEnabled)
            }
        }
        .padding(24)
        .frame(minWidth: 560, minHeight: 420)
        .background(canvasBackground)
    }

    private var filteredCommands: [CommandPaletteItem] {
        let all = commandItems()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return all
        }
        return all.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed) ||
            $0.subtitle.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private func commandItems() -> [CommandPaletteItem] {
        var commands: [CommandPaletteItem] = [
            .init(id: "settings", title: "Open Settings", subtitle: "Project, models, auth, and agent defaults", isEnabled: true),
            .init(id: "new_prompt", title: "New Prompt", subtitle: "Create a new prompt", isEnabled: true),
            .init(id: "new_suite", title: "New Test Suite", subtitle: "Create a saved prompt test suite", isEnabled: model.selectedPrompt != nil),
            .init(id: "save_workspace", title: "Save Prompt", subtitle: "Persist prompt metadata and prompt files", isEnabled: model.selectedPrompt != nil),
            .init(id: "quick_check", title: "Quick Check", subtitle: "Run the quick test lane on the active prompt", isEnabled: model.selectedPrompt != nil),
            .init(id: "run_suite", title: "Run Tests", subtitle: "Run the selected test suite and open review", isEnabled: model.selectedPrompt != nil && model.selectedSuite != nil),
            .init(id: "playground", title: "Try Input", subtitle: "Generate samples for the current scratch input", isEnabled: model.selectedPrompt != nil),
        ]
        commands.append(contentsOf: model.prompts.map { prompt in
            CommandPaletteItem(
                id: "open:\(prompt.version)",
                title: "Open \(prompt.name)",
                subtitle: prompt.version,
                isEnabled: true
            )
        })
        return commands
    }

    private func run(_ command: CommandPaletteItem) {
        guard command.isEnabled else { return }
        switch command.id {
        case "settings":
            model.openSettings()
        case "new_prompt":
            model.createPromptShortcut()
        case "new_suite":
            model.createScenarioShortcut()
        case "save_workspace":
            model.savePromptWorkspace()
        case "quick_check":
            model.runQuickBenchmark()
        case "run_suite":
            model.runScenarioReview()
        case "playground":
            model.runPlayground()
        default:
            if command.id.hasPrefix("open:") {
                let prompt = String(command.id.dropFirst("open:".count))
                Task {
                    await model.openPrompt(prompt, announce: true)
                }
            }
        }
        model.closeCommandBar()
    }
}

struct CommandPaletteItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let isEnabled: Bool
}

struct SettingsSheet: View {
    @EnvironmentObject private var model: PromptForgeAppModel

    private let providers = PromptForgeProviderCatalog.builtInProviders
    private let permissionModes = ["proposal_only", "auto_apply"]
    private let researchPolicies = ["prompt_only", "allow_external"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    onboardingHeader
                    projectSection
                    providerSection
                    builderSection
                    authSection
                }
                .padding(24)
            }
            .frame(minWidth: 820, minHeight: 720)
            .background(canvasBackground)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(model.isOnboarding ? "Later" : "Close") {
                        model.showSettings = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.isOnboarding ? "Finish Setup" : "Save") {
                        model.saveSettings()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var onboardingHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.isOnboarding ? "Welcome to PromptForge" : "Settings")
                .font(.system(size: 28, weight: .semibold))
            Text(model.isOnboarding ? "Set up providers, default models, and how the agent should work in this project." : "Update project defaults, model choices, and agent behavior.")
                .foregroundStyle(.secondary)
            if let notice = model.settingsNotice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            if let error = model.settingsError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var projectSection: some View {
        SettingsCard(title: model.isOnboarding ? "1. Project" : "Project") {
            TextField("Project name", text: $model.settingsDraft.projectName)
            TextField("Quick check dataset", text: $model.settingsDraft.quickBenchmarkDataset)
            TextField("Full evaluation dataset", text: $model.settingsDraft.fullEvaluationDataset)
            Stepper("Quick check repeats: \(model.settingsDraft.quickBenchmarkRepeats)", value: $model.settingsDraft.quickBenchmarkRepeats, in: 1 ... 5)
            Stepper("Full evaluation repeats: \(model.settingsDraft.fullEvaluationRepeats)", value: $model.settingsDraft.fullEvaluationRepeats, in: 1 ... 5)
        }
    }

    private var providerSection: some View {
        SettingsCard(title: model.isOnboarding ? "2. Models" : "Models") {
            LabeledRow(label: "Generation provider") {
                Picker("Generation provider", selection: $model.settingsDraft.provider) {
                    ForEach(providers, id: \.self) { provider in
                        Text(provider.displayName).tag(provider.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }
            LabeledRow(label: "Judge provider") {
                Picker("Judge provider", selection: $model.settingsDraft.judgeProvider) {
                    ForEach(providers, id: \.self) { provider in
                        Text(provider.displayName).tag(provider.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }
            TextField("Generation model", text: $model.settingsDraft.generationModel)
            TextField("Judge model", text: $model.settingsDraft.judgeModel)
            TextField("Builder agent model", text: $model.settingsDraft.agentModel)
        }
    }

    private var builderSection: some View {
        SettingsCard(title: model.isOnboarding ? "3. Agent" : "Agent") {
            Picker("Permission mode", selection: $model.settingsDraft.builderPermissionMode) {
                ForEach(permissionModes, id: \.self) { mode in
                    Text(mode.replacingOccurrences(of: "_", with: " ")).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            Picker("Research policy", selection: $model.settingsDraft.builderResearchPolicy) {
                ForEach(researchPolicies, id: \.self) { policy in
                    Text(policy.replacingOccurrences(of: "_", with: " ")).tag(policy)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var authSection: some View {
        SettingsCard(title: model.isOnboarding ? "4. Connections" : "Connections") {
            ForEach(model.connectionStatuses) { status in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(status.label)
                            .font(.headline)
                        Spacer()
                        Text(status.ready ? "Connected" : "Needs auth")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(status.ready ? appAccent : .secondary)
                    }
                    Text(status.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Source: \(status.source)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                    if status.id == "openai" {
                        HStack {
                            SecureField("Paste a new OpenAI API key", text: $model.openAIKeyDraft)
                            Button("Clear") {
                                model.clearKey(kind: "openai")
                            }
                        }
                    }
                    if status.id == "openrouter" {
                        HStack {
                            SecureField("Paste a new OpenRouter API key", text: $model.openRouterKeyDraft)
                            Button("Clear") {
                                model.clearKey(kind: "openrouter")
                            }
                        }
                    }
                    if status.id == "codex" {
                        HStack {
                            Button("Use OpenAI Key") {
                                model.authenticateCodexWithOpenAIKey()
                            }
                            .buttonStyle(.borderedProminent)
                            Button("Device Code") {
                                model.beginCodexDeviceAuth()
                            }
                            .buttonStyle(.bordered)
                            Button("Refresh Status") {
                                model.refreshConnectionStatuses()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .padding(12)
                .background(panelBackground, in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(borderColor, lineWidth: 1)
                )
            }
        }
    }
}
