import Charts
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: PromptForgeAppModel

    var body: some View {
        Group {
            if model.projectPath == nil {
                onboardingView
            } else {
                workspaceView
            }
        }
        .frame(minWidth: 1360, minHeight: 880)
        .sheet(isPresented: $model.showSettings) {
            SettingsSheet()
                .environmentObject(model)
        }
    }

    private var onboardingView: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("PromptForge")
                .font(.system(size: 34, weight: .bold, design: .rounded))
            Text("Chat-first prompt engineering with staged edits, benchmarks, and local model access.")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Open a PromptForge project folder to start.")
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("Choose Project Folder") {
                    model.chooseProjectFolder()
                }
                .buttonStyle(.borderedProminent)

                if let savedProject = model.savedProjectHint {
                    Button("Reopen \(savedProject)") {
                        Task {
                            await model.openProject(at: savedProject)
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }

            Text("The first project open starts guided onboarding for providers, models, API keys, and Codex login.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let errorText = model.launchError, !errorText.isEmpty {
                Text(errorText)
                    .foregroundStyle(.red)
                    .padding(12)
                    .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }

            Spacer()
        }
        .padding(32)
        .background(
            LinearGradient(
                colors: [.black.opacity(0.98), .blue.opacity(0.20)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var workspaceView: some View {
        NavigationSplitView {
            sidebarView
        } detail: {
            detailView
                .background(Color.black.opacity(0.96))
        }
        .navigationSplitViewStyle(.balanced)
        .background(Color.black.opacity(0.98))
    }

    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.projectName)
                    .font(.headline)
                Text(model.projectPath ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Button("New Prompt") {
                    model.createPromptShortcut()
                }
                .buttonStyle(.borderedProminent)

                Button("Settings") {
                    model.openSettings()
                }
                .buttonStyle(.bordered)

                Button("Open Project") {
                    model.chooseProjectFolder()
                }
                .buttonStyle(.bordered)
            }

            Text("Prompts")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            List(selection: Binding(
                get: { model.selectedPrompt },
                set: { newValue in
                    guard let newValue else { return }
                    model.showOverview()
                    Task {
                        await model.openPrompt(newValue, announce: true)
                    }
                }
            )) {
                ForEach(model.prompts) { prompt in
                    PromptSidebarRow(
                        prompt: prompt,
                        isSelected: model.selectedPrompt == prompt.version
                    )
                    .tag(Optional(prompt.version))
                }
            }
            .listStyle(.sidebar)

            Spacer()
        }
        .padding(16)
        .background(Color.black.opacity(0.92))
    }

    @ViewBuilder
    private var detailView: some View {
        if model.selectedPrompt == nil {
            emptyPromptView
        } else {
            VStack(spacing: 0) {
                promptHeader
                Divider()
                switch model.selectedWorkspaceMode {
                case .overview:
                    promptOverviewView
                case .editor:
                    promptEditorView
                }
            }
        }
    }

    private var emptyPromptView: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Select a Prompt")
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text("Pick a prompt from the sidebar to open its dashboard, inspect recent behavior, and move into the editor when you want to chat or rewrite it.")
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button("New Prompt") {
                    model.createPromptShortcut()
                }
                .buttonStyle(.borderedProminent)
                Button("Open Settings") {
                    model.openSettings()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var promptHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.currentPromptName.isEmpty ? (model.selectedPrompt ?? "Prompt") : model.currentPromptName)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text(model.selectedPrompt ?? "")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text(model.promptDraft.purpose.isEmpty ? "Add a clear purpose for this prompt so the overview and editor stay grounded." : model.promptDraft.purpose)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text(model.providerLine)
                        .font(.caption.monospaced())
                    Text(model.sessionLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(alignment: .center, spacing: 12) {
                Picker("Mode", selection: $model.selectedWorkspaceMode) {
                    ForEach(PromptWorkspaceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)

                if model.promptHasUnsavedChanges {
                    Text("Unsaved changes")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.orange.opacity(0.10), in: Capsule())
                } else if let notice = model.promptSaveNotice, !notice.isEmpty {
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Run Bench") {
                    model.runQuickBenchmark()
                }
                .buttonStyle(.bordered)

                Button("Full Eval") {
                    model.runFullEvaluation()
                }
                .buttonStyle(.bordered)

                Button("Save Prompt") {
                    model.savePromptWorkspace()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.promptHasUnsavedChanges)
            }

            HStack(spacing: 12) {
                StatusPill(label: "Latest score", value: model.latestScoreLine)
                StatusPill(label: "Delta", value: model.latestDeltaLine)
                StatusPill(label: "Auth", value: model.authLine)
                StatusPill(label: "Dataset", value: model.statusSubtitle)
            }
        }
        .padding(22)
        .background(
            LinearGradient(
                colors: [.blue.opacity(0.16), .black.opacity(0.96)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var promptOverviewView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PromptHeroCard(
                    prompt: model.selectedPrompt,
                    description: model.currentPromptDescription,
                    rootPath: model.promptRootPath,
                    latestScore: model.latestScoreLine,
                    latestDelta: model.latestDeltaLine
                )

                HStack(alignment: .top, spacing: 18) {
                    PromptBriefCard()
                        .environmentObject(model)
                        .frame(maxWidth: .infinity)
                    PromptStructureCard(rootPath: model.promptRootPath, files: model.promptFiles)
                        .frame(width: 300)
                }

                PromptPreviewSection(
                    systemPrompt: model.promptDraft.systemPrompt,
                    userTemplate: model.promptDraft.userTemplate
                )

                HStack(alignment: .top, spacing: 18) {
                    InspectorKeyValueSection(title: "Latest Run", rows: model.benchmarkRows)
                        .frame(maxWidth: 360)
                    BenchmarkHistorySection(
                        prompt: model.selectedPrompt,
                        entries: model.benchmarkHistory,
                        trend: model.benchmarkTrend
                    )
                }

                HStack(alignment: .top, spacing: 18) {
                    InspectorCasesSection(title: "Weak Cases", cases: model.weakCases)
                    InspectorCasesSection(title: "Failures", cases: model.failureCases)
                }

                if !model.recentTranscript.isEmpty {
                    RecentActivitySection(entries: model.recentTranscript)
                }
            }
            .padding(22)
        }
    }

    private var promptEditorView: some View {
        HSplitView {
            EditorChatPane()
                .environmentObject(model)

            PromptEditorPane()
                .environmentObject(model)
                .frame(minWidth: 420, idealWidth: 460, maxWidth: 560)
        }
    }
}

