import SwiftUI

struct WorkspaceInspectorPane: View {
    @EnvironmentObject private var model: PromptForgeAppModel
    let selection: WorkspaceNavigatorSelection?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                switch selection {
                case .promptFile, .playground:
                    promptInspector
                case .caseSet:
                    casesInspector
                case .review:
                    reviewInspector
                case nil:
                    PanelCard(title: "Inspector") {
                        Text("Open a prompt, test suite, or review to inspect its metadata here.")
                            .foregroundStyle(.secondary)
                    }
                }

                if model.selectedPrompt != nil {
                    ActivityFeedCard()
                        .environmentObject(model)
                }
            }
            .padding(16)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(sidebarBackground)
    }

    @ViewBuilder
    private var promptInspector: some View {
        PanelCard(title: "Prompt Status") {
            VStack(alignment: .leading, spacing: 12) {
                Text(model.currentPromptDescription.isEmpty ? "Keep the prompt tight here: baseline, current score, and the small amount of metadata you actually need while editing." : model.currentPromptDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    SoftBadge(label: "Prompt", value: model.selectedPrompt ?? "--")
                    SoftBadge(label: "Baseline", value: model.promptDraft.baselinePromptRef.isEmpty ? (model.selectedPrompt ?? "--") : model.promptDraft.baselinePromptRef)
                    SoftBadge(label: "Score", value: model.latestScoreLine)
                }

                HStack(spacing: 10) {
                    SoftBadge(label: "Provider", value: model.providerLine)
                    SoftBadge(label: "Tests", value: "\(model.scenarioSuites.count)")
                    SoftBadge(label: "Reviews", value: "\(model.reviews.count)")
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Open Folder")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(model.promptRootPath.isEmpty ? "No prompt selected." : model.promptRootPath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if let notice = model.promptSaveNotice, !notice.isEmpty {
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }

        BuilderControlsCard()
            .environmentObject(model)
    }

    @ViewBuilder
    private var casesInspector: some View {
        PanelCard(title: "Tests") {
            VStack(alignment: .leading, spacing: 12) {
                if let suite = model.activeScenarioSuite {
                    Text("This saved test suite is the product contract for `\(suite.name)`. Edit the suite here, keep the selected case in the editor, and run it when you want a real answer on regressions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Select a test suite from the navigator to inspect and edit it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Button("Run Tests") {
                        model.runScenarioReview()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.activeScenarioSuite == nil || model.isBusy)

                    Button("Save") {
                        model.saveScenarioSuite()
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.activeScenarioSuite == nil || model.isBusy)
                }

                Divider()

                ScenarioSuiteEditor()
                    .environmentObject(model)
            }
        }
    }

    @ViewBuilder
    private var reviewInspector: some View {
        if let review = model.latestReview {
            PanelCard(title: "Run Summary") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("This review compares the current candidate against the baseline on the selected test suite.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        SoftBadge(label: "Suite", value: review.suiteName)
                        SoftBadge(label: "Revision", value: review.revisionID)
                        SoftBadge(label: "Created", value: review.createdAt)
                    }

                    HStack(spacing: 10) {
                        SoftBadge(label: "Score Delta", value: review.scoreDelta.map { String(format: "%.2f", $0) } ?? "--")
                        SoftBadge(label: "Pass Rate Delta", value: review.passRateDelta.map { String(format: "%.2f", $0) } ?? "--")
                        SoftBadge(label: "Tests", value: "\(review.cases.count)")
                    }

                    HStack(spacing: 8) {
                        Button("Ship Candidate") {
                            model.promoteCurrentCandidate()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isBusy)

                        Button("Keep Iterating") {
                            model.recordIterateDecision()
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.isBusy)
                    }
                }
            }

            PanelCard(title: "Decision History") {
                if model.decisions.isEmpty {
                    Text("No decisions recorded for this prompt yet.")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(model.decisions.reversed().prefix(6))) { decision in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(decision.summary)
                                        .font(.caption.weight(.semibold))
                                    Spacer()
                                    Text(decision.status)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(decision.status == "promoted" ? appAccent : .secondary)
                                }
                                if !decision.rationale.isEmpty {
                                    Text(decision.rationale)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(decision.createdAt)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        } else {
            PanelCard(title: "Run Summary") {
                Text("Run a test suite first to populate review results and decisions.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct PromptWorkspacePane: View {
    @EnvironmentObject private var model: PromptForgeAppModel
    let selection: String

    var body: some View {
        promptDocument
            .background(canvasBackground)
    }

    @ViewBuilder
    private var promptDocument: some View {
        switch selection {
        case "system.md":
            EditablePromptFileSurface(
                fileName: selection,
                subtitle: "Core instructions for the active prompt.",
                text: $model.promptDraft.systemPrompt,
                diffText: model.promptDiffPreview,
                notice: model.promptHasUnsavedChanges ? "Draft has local changes." : (model.promptSaveNotice ?? "")
            )
        case "user_template.md":
            EditablePromptFileSurface(
                fileName: selection,
                subtitle: "Template rendered with each dataset or case input.",
                text: $model.promptDraft.userTemplate,
                diffText: model.promptDiffPreview,
                notice: model.promptHasUnsavedChanges ? "Draft has local changes." : (model.promptSaveNotice ?? "")
            )
        case "prompt.json":
            PromptMetadataDocument()
                .environmentObject(model)
        default:
            ReadOnlyPromptFileSurface(
                fileName: selection,
                rootPath: model.promptRootPath,
                note: "This file is shown directly from the prompt on disk. PromptForge currently edits the main authoring files and metadata from this workspace."
            )
        }
    }
}

struct PlaygroundWorkspacePane: View {
    @EnvironmentObject private var model: PromptForgeAppModel

    var body: some View {
        VStack(spacing: 0) {
            DocumentHeaderBar(
                title: "Try Input",
                subtitle: "Scratch input sandbox for the active prompt.",
                accessory: model.latestPlaygroundRun.map { "Last run \($0.createdAt)" }
            )
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PlaygroundCard()
                        .environmentObject(model)
                }
                .padding(16)
            }
            .background(canvasBackground)
        }
        .background(canvasBackground)
    }
}

struct CasesWorkspacePane: View {
    @EnvironmentObject private var model: PromptForgeAppModel

    var body: some View {
        if model.activeScenarioSuite == nil {
            VStack(alignment: .leading, spacing: 14) {
                Text("No Test Suite Selected")
                    .font(.title2.weight(.semibold))
                Text("Pick a test suite from the navigator or create one from the command bar.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(24)
        } else {
            HSplitView {
                ScenarioCaseNavigator()
                    .environmentObject(model)
                    .frame(minWidth: 290, idealWidth: 320)

                VStack(spacing: 0) {
                    DocumentHeaderBar(
                        title: model.selectedScenarioCase?.title.isEmpty == false ? (model.selectedScenarioCase?.title ?? "Case") : (model.selectedScenarioCase?.caseID ?? "Case"),
                        subtitle: "Edit the selected case. Its checks define the saved test contract for this prompt.",
                        accessory: model.selectedScenarioCase?.caseID
                    )
                    Divider()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            ScenarioCaseEditor()
                                .environmentObject(model)
                        }
                        .padding(16)
                    }
                    .background(canvasBackground)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(canvasBackground)
        }
    }
}

struct ResultsWorkspacePane: View {
    @EnvironmentObject private var model: PromptForgeAppModel

    var body: some View {
        if let review = model.latestReview {
            HSplitView {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Review Cases")
                            .font(.headline)
                        Text("Review `\(review.suiteName)` case-by-case. Regressions and flaky outputs are called out here before you ship or keep iterating.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)

                    List(selection: Binding(
                        get: { model.selectedReviewCaseID },
                        set: { model.selectedReviewCaseID = $0 }
                    )) {
                        ForEach(review.cases) { reviewCase in
                            ReviewCaseRow(reviewCase: reviewCase)
                                .tag(Optional(reviewCase.caseID))
                        }
                    }
                }
                .frame(minWidth: 300, idealWidth: 340)
                .background(sidebarBackground)

                VStack(spacing: 0) {
                    DocumentHeaderBar(
                        title: model.selectedReviewCase?.title ?? review.suiteName,
                        subtitle: "Compare baseline and candidate behavior for the selected case.",
                        accessory: model.selectedReviewCase?.caseID ?? review.reviewID
                    )
                    Divider()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if let reviewCase = model.selectedReviewCase {
                                ReviewCaseDetail(reviewCase: reviewCase)
                            } else {
                                PanelCard(title: "Review Detail") {
                                    Text("Select a review case to inspect its diff, outputs, and checks.")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(16)
                    }
                    .background(canvasBackground)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(canvasBackground)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                Text("No Review Yet")
                    .font(.title2.weight(.semibold))
                Text("Run a test suite to compare the current prompt against the baseline and inspect regressions here.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(24)
        }
    }
}

struct PromptMetadataDocument: View {
    @EnvironmentObject private var model: PromptForgeAppModel

    var body: some View {
        VStack(spacing: 0) {
            DocumentHeaderBar(
                title: "Prompt Settings",
                subtitle: "Metadata, ownership, baseline, and release notes for this prompt.",
                accessory: "prompt.json"
            )
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PanelCard(title: "Prompt Metadata") {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("PromptForge stores the authoring brief and release metadata alongside the prompt files. Edit the product context here and keep the source instructions in `system.md` and `user_template.md`.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            LabeledTextEditor(label: "Purpose", text: $model.promptDraft.purpose, minHeight: 80, font: .system(.body, design: .default))
                            LabeledTextEditor(label: "Expected Behavior", text: $model.promptDraft.expectedBehavior, minHeight: 90, font: .system(.body, design: .default))
                            LabeledTextEditor(label: "Success Criteria", text: $model.promptDraft.successCriteria, minHeight: 90, font: .system(.body, design: .default))

                            HStack(spacing: 12) {
                                LabeledField(label: "Baseline Prompt", text: $model.promptDraft.baselinePromptRef)
                                LabeledField(label: "Owner", text: $model.promptDraft.owner)
                                LabeledField(label: "Audience", text: $model.promptDraft.audience)
                            }

                            LabeledField(label: "Primary Test Suites", text: primarySuitesBinding)
                            LabeledTextEditor(label: "Release Notes", text: $model.promptDraft.releaseNotes, minHeight: 90, font: .system(.body, design: .default))
                        }
                    }
                }
                .padding(16)
            }
            .background(canvasBackground)
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

struct EditablePromptFileSurface: View {
    let fileName: String
    let subtitle: String
    @Binding var text: String
    let diffText: String
    let notice: String

    var body: some View {
        VStack(spacing: 0) {
            DocumentHeaderBar(title: fileName, subtitle: subtitle, accessory: notice.isEmpty ? nil : notice)
            Divider()
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(canvasBackground)

            if !diffText.isEmpty {
                Divider()
                VStack(spacing: 0) {
                    HStack {
                        Text("Draft Diff")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    Divider()

                    ScrollView {
                        Text(diffText)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                    }
                }
                .frame(minHeight: 170, idealHeight: 210)
                .background(sidebarBackground)
            }
        }
        .background(canvasBackground)
    }
}

struct ReadOnlyPromptFileSurface: View {
    let fileName: String
    let rootPath: String
    let note: String

    var body: some View {
        VStack(spacing: 0) {
            DocumentHeaderBar(title: fileName, subtitle: "Read-only file from the active prompt.", accessory: nil)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PanelCard(title: "About This File") {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    LabeledReadOnlyCode(label: fileName, text: fileContents)
                }
                .padding(16)
            }
            .background(canvasBackground)
        }
    }

    private var fileContents: String {
        guard !rootPath.isEmpty else {
            return "Prompt root path is not available."
        }
        let path = URL(fileURLWithPath: rootPath).appendingPathComponent(fileName).path
        guard FileManager.default.fileExists(atPath: path) else {
            return "File not found at \(path)"
        }
        return (try? String(contentsOfFile: path, encoding: .utf8)) ?? "Unable to read \(fileName)."
    }
}

struct DocumentHeaderBar: View {
    let title: String
    let subtitle: String
    let accessory: String?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let accessory, !accessory.isEmpty {
                Text(accessory)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(canvasBackground)
    }
}
