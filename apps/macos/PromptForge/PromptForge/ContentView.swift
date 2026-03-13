import SwiftUI

enum WorkspaceNavigatorSelection: Hashable {
    case promptFile(String)
    case playground
    case caseSet(String)
    case review(String)
}

struct ContentView: View {
    @EnvironmentObject private var model: PromptForgeAppModel
    @State private var workspaceSelection: WorkspaceNavigatorSelection?

    var body: some View {
        Group {
            if model.projectPath == nil {
                onboardingView
            } else {
                workspaceView
            }
        }
        .frame(minWidth: 1540, minHeight: 900)
        .tint(appAccent)
        .sheet(isPresented: $model.showSettings) {
            SettingsSheet()
                .environmentObject(model)
        }
        .sheet(isPresented: $model.showCommandBar) {
            CommandPaletteSheet()
                .environmentObject(model)
        }
    }

    private var onboardingView: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("PromptForge")
                .font(.system(size: 34, weight: .semibold))
            Text("Open a project, edit prompts, run tests, and review changes.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 560, alignment: .leading)

            HStack(spacing: 12) {
                Button("Open Project") {
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

            if let errorText = model.launchError, !errorText.isEmpty {
                Text(errorText)
                    .foregroundStyle(.red)
                    .padding(12)
                    .frame(maxWidth: 520, alignment: .leading)
                    .background(panelBackground, in: RoundedRectangle(cornerRadius: 10))
            }

            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ForgeAmbientBackground().ignoresSafeArea())
    }

    private var workspaceView: some View {
        HStack(spacing: 0) {
            sidebarView
                .frame(width: 260)

            Divider()

            GeometryReader { proxy in
                let detailWidth = proxy.size.width
                let showChat = model.selectedPrompt != nil
                let showInspector = detailWidth >= 1180
                let chatWidth = showChat ? (detailWidth >= 1380 ? CGFloat(360) : CGFloat(320)) : CGFloat.zero
                let inspectorWidth = showInspector ? (detailWidth >= 1420 ? CGFloat(320) : CGFloat(292)) : CGFloat.zero

                VStack(spacing: 0) {
                    WorkspaceTopBar(selection: resolvedSelection)
                        .environmentObject(model)
                    Divider()
                    HStack(spacing: 0) {
                        if showChat {
                            StudioChatPane()
                                .environmentObject(model)
                                .frame(width: chatWidth)
                            Divider()
                        }

                        workspaceMainView
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        if showInspector {
                            Divider()
                            WorkspaceInspectorPane(selection: resolvedSelection)
                                .environmentObject(model)
                                .frame(width: inspectorWidth)
                        }
                    }
                    .background(canvasBackground)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(ForgeAmbientBackground().ignoresSafeArea())
        .onAppear {
            ensureValidSelection()
        }
        .onChange(of: model.selectedPrompt) { _, _ in
            ensureValidSelection()
        }
        .onChange(of: model.promptFiles) { _, _ in
            ensureValidSelection()
        }
        .onChange(of: model.scenarioSuites.map(\.suiteID)) { _, _ in
            ensureValidSelection()
        }
        .onChange(of: model.reviews.map(\.reviewID)) { _, _ in
            ensureValidSelection()
        }
        .onChange(of: model.selectedWorkspaceMode) { _, mode in
            alignSelection(to: mode)
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
                    Button("Open") {
                        model.chooseProjectFolder()
                    }
                    .buttonStyle(.bordered)

                    Button("New Prompt") {
                        model.createPromptShortcut()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(16)
            .background(sidebarBackground)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    NavigatorSection(title: "Prompts") {
                        ForEach(model.prompts) { prompt in
                            VStack(alignment: .leading, spacing: 4) {
                                Button {
                                    Task {
                                        await model.openPrompt(prompt.version, announce: true)
                                        ensureValidSelection(preferred: .promptFile("system.md"))
                                    }
                                } label: {
                                    NavigatorRow(
                                        title: prompt.name,
                                        subtitle: prompt.version,
                                        systemImage: "shippingbox",
                                        isSelected: model.selectedPrompt == prompt.version && isPromptSelection(resolvedSelection),
                                        indentation: 0
                                    )
                                }
                                .buttonStyle(.plain)

                                if prompt.version == model.selectedPrompt {
                                    ForEach(promptFileItems, id: \.self) { file in
                                        Button {
                                            setSelection(.promptFile(file))
                                        } label: {
                                            NavigatorRow(
                                                title: promptFileTitle(for: file),
                                                subtitle: promptFileSubtitle(for: file),
                                                systemImage: iconName(forPromptFile: file),
                                                isSelected: resolvedSelection == .promptFile(file),
                                                indentation: 18
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }

                                    Button {
                                        setSelection(.playground)
                                    } label: {
                                        NavigatorRow(
                                            title: "Try Input",
                                            subtitle: "Scratch input sandbox",
                                            systemImage: "play.square",
                                            isSelected: resolvedSelection == .playground,
                                            indentation: 18
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    NavigatorSection(title: "Tests") {
                        if model.scenarioSuites.isEmpty {
                            NavigatorPlaceholder(text: "No saved tests yet")
                        } else {
                            ForEach(model.scenarioSuites) { suite in
                                Button {
                                    setSelection(.caseSet(suite.suiteID))
                                } label: {
                                    NavigatorRow(
                                        title: suite.name,
                                        subtitle: "\(suite.cases.count) test case(s)",
                                        systemImage: "checklist",
                                        isSelected: resolvedSelection == .caseSet(suite.suiteID),
                                        indentation: 0
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    NavigatorSection(title: "Review") {
                        if model.reviews.isEmpty {
                            NavigatorPlaceholder(text: "Run tests to create a review")
                        } else {
                            ForEach(model.reviews.reversed()) { review in
                                Button {
                                    setSelection(.review(review.reviewID))
                                } label: {
                                    NavigatorRow(
                                        title: review.suiteName,
                                        subtitle: review.reviewID,
                                        systemImage: "doc.text.magnifyingglass",
                                        isSelected: resolvedSelection == .review(review.reviewID),
                                        indentation: 0
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(12)
            }

            Divider()

            HStack(spacing: 8) {
                Button("Commands") {
                    model.openCommandBar()
                }
                .buttonStyle(.bordered)

                Button("Settings") {
                    model.openSettings()
                }
                .buttonStyle(.bordered)
            }
            .padding(16)
            .background(sidebarBackground)
        }
        .background(sidebarBackground)
    }

    @ViewBuilder
    private var workspaceMainView: some View {
        if model.selectedPrompt == nil {
            emptyPromptView
        } else {
            switch resolvedSelection {
            case .promptFile(let file):
                PromptWorkspacePane(selection: file)
                    .environmentObject(model)
            case .playground:
                PlaygroundWorkspacePane()
                    .environmentObject(model)
            case .caseSet:
                CasesWorkspacePane()
                    .environmentObject(model)
            case .review:
                ResultsWorkspacePane()
                    .environmentObject(model)
            case nil:
                emptyPromptView
            }
        }
    }

    private var emptyPromptView: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Select a Prompt")
                .font(.system(size: 28, weight: .semibold))
            Text("This project does not have a prompt yet. Create one or import an existing prompt to open the IDE.")
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button("New Prompt") {
                    model.createPromptShortcut()
                }
                .buttonStyle(.bordered)

                Button("Import Prompt") {
                    model.importPromptPack()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var resolvedSelection: WorkspaceNavigatorSelection? {
        if let workspaceSelection, selectionAvailable(workspaceSelection) {
            return workspaceSelection
        }
        return defaultSelection(for: model.selectedWorkspaceMode)
    }

    private var promptFileItems: [String] {
        let preferredOrder = ["system.md", "user_template.md", "prompt.json"]
        let available = Set(model.promptFiles)
        return preferredOrder.filter { available.contains($0) }
    }

    private func promptFileTitle(for file: String) -> String {
        switch file {
        case "system.md":
            return "System Prompt"
        case "user_template.md":
            return "User Template"
        case "prompt.json":
            return "Prompt Settings"
        default:
            return file
        }
    }

    private func promptFileSubtitle(for file: String) -> String {
        switch file {
        case "system.md":
            return "Core instructions"
        case "user_template.md":
            return "Rendered with each case"
        case "prompt.json":
            return "Metadata and ownership"
        default:
            return "Project file"
        }
    }

    private func iconName(forPromptFile file: String) -> String {
        switch file {
        case "system.md":
            return "doc.plaintext"
        case "user_template.md":
            return "curlybraces.square"
        case "prompt.json":
            return "slider.horizontal.3"
        default:
            return "doc"
        }
    }

    private func isPromptSelection(_ selection: WorkspaceNavigatorSelection?) -> Bool {
        switch selection {
        case .promptFile, .playground:
            return true
        default:
            return false
        }
    }

    private func selectionAvailable(_ selection: WorkspaceNavigatorSelection) -> Bool {
        switch selection {
        case .promptFile(let file):
            return model.selectedPrompt != nil && promptFileItems.contains(file)
        case .playground:
            return model.selectedPrompt != nil
        case .caseSet(let suiteID):
            return model.scenarioSuites.contains(where: { $0.suiteID == suiteID })
        case .review(let reviewID):
            return model.reviews.contains(where: { $0.reviewID == reviewID })
        }
    }

    private func defaultSelection(for mode: PromptWorkspaceMode? = nil) -> WorkspaceNavigatorSelection? {
        let effectiveMode = mode ?? model.selectedWorkspaceMode
        switch effectiveMode {
        case .studio:
            return model.selectedPrompt == nil ? nil : .promptFile(promptFileItems.first ?? "system.md")
        case .tests:
            if let suiteID = model.selectedSuite?.suiteID ?? model.scenarioSuites.first?.suiteID {
                return .caseSet(suiteID)
            }
            return model.selectedPrompt == nil ? nil : .promptFile(promptFileItems.first ?? "system.md")
        case .review:
            if let reviewID = model.latestReview?.reviewID {
                return .review(reviewID)
            }
            if let suiteID = model.selectedSuite?.suiteID ?? model.scenarioSuites.first?.suiteID {
                return .caseSet(suiteID)
            }
            return model.selectedPrompt == nil ? nil : .promptFile(promptFileItems.first ?? "system.md")
        }
    }

    private func ensureValidSelection(preferred: WorkspaceNavigatorSelection? = nil) {
        let candidate = preferred ?? workspaceSelection
        if let candidate, selectionAvailable(candidate) {
            workspaceSelection = candidate
            applyMode(for: candidate)
            return
        }
        let fallback = defaultSelection(for: model.selectedWorkspaceMode)
        workspaceSelection = fallback
        if let fallback {
            applyMode(for: fallback)
        }
    }

    private func alignSelection(to mode: PromptWorkspaceMode) {
        guard resolvedSelection == nil || modeForSelection(resolvedSelection) != mode else { return }
        workspaceSelection = defaultSelection(for: mode)
    }

    private func setSelection(_ selection: WorkspaceNavigatorSelection) {
        workspaceSelection = selection
        applyMode(for: selection)
    }

    private func applyMode(for selection: WorkspaceNavigatorSelection) {
        switch selection {
        case .promptFile, .playground:
            model.selectedWorkspaceMode = .studio
        case .caseSet(let suiteID):
            model.selectSuite(suiteID)
            model.selectedWorkspaceMode = .tests
        case .review(let reviewID):
            model.selectedReviewID = reviewID
            if let review = model.reviews.first(where: { $0.reviewID == reviewID }) {
                model.selectedReviewCaseID = review.cases.first?.caseID
            }
            model.selectedWorkspaceMode = .review
        }
    }

    private func modeForSelection(_ selection: WorkspaceNavigatorSelection?) -> PromptWorkspaceMode? {
        guard let selection else { return nil }
        switch selection {
        case .promptFile, .playground:
            return .studio
        case .caseSet:
            return .tests
        case .review:
            return .review
        }
    }
}