private struct PromptSidebarRow: View {
    let prompt: PromptSummaryModel
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(prompt.version)
                    .font(.system(.body, design: .monospaced))
                Spacer()
                if isSelected {
                    Text("Open")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.blue)
                }
            }
            Text(prompt.name)
                .font(.caption.weight(.semibold))
            Text(prompt.description.isEmpty ? "Prompt package" : prompt.description)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }
}

private struct PromptHeroCard: View {
    let prompt: String?
    let description: String
    let rootPath: String
    let latestScore: String
    let latestDelta: String

    var body: some View {
        PanelCard(title: "Prompt Dashboard") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(prompt ?? "--")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                        Text(description.isEmpty ? "Use the overview to define the purpose and success bar for this prompt before editing its files." : description)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(latestScore)
                            .font(.system(.title3, design: .monospaced, weight: .semibold))
                        Text("delta \(latestDelta)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }

                Text(rootPath.isEmpty ? "Prompt package path unavailable." : rootPath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct PromptBriefCard: View {
    @EnvironmentObject private var model: PromptForgeAppModel

    var body: some View {
        PanelCard(title: "Prompt Intent") {
            VStack(alignment: .leading, spacing: 14) {
                LabeledTextEditor(
                    label: "Purpose",
                    text: $model.promptDraft.purpose,
                    minHeight: 80,
                    font: .system(.body, design: .default)
                )
                LabeledTextEditor(
                    label: "Expected Behavior",
                    text: $model.promptDraft.expectedBehavior,
                    minHeight: 110,
                    font: .system(.body, design: .default)
                )
                LabeledTextEditor(
                    label: "Success Criteria",
                    text: $model.promptDraft.successCriteria,
                    minHeight: 110,
                    font: .system(.body, design: .default)
                )

                HStack {
                    if let notice = model.promptSaveNotice, !notice.isEmpty {
                        Text(notice)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Edit Prompt") {
                        model.showEditor()
                    }
                    .buttonStyle(.bordered)
                    Button("Save Overview") {
                        model.savePromptWorkspace()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.promptHasUnsavedChanges)
                }
            }
        }
    }
}

private struct PromptStructureCard: View {
    let rootPath: String
    let files: [String]

    var body: some View {
        PanelCard(title: "Package Layout") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Each prompt lives as a structured folder with prompt intent, prompt files, and schema side by side.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !rootPath.isEmpty {
                    Text(rootPath)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                ForEach(files, id: \.self) { file in
                    HStack {
                        Image(systemName: file == "prompt.json" ? "sidebar.left" : "doc.text")
                            .foregroundStyle(file == "prompt.json" ? .blue : .secondary)
                        Text(file)
                            .font(.caption.monospaced())
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
                }
                if files.isEmpty {
                    Text("No prompt files found yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct PromptPreviewSection: View {
    let systemPrompt: String
    let userTemplate: String

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            PromptCodeCard(title: "System Prompt", text: systemPrompt)
            PromptCodeCard(title: "User Template", text: userTemplate)
        }
    }
}

private struct PromptCodeCard: View {
    let title: String
    let text: String

    var body: some View {
        PanelCard(title: title) {
            Text(text.isEmpty ? "Nothing loaded yet." : text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct RecentActivitySection: View {
    let entries: [TranscriptEntry]

    var body: some View {
        PanelCard(title: "Recent Activity") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(entries) { entry in
                    TranscriptBubble(entry: entry)
                }
            }
        }
    }
}

private struct EditorChatPane: View {
    @EnvironmentObject private var model: PromptForgeAppModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Chat Editor")
                            .font(.system(.title3, design: .rounded, weight: .bold))
                        Text("Use normal messages like you would with an agent. It can answer, stage edits, or run evaluations from chat.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Back to Overview") {
                        model.showOverview()
                    }
                    .buttonStyle(.bordered)
                }
                if let pending = model.pendingProposal {
                    HStack {
                        Text("Pending proposal \(pending.proposalID)")
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Button("/apply") {
                            model.submitText("/apply")
                        }
                        Button("/discard") {
                            model.submitText("/discard")
                        }
                    }
                    .padding(10)
                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(18)
            .background(Color.black.opacity(0.98))

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(model.transcript) { entry in
                            TranscriptBubble(entry: entry)
                                .id(entry.id)
                        }
                    }
                    .padding(18)
                }
                .onChange(of: model.transcript.count) { _, _ in
                    if let lastID = model.transcript.last?.id {
                        withAnimation {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                TextField(
                    "Ask for changes, analysis, or evaluations in plain language",
                    text: $model.draftMessage,
                    axis: .vertical
                )
                .textFieldStyle(.roundedBorder)
                .lineLimit(1 ... 5)
                .onSubmit {
                    model.submitDraft()
                }

                HStack {
                    Text("/help for commands")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if model.isBusy {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Button("Send") {
                        model.submitDraft()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(16)
            .background(Color.black.opacity(0.96))
        }
    }
}

private struct PromptEditorPane: View {
    @EnvironmentObject private var model: PromptForgeAppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PanelCard(title: "Prompt Intent") {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledTextEditor(
                            label: "Purpose",
                            text: $model.promptDraft.purpose,
                            minHeight: 80,
                            font: .system(.body, design: .default)
                        )
                        LabeledTextEditor(
                            label: "Expected Behavior",
                            text: $model.promptDraft.expectedBehavior,
                            minHeight: 100,
                            font: .system(.body, design: .default)
                        )
                        LabeledTextEditor(
                            label: "Success Criteria",
                            text: $model.promptDraft.successCriteria,
                            minHeight: 100,
                            font: .system(.body, design: .default)
                        )
                    }
                }

                PromptTextEditorCard(title: "System Prompt", text: $model.promptDraft.systemPrompt)
                PromptTextEditorCard(title: "User Template", text: $model.promptDraft.userTemplate)
                PromptStructureCard(rootPath: model.promptRootPath, files: model.promptFiles)
            }
            .padding(18)
        }
        .background(Color.black.opacity(0.92))
    }
}

private struct PromptTextEditorCard: View {
    let title: String
    @Binding var text: String

    var body: some View {
        PanelCard(title: title) {
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 220)
                .padding(10)
                .background(.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

private struct BenchmarkHistorySection: View {
    let prompt: String?
    let entries: [BenchmarkHistoryEntry]
    let trend: [BenchmarkTrendPoint]

    var body: some View {
        PanelCard(title: prompt.map { "\($0) Benchmark History" } ?? "Benchmark History") {
            VStack(alignment: .leading, spacing: 12) {
                if trend.isEmpty {
                    Text("No benchmark history yet. Run `Run Bench` or `Full Eval` to populate this view.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Chart(trend) { point in
                        LineMark(
                            x: .value("Revision", point.revisionID),
                            y: .value("Score", point.score)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(.blue)

                        PointMark(
                            x: .value("Revision", point.revisionID),
                            y: .value("Score", point.score)
                        )
                        .foregroundStyle(.white)
                    }
                    .frame(height: 170)
                    .chartYScale(domain: 0 ... 5)

                    ForEach(entries.reversed()) { entry in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(entry.revisionID)
                                    .font(.caption.weight(.semibold))
                                Spacer()
                                Text(entry.score.map { String(format: "%.2f / 5", $0) } ?? "--")
                                    .font(.caption.monospaced())
                            }
                            Text("\(entry.source)  |  delta \(entry.scoreDeltaVsBaseline.map { String(format: "%+.2f", $0) } ?? "--")  |  pass \(entry.passRate.map { String(format: "%.0f%%", $0 * 100) } ?? "--")  |  hard fail \(entry.hardFailRate.map { String(format: "%.0f%%", $0 * 100) } ?? "--")")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                            if let fullScore = entry.fullScore {
                                Text("full eval \(String(format: "%.2f / 5", fullScore))")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.green)
                            }
                            if !entry.note.isEmpty {
                                Text(entry.note)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(12)
                        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
    }
}

private struct SettingsSheet: View {
    @EnvironmentObject private var model: PromptForgeAppModel

    private let providers = ["openai", "openrouter", "codex"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    onboardingHeader
                    projectSection
                    providerSection
                    authSection
                }
                .padding(24)
            }
            .frame(minWidth: 760, minHeight: 680)
            .background(Color.black.opacity(0.97))
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
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var onboardingHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.isOnboarding ? "Welcome to PromptForge" : "Settings")
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text(model.isOnboarding ? "Walk through project defaults, secure provider auth, and Codex login from one place." : "Update project defaults, inspect provider connections, and manage auth without leaving the app.")
                .foregroundStyle(.secondary)
            if let notice = model.settingsNotice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.green)
                    .padding(10)
                    .background(.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            }
            if let error = model.settingsError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(10)
                    .background(.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var projectSection: some View {
        SettingsCard(title: model.isOnboarding ? "1. Project" : "Project") {
            TextField("Project name", text: $model.settingsDraft.projectName)
            TextField("Quick benchmark dataset", text: $model.settingsDraft.quickBenchmarkDataset)
            TextField("Full evaluation dataset", text: $model.settingsDraft.fullEvaluationDataset)
        }
    }

    private var providerSection: some View {
        SettingsCard(title: model.isOnboarding ? "2. Defaults" : "Defaults") {
            LabeledRow(label: "Generation provider") {
                Picker("Generation provider", selection: $model.settingsDraft.provider) {
                    ForEach(providers, id: \.self) { provider in
                        Text(provider.capitalized).tag(provider)
                    }
                }
                .pickerStyle(.segmented)
            }
            LabeledRow(label: "Judge provider") {
                Picker("Judge provider", selection: $model.settingsDraft.judgeProvider) {
                    ForEach(providers, id: \.self) { provider in
                        Text(provider.capitalized).tag(provider)
                    }
                }
                .pickerStyle(.segmented)
            }
            TextField("Generation model", text: $model.settingsDraft.generationModel)
            TextField("Judge model", text: $model.settingsDraft.judgeModel)
        }
    }

    private var authSection: some View {
        SettingsCard(title: model.isOnboarding ? "3. Connections" : "Connections") {
            ForEach(model.connectionStatuses) { status in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(status.label)
                            .font(.headline)
                        Spacer()
                        Text(status.ready ? "Connected" : "Needs auth")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(status.ready ? .green : .orange)
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
                            .buttonStyle(.bordered)
                        }
                    }
                    if status.id == "openrouter" {
                        HStack {
                            SecureField("Paste a new OpenRouter API key", text: $model.openRouterKeyDraft)
                            Button("Clear") {
                                model.clearKey(kind: "openrouter")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    if status.id == "codex" {
                        HStack {
                            Button("Authenticate Codex") {
                                model.launchCodexLogin()
                            }
                            .buttonStyle(.borderedProminent)
                            Button("Refresh Status") {
                                model.openSettings(onboarding: model.isOnboarding)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .padding(12)
                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

private struct PanelCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content
        }
        .padding(16)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content
        }
        .padding(16)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct LabeledRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
    }
}

private struct LabeledTextEditor: View {
    let label: String
    @Binding var text: String
    let minHeight: CGFloat
    let font: Font

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextEditor(text: $text)
                .font(font)
                .frame(minHeight: minHeight)
                .padding(10)
                .background(.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

private struct TranscriptBubble: View {
    let entry: TranscriptEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(entry.role.tint)
            Text(entry.body)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(entry.role.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(entry.role.border, lineWidth: 1)
        )
    }
}

private struct StatusPill: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospaced())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.white.opacity(0.04), in: Capsule())
    }
}

private struct InspectorKeyValueSection: View {
    let title: String
    let rows: [(String, String)]

    var body: some View {
        PanelCard(title: title) {
            if rows.isEmpty {
                Text("No benchmark summary yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        HStack(alignment: .top) {
                            Text(row.0)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(row.1)
                                .font(.caption.monospaced())
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
            }
        }
    }
}

private struct InspectorCasesSection: View {
    let title: String
    let cases: [CaseIssue]

    var body: some View {
        PanelCard(title: title) {
            if cases.isEmpty {
                Text("No cases to show.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(cases) { issue in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(issue.caseID)
                                .font(.caption.weight(.semibold))
                            Text("score \(issue.score)  |  hard fail \(issue.hardFailRate)")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                            Text(issue.reasons)
                                .font(.caption)
                            Text(issue.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .background(.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
    }
}
