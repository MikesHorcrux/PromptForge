import SwiftUI

private let emberAccent = Color(red: 0.84, green: 0.47, blue: 0.18)
private let parchmentTint = Color(red: 0.96, green: 0.94, blue: 0.90)

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
        .frame(minWidth: 1380, minHeight: 900)
        .sheet(isPresented: $model.showSettings) {
            SettingsSheet()
                .environmentObject(model)
        }
    }

    private var onboardingView: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    parchmentTint,
                    emberAccent.opacity(0.12),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 18) {
                Text("PromptForge")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                Text("A native prompt studio for writing with an agent, testing behavior, and reviewing changes before you ship.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 620, alignment: .leading)

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

                Text("Forgie guides onboarding, editing, scenario checks, and review. Open a PromptForge project to begin.")
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
            .padding(36)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var workspaceView: some View {
        NavigationSplitView {
            sidebarView
        } detail: {
            detailView
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Workspace", selection: $model.selectedWorkspaceMode) {
                    ForEach(PromptWorkspaceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
            }

            ToolbarItemGroup {
                Button("Quick Check") {
                    model.runQuickBenchmark()
                }
                .disabled(model.selectedPrompt == nil)

                Button("Run Suite") {
                    model.runScenarioReview()
                }
                .disabled(model.selectedPrompt == nil || model.selectedSuite == nil)

                Button("Playground") {
                    model.runPlayground()
                }
                .disabled(model.selectedPrompt == nil)

                Button("Review") {
                    model.showReview()
                }
                .disabled(model.reviews.isEmpty)

                Button("Settings") {
                    model.openSettings()
                }
            }
        }
    }

    private var sidebarView: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text(model.projectName)
                    .font(.headline)
                Text(model.projectPath ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Button("New Prompt") {
                        model.createPromptShortcut()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("New Suite") {
                        model.createScenarioShortcut()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(16)

            List {
                Section("Prompts") {
                    ForEach(model.prompts) { prompt in
                        Button {
                            Task {
                                await model.openPrompt(prompt.version, announce: true)
                            }
                        } label: {
                            PromptSidebarRow(prompt: prompt, isSelected: model.selectedPrompt == prompt.version)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section("Scenario Suites") {
                    ForEach(model.scenarioSuites) { suite in
                        Button {
                            model.selectSuite(suite.suiteID)
                            model.showTests()
                        } label: {
                            SidebarMetaRow(
                                title: suite.name,
                                subtitle: "\(suite.cases.count) cases",
                                isSelected: model.selectedSuiteID == suite.suiteID && model.selectedWorkspaceMode == .tests
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section("Recent Reviews") {
                    ForEach(Array(model.reviews.suffix(8).reversed())) { review in
                        Button {
                            model.selectedReviewID = review.reviewID
                            model.selectedReviewCaseID = review.cases.first?.caseID
                            model.showReview()
                        } label: {
                            SidebarMetaRow(
                                title: review.suiteName,
                                subtitle: review.createdAt,
                                isSelected: model.selectedReviewID == review.reviewID && model.selectedWorkspaceMode == .review
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .background(parchmentTint.opacity(0.25))
    }

    @ViewBuilder
    private var detailView: some View {
        if model.selectedPrompt == nil {
            emptyPromptView
        } else {
            switch model.selectedWorkspaceMode {
            case .studio:
                studioView
            case .tests:
                testsView
            case .review:
                reviewView
            }
        }
    }

    private var emptyPromptView: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Select a Prompt")
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text("Open a prompt to work in Studio, manage scenario suites, or review the latest change.")
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

    private var studioView: some View {
        HSplitView {
            StudioChatPane()
                .environmentObject(model)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    StudioHeaderCard()
                        .environmentObject(model)
                    PromptCanvasCard()
                        .environmentObject(model)
                    PlaygroundCard()
                        .environmentObject(model)
                    BuilderActionsCard()
                        .environmentObject(model)
                }
                .padding(20)
            }
            .frame(minWidth: 620)
        }
    }

    private var testsView: some View {
        Group {
            if model.activeScenarioSuite != nil {
                HSplitView {
                    ScenarioCaseNavigator()
                        .environmentObject(model)
                        .frame(minWidth: 280, idealWidth: 320)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            ScenarioSuiteCard()
                                .environmentObject(model)
                            ScenarioCaseEditorCard()
                                .environmentObject(model)
                        }
                        .padding(20)
                    }
                    .frame(minWidth: 640)
                }
            } else {
                PanelCard(title: "Scenario Suites") {
                    Text("Select or create a suite from the sidebar.")
                        .foregroundStyle(.secondary)
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private var reviewView: some View {
        Group {
            if let review = model.latestReview {
                HSplitView {
                    List(selection: Binding(
                        get: { model.selectedReviewCaseID },
                        set: { model.selectedReviewCaseID = $0 }
                    )) {
                        ForEach(review.cases) { reviewCase in
                            ReviewCaseRow(reviewCase: reviewCase)
                                .tag(Optional(reviewCase.caseID))
                        }
                    }
                    .frame(minWidth: 260, idealWidth: 280)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            PanelCard(title: review.suiteName) {
                                HStack(spacing: 10) {
                                    SoftBadge(label: "Review", value: review.reviewID)
                                    SoftBadge(label: "Revision", value: review.revisionID.isEmpty ? "--" : review.revisionID)
                                    SoftBadge(label: "Delta", value: review.scoreDelta.map { String(format: "%+.2f", $0) } ?? "--")
                                }
                            }

                            if let reviewCase = model.selectedReviewCase {
                                ReviewCaseDetail(reviewCase: reviewCase)
                            } else {
                                PanelCard(title: "Case Detail") {
                                    Text("Select a case from the left to inspect outputs and assertions.")
                                        .foregroundStyle(.secondary)
                                }
                            }

                            PanelCard(title: "Decision") {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("End every review with a decision.")
                                        .foregroundStyle(.secondary)
                                    HStack(spacing: 10) {
                                        Button("Keep Iterating") {
                                            model.recordIterateDecision()
                                        }
                                        .buttonStyle(.bordered)

                                        Button("Promote to Baseline") {
                                            model.promoteCurrentCandidate()
                                        }
                                        .buttonStyle(.borderedProminent)
                                    }
                                    if !model.decisions.isEmpty {
                                        Divider()
                                        ForEach(model.decisions.suffix(4).reversed()) { decision in
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(decision.summary)
                                                    .font(.caption.weight(.semibold))
                                                Text("\(decision.status)  |  \(decision.createdAt)")
                                                    .font(.caption2.monospaced())
                                                    .foregroundStyle(.secondary)
                                                if !decision.rationale.isEmpty {
                                                    Text(decision.rationale)
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(20)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    Text("No Review Yet")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("Run a scenario suite to generate a review with regressions, diffs, and decisions.")
                        .foregroundStyle(.secondary)
                    Button("Run Selected Suite") {
                        model.runScenarioReview()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.selectedSuite == nil)
                }
                .padding(30)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }
}

private struct PromptSidebarRow: View {
    let prompt: PromptSummaryModel
    let isSelected: Bool

    var body: some View {
        SidebarMetaRow(
            title: prompt.name,
            subtitle: prompt.version,
            isSelected: isSelected
        )
    }
}

private struct SidebarMetaRow: View {
    let title: String
    let subtitle: String
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.body.weight(.semibold))
                Spacer()
                if isSelected {
                    Circle()
                        .fill(emberAccent)
                        .frame(width: 7, height: 7)
                }
            }
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }
}

private struct StudioHeaderCard: View {
    @EnvironmentObject private var model: PromptForgeAppModel

    var body: some View {
        PanelCard(title: model.currentPromptName.isEmpty ? (model.selectedPrompt ?? "Prompt") : model.currentPromptName) {
            VStack(alignment: .leading, spacing: 10) {
                Text(model.selectedPrompt ?? "")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Text(model.promptDraft.purpose.isEmpty ? "Define what this prompt is for and how you will know it is working." : model.promptDraft.purpose)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    SoftBadge(label: "Provider", value: model.providerLine)
                    SoftBadge(label: "Session", value: model.sessionLine)
                    SoftBadge(label: "Quick score", value: model.latestScoreLine)
                    SoftBadge(label: "Baseline", value: model.promptDraft.baselinePromptRef.isEmpty ? (model.selectedPrompt ?? "--") : model.promptDraft.baselinePromptRef)
                }
                if model.promptHasUnsavedChanges {
                    Text("Autosave is local to the draft. Create a revision by running a check or saving the workspace.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let notice = model.promptSaveNotice, !notice.isEmpty {
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct StudioChatPane: View {
    @EnvironmentObject private var model: PromptForgeAppModel

    var body: some View {
        VStack(spacing: 0) {
            PanelCard(title: "Forgie") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ask for prompt changes, run a quick check, inspect failures, or explain a regression.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let pending = model.pendingProposal {
                        HStack {
                            Text("Pending proposal \(pending.proposalID)")
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Button("Apply") {
                                model.submitText("/apply")
                            }
                            Button("Discard") {
                                model.submitText("/discard")
                            }
                        }
                    }
                }
            }
            .padding([.top, .horizontal], 16)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(model.transcript) { entry in
                            TranscriptBubble(entry: entry)
                                .id(entry.id)
                        }
                    }
                    .padding(16)
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
                TextField("Ask Forgie to edit, explain, or review the prompt", text: $model.draftMessage, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1 ... 5)
                    .onSubmit {
                        model.submitDraft()
                    }
                HStack {
                    Text("Use normal language. Slash commands remain available for power use.")
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
        }
        .frame(minWidth: 360, idealWidth: 390)
        .background(parchmentTint.opacity(0.18))
    }
}

private struct PromptCanvasCard: View {
    @EnvironmentObject private var model: PromptForgeAppModel

    var body: some View {
        PanelCard(title: "Prompt Canvas") {
            VStack(alignment: .leading, spacing: 16) {
                LabeledTextEditor(label: "Purpose", text: $model.promptDraft.purpose, minHeight: 80, font: .system(.body, design: .default))
                LabeledTextEditor(label: "Expected Behavior", text: $model.promptDraft.expectedBehavior, minHeight: 90, font: .system(.body, design: .default))
                LabeledTextEditor(label: "Success Criteria", text: $model.promptDraft.successCriteria, minHeight: 90, font: .system(.body, design: .default))

                HStack(spacing: 12) {
                    LabeledField(label: "Baseline Prompt", text: $model.promptDraft.baselinePromptRef)
                    LabeledField(label: "Owner", text: $model.promptDraft.owner)
                    LabeledField(label: "Audience", text: $model.promptDraft.audience)
                }

                LabeledField(label: "Primary Scenario Suites", text: primarySuitesBinding)

                HStack(spacing: 12) {
                    LabeledField(label: "Agent Model", text: $model.promptDraft.builderAgentModel)
                    LabeledField(label: "Permission Mode", text: $model.promptDraft.builderPermissionMode)
                    LabeledField(label: "Research Policy", text: $model.promptDraft.researchPolicy)
                }

                LabeledTextEditor(label: "Release Notes", text: $model.promptDraft.releaseNotes, minHeight: 70, font: .system(.body, design: .default))
                PromptTextEditorCard(title: "System Prompt", text: $model.promptDraft.systemPrompt)
                PromptTextEditorCard(title: "User Template", text: $model.promptDraft.userTemplate)

                HStack(spacing: 10) {
                    Button("Save Workspace") {
                        model.savePromptWorkspace()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Quick Check") {
                        model.runQuickBenchmark()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var primarySuitesBinding: Binding<String> {
        Binding(
            get: {
                model.promptDraft.primaryScenarioSuites.joined(separator: ", ")
            },
            set: { newValue in
                model.promptDraft.primaryScenarioSuites = newValue
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        )
    }
}

private struct PlaygroundCard: View {
    @EnvironmentObject private var model: PromptForgeAppModel

    var body: some View {
        PanelCard(title: "Playground") {
            VStack(alignment: .leading, spacing: 12) {
                LabeledTextEditor(label: "Input JSON", text: $model.playgroundInputJSON, minHeight: 170, font: .system(.caption, design: .monospaced))
                LabeledTextEditor(label: "Context", text: $model.playgroundContext, minHeight: 70, font: .system(.body, design: .default))
                HStack(spacing: 12) {
                    Stepper("Samples: \(model.playgroundSampleCount)", value: $model.playgroundSampleCount, in: 1 ... 5)
                    Spacer()
                    Button("Add to Suite") {
                        model.promotePlaygroundInputToScenario()
                    }
                    .buttonStyle(.bordered)

                    Button("Run Playground") {
                        model.runPlayground()
                    }
                    .buttonStyle(.borderedProminent)
                }

                if let run = model.latestPlaygroundRun {
                    Divider()
                    Text("Candidate")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(run.candidateSamples) { sample in
                        PlaygroundSampleCard(title: "Sample \(sample.sampleID)", sample: sample)
                    }
                    if !run.baselineSamples.isEmpty {
                        Text("Baseline")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)
                        ForEach(run.baselineSamples) { sample in
                            PlaygroundSampleCard(title: "Baseline \(sample.sampleID)", sample: sample)
                        }
                    }
                }
            }
        }
    }
}

private struct BuilderActionsCard: View {
    @EnvironmentObject private var model: PromptForgeAppModel

    var body: some View {
        PanelCard(title: "Builder Activity") {
            if model.builderActions.isEmpty {
                Text("Forgie has not recorded any builder actions yet.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.builderActions.suffix(8).reversed()) { action in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(action.title)
                                    .font(.caption.weight(.semibold))
                                Spacer()
                                Text(action.kind)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            if !action.details.isEmpty {
                                Text(action.details)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if !action.files.isEmpty {
                                Text(action.files.joined(separator: ", "))
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct ScenarioCaseNavigator: View {
    @EnvironmentObject private var model: PromptForgeAppModel

    var body: some View {
        VStack(spacing: 0) {
            PanelCard(title: "Cases") {
                VStack(alignment: .leading, spacing: 10) {
                    if let suite = model.activeScenarioSuite {
                        Text("\(suite.cases.count) cases in \(suite.name)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        Button("New Case") {
                            model.createScenarioCase()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Duplicate") {
                            model.duplicateSelectedScenarioCase()
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.selectedScenarioCase == nil)
                    }
                }
            }
            .padding([.top, .horizontal], 16)

            List(selection: Binding(
                get: { model.selectedScenarioCaseID },
                set: { model.selectedScenarioCaseID = $0 }
            )) {
                if let suite = model.activeScenarioSuite {
                    ForEach(suite.cases) { scenarioCase in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(scenarioCase.title.isEmpty ? scenarioCase.caseID : scenarioCase.title)
                                .font(.body.weight(.semibold))
                            Text(scenarioCase.caseID)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        .tag(Optional(scenarioCase.caseID))
                    }
                }
            }
        }
        .background(parchmentTint.opacity(0.16))
    }
}

private struct ScenarioSuiteCard: View {
    @EnvironmentObject private var model: PromptForgeAppModel

    var body: some View {
        PanelCard(title: model.activeScenarioSuite?.name ?? "Scenario Suite") {
            VStack(alignment: .leading, spacing: 12) {
                LabeledField(label: "Suite Name", text: suiteBinding(\.name))
                LabeledTextEditor(label: "Description", text: suiteBinding(\.description), minHeight: 80, font: .system(.body, design: .default))
                LabeledField(label: "Linked Prompts", text: linkedPromptsBinding)

                HStack(spacing: 10) {
                    if let suite = model.activeScenarioSuite {
                        SoftBadge(label: "Cases", value: "\(suite.cases.count)")
                        SoftBadge(label: "Suite ID", value: suite.suiteID)
                    }
                    Spacer()
                    Button("Run Selected Suite") {
                        model.runScenarioReview()
                    }
                    .buttonStyle(.bordered)
                    Button("Save Suite") {
                        model.saveScenarioSuite()
                    }
                    .buttonStyle(.borderedProminent)
                }

                if let scenarioNotice = model.scenarioNotice, !scenarioNotice.isEmpty {
                    Text(scenarioNotice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func suiteBinding(_ keyPath: WritableKeyPath<ScenarioSuiteModel, String>) -> Binding<String> {
        Binding(
            get: {
                model.scenarioDraft?[keyPath: keyPath] ?? model.activeScenarioSuite?[keyPath: keyPath] ?? ""
            },
            set: { newValue in
                guard var suite = model.scenarioDraft ?? model.activeScenarioSuite else { return }
                suite[keyPath: keyPath] = newValue
                model.scenarioDraft = suite
            }
        )
    }

    private var linkedPromptsBinding: Binding<String> {
        Binding(
            get: {
                (model.scenarioDraft ?? model.activeScenarioSuite)?.linkedPrompts.joined(separator: ", ") ?? ""
            },
            set: { newValue in
                guard var suite = model.scenarioDraft ?? model.activeScenarioSuite else { return }
                suite.linkedPrompts = newValue
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                model.scenarioDraft = suite
            }
        )
    }
}

private struct ScenarioCaseEditorCard: View {
    @EnvironmentObject private var model: PromptForgeAppModel
    private let assertionKinds = [
        "required_string",
        "forbidden_string",
        "required_section",
        "max_words",
        "trait_minimum",
        "max_latency_ms",
        "max_total_tokens",
    ]
    private let assertionSeverities = ["info", "warn", "fail"]

    var body: some View {
        PanelCard(title: model.selectedScenarioCase?.title.isEmpty == false ? (model.selectedScenarioCase?.title ?? "Scenario Case") : "Scenario Case") {
            if let scenarioCase = model.selectedScenarioCase {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        LabeledField(label: "Title", text: caseBinding(\.title))
                        LabeledField(label: "Case ID", text: .constant(scenarioCase.caseID))
                    }
                    HStack(spacing: 10) {
                        Button("Add Assertion") {
                            model.addAssertionToSelectedCase()
                        }
                        .buttonStyle(.bordered)
                        Button("Delete Case") {
                            model.deleteSelectedScenarioCase()
                        }
                        .buttonStyle(.bordered)
                    }

                    LabeledField(label: "Tags", text: tagsBinding)
                    LabeledTextEditor(label: "Context", text: caseBinding(\.contextText), minHeight: 70, font: .system(.body, design: .default))
                    LabeledTextEditor(label: "Notes", text: caseBinding(\.notes), minHeight: 70, font: .system(.body, design: .default))
                    LabeledTextEditor(label: "Input JSON", text: caseBinding(\.inputJSON), minHeight: 180, font: .system(.caption, design: .monospaced))

                    PanelCard(title: "Assertions") {
                        if scenarioCase.assertions.isEmpty {
                            Text("Add assertions to define required content, token ceilings, or tone checks.")
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(Array(scenarioCase.assertions.enumerated()), id: \.element.id) { index, assertion in
                                    VStack(alignment: .leading, spacing: 10) {
                                        HStack {
                                            Text(assertion.assertionID)
                                                .font(.caption.monospaced())
                                                .foregroundStyle(.secondary)
                                            Spacer()
                                            Button("Remove") {
                                                removeAssertion(at: index)
                                            }
                                            .buttonStyle(.borderless)
                                        }
                                        LabeledField(label: "Label", text: assertionBinding(index: index, keyPath: \.label))
                                        HStack(spacing: 12) {
                                            LabeledRow(label: "Kind") {
                                                Picker("Kind", selection: assertionBinding(index: index, keyPath: \.kind)) {
                                                    ForEach(assertionKinds, id: \.self) { kind in
                                                        Text(kind).tag(kind)
                                                    }
                                                }
                                                .pickerStyle(.menu)
                                            }
                                            LabeledRow(label: "Severity") {
                                                Picker("Severity", selection: assertionBinding(index: index, keyPath: \.severity)) {
                                                    ForEach(assertionSeverities, id: \.self) { severity in
                                                        Text(severity).tag(severity)
                                                    }
                                                }
                                                .pickerStyle(.segmented)
                                            }
                                        }
                                        HStack(spacing: 12) {
                                            LabeledField(label: "Expected Text", text: assertionBinding(index: index, keyPath: \.expectedText))
                                            LabeledField(label: "Trait", text: assertionBinding(index: index, keyPath: \.trait))
                                            LabeledField(label: "Threshold", text: assertionThresholdBinding(index: index))
                                        }
                                    }
                                    .padding(12)
                                    .background(.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
                                }
                            }
                        }
                    }
                }
            } else {
                Text("Select a case to edit its input, notes, and assertions.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func caseBinding(_ keyPath: WritableKeyPath<ScenarioCaseModel, String>) -> Binding<String> {
        Binding(
            get: {
                model.selectedScenarioCase?[keyPath: keyPath] ?? ""
            },
            set: { newValue in
                guard var suite = model.scenarioDraft ?? model.activeScenarioSuite,
                      let caseID = model.selectedScenarioCaseID,
                      let caseIndex = suite.cases.firstIndex(where: { $0.caseID == caseID })
                else {
                    return
                }
                suite.cases[caseIndex][keyPath: keyPath] = newValue
                model.scenarioDraft = suite
            }
        )
    }

    private var tagsBinding: Binding<String> {
        Binding(
            get: {
                model.selectedScenarioCase?.tags.joined(separator: ", ") ?? ""
            },
            set: { newValue in
                guard var suite = model.scenarioDraft ?? model.activeScenarioSuite,
                      let caseID = model.selectedScenarioCaseID,
                      let caseIndex = suite.cases.firstIndex(where: { $0.caseID == caseID })
                else {
                    return
                }
                suite.cases[caseIndex].tags = newValue
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                model.scenarioDraft = suite
            }
        )
    }

    private func assertionBinding(index: Int, keyPath: WritableKeyPath<ScenarioAssertionModel, String>) -> Binding<String> {
        Binding(
            get: {
                guard let scenarioCase = model.selectedScenarioCase, scenarioCase.assertions.indices.contains(index) else { return "" }
                return scenarioCase.assertions[index][keyPath: keyPath]
            },
            set: { newValue in
                guard var suite = model.scenarioDraft ?? model.activeScenarioSuite,
                      let caseID = model.selectedScenarioCaseID,
                      let caseIndex = suite.cases.firstIndex(where: { $0.caseID == caseID }),
                      suite.cases[caseIndex].assertions.indices.contains(index)
                else {
                    return
                }
                suite.cases[caseIndex].assertions[index][keyPath: keyPath] = newValue
                model.scenarioDraft = suite
            }
        )
    }

    private func assertionThresholdBinding(index: Int) -> Binding<String> {
        Binding(
            get: {
                guard let scenarioCase = model.selectedScenarioCase, scenarioCase.assertions.indices.contains(index) else { return "" }
                if let threshold = scenarioCase.assertions[index].threshold {
                    return String(format: "%.2f", threshold)
                }
                return ""
            },
            set: { newValue in
                guard var suite = model.scenarioDraft ?? model.activeScenarioSuite,
                      let caseID = model.selectedScenarioCaseID,
                      let caseIndex = suite.cases.firstIndex(where: { $0.caseID == caseID }),
                      suite.cases[caseIndex].assertions.indices.contains(index)
                else {
                    return
                }
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                suite.cases[caseIndex].assertions[index].threshold = trimmed.isEmpty ? nil : Double(trimmed)
                model.scenarioDraft = suite
            }
        )
    }

    private func removeAssertion(at index: Int) {
        guard var suite = model.scenarioDraft ?? model.activeScenarioSuite,
              let caseID = model.selectedScenarioCaseID,
              let caseIndex = suite.cases.firstIndex(where: { $0.caseID == caseID }),
              suite.cases[caseIndex].assertions.indices.contains(index)
        else {
            return
        }
        suite.cases[caseIndex].assertions.remove(at: index)
        model.scenarioDraft = suite
    }
}

private struct PlaygroundSampleCard: View {
    let title: String
    let sample: PlaygroundSampleModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("\(sample.totalTokens) tok  |  \(sample.latencyMS)ms")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            Text(sample.outputText.isEmpty ? "No output." : sample.outputText)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
        .padding(12)
        .background(.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct ReviewCaseRow: View {
    let reviewCase: ReviewCaseModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(reviewCase.title)
                    .font(.body.weight(.semibold))
                Spacer()
                if reviewCase.regression {
                    Text("Regressed")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.red)
                } else if reviewCase.flaky {
                    Text("Flaky")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
            Text(reviewCase.caseID)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct ReviewCaseDetail: View {
    let reviewCase: ReviewCaseModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PanelCard(title: reviewCase.title) {
                HStack(spacing: 10) {
                    SoftBadge(label: "Candidate", value: reviewCase.candidateScore.map { String(format: "%.2f", $0) } ?? "--")
                    SoftBadge(label: "Baseline", value: reviewCase.baselineScore.map { String(format: "%.2f", $0) } ?? "--")
                    SoftBadge(label: "Status", value: reviewCase.regression ? "Regressed" : (reviewCase.flaky ? "Flaky" : "Stable"))
                }
            }

            HStack(alignment: .top, spacing: 18) {
                LabeledReadOnlyCode(label: "Baseline Output", text: reviewCase.baselineOutput.isEmpty ? "No baseline output." : reviewCase.baselineOutput)
                LabeledReadOnlyCode(label: "Candidate Output", text: reviewCase.candidateOutput.isEmpty ? "No candidate output." : reviewCase.candidateOutput)
            }

            LabeledReadOnlyCode(label: "Diff", text: reviewCase.diffPreview.isEmpty ? "No diff preview." : reviewCase.diffPreview)

            PanelCard(title: "Assertions") {
                VStack(alignment: .leading, spacing: 8) {
                    if reviewCase.assertions.isEmpty {
                        Text("No explicit suite assertions for this case.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(reviewCase.assertions) { assertion in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(assertion.label)
                                        .font(.caption.weight(.semibold))
                                    Spacer()
                                    Text(assertion.status)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(assertion.status == "failed" ? .red : (assertion.status == "warn" ? .orange : .secondary))
                                }
                                Text(assertion.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if !reviewCase.hardFailReasons.isEmpty {
                        Divider()
                        Text("Hard fail reasons: \(reviewCase.hardFailReasons.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !reviewCase.likelyChangedFiles.isEmpty {
                        Text("Likely changed files: \(reviewCase.likelyChangedFiles.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                    builderSection
                    authSection
                }
                .padding(24)
            }
            .frame(minWidth: 820, minHeight: 720)
            .background(parchmentTint.opacity(0.35))
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
            Text(model.isOnboarding ? "Set up providers, default models, and how Forgie should work in this project." : "Update project defaults, model choices, and builder-agent behavior.")
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
            TextField("Full suite dataset", text: $model.settingsDraft.fullEvaluationDataset)
            Stepper("Quick check repeats: \(model.settingsDraft.quickBenchmarkRepeats)", value: $model.settingsDraft.quickBenchmarkRepeats, in: 1 ... 5)
            Stepper("Full suite repeats: \(model.settingsDraft.fullEvaluationRepeats)", value: $model.settingsDraft.fullEvaluationRepeats, in: 1 ... 5)
        }
    }

    private var providerSection: some View {
        SettingsCard(title: model.isOnboarding ? "2. Models" : "Models") {
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
            TextField("Builder agent model", text: $model.settingsDraft.agentModel)
        }
    }

    private var builderSection: some View {
        SettingsCard(title: model.isOnboarding ? "3. Forgie" : "Forgie") {
            TextField("Permission mode", text: $model.settingsDraft.builderPermissionMode)
            TextField("Research policy", text: $model.settingsDraft.builderResearchPolicy)
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
                .background(.white.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
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
        .background(.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.black.opacity(0.05), lineWidth: 1)
        )
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
        .background(.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 16))
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
                .background(.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

private struct LabeledReadOnlyCode: View {
    let label: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LabeledField: View {
    let label: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(label, text: $text)
                .textFieldStyle(.roundedBorder)
        }
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
                .background(.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
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

private struct SoftBadge: View {
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
        .background(.white.opacity(0.45), in: Capsule())
    }
}
