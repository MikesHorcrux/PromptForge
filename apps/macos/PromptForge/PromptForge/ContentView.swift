import AppKit
import SwiftUI

private func forgeColor(
    lightRed: Double,
    lightGreen: Double,
    lightBlue: Double,
    darkRed: Double,
    darkGreen: Double,
    darkBlue: Double,
    alpha: Double = 1.0
) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        let bestMatch = appearance.bestMatch(from: [.darkAqua, .aqua]) ?? .aqua
        if bestMatch == .darkAqua {
            return NSColor(
                red: darkRed,
                green: darkGreen,
                blue: darkBlue,
                alpha: alpha
            )
        }
        return NSColor(
            red: lightRed,
            green: lightGreen,
            blue: lightBlue,
            alpha: alpha
        )
    })
}

private let appAccent = forgeColor(
    lightRed: 0.84, lightGreen: 0.39, lightBlue: 0.05,
    darkRed: 0.94, darkGreen: 0.52, darkBlue: 0.16
)
private let forgeGlow = forgeColor(
    lightRed: 0.95, lightGreen: 0.66, lightBlue: 0.24,
    darkRed: 0.99, darkGreen: 0.77, darkBlue: 0.43
)
private let panelBackground = forgeColor(
    lightRed: 0.96, lightGreen: 0.92, lightBlue: 0.88,
    darkRed: 0.16, darkGreen: 0.10, darkBlue: 0.08
)
private let sidebarBackground = forgeColor(
    lightRed: 0.92, lightGreen: 0.88, lightBlue: 0.83,
    darkRed: 0.12, darkGreen: 0.08, darkBlue: 0.06
)
private let canvasBackground = forgeColor(
    lightRed: 0.99, lightGreen: 0.97, lightBlue: 0.94,
    darkRed: 0.09, darkGreen: 0.06, darkBlue: 0.05
)
private let inputBackground = forgeColor(
    lightRed: 1.0, lightGreen: 0.98, lightBlue: 0.95,
    darkRed: 0.12, darkGreen: 0.08, darkBlue: 0.06
)
private let borderColor = forgeColor(
    lightRed: 0.79, lightGreen: 0.49, lightBlue: 0.22,
    darkRed: 0.69, darkGreen: 0.38, darkBlue: 0.16,
    alpha: 0.26
)
private let forgeBackdrop = LinearGradient(
    colors: [
        forgeColor(
            lightRed: 0.96, lightGreen: 0.91, lightBlue: 0.82,
            darkRed: 0.17, darkGreen: 0.09, darkBlue: 0.05
        ),
        forgeColor(
            lightRed: 0.98, lightGreen: 0.95, lightBlue: 0.90,
            darkRed: 0.09, darkGreen: 0.06, darkBlue: 0.05
        ),
        forgeColor(
            lightRed: 0.93, lightGreen: 0.89, lightBlue: 0.84,
            darkRed: 0.05, darkGreen: 0.03, darkBlue: 0.03
        ),
    ],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)
private let forgePanelFill = LinearGradient(
    colors: [
        forgeColor(
            lightRed: 0.99, lightGreen: 0.95, lightBlue: 0.91,
            darkRed: 0.21, darkGreen: 0.13, darkBlue: 0.09,
            alpha: 0.98
        ),
        forgeColor(
            lightRed: 0.96, lightGreen: 0.91, lightBlue: 0.86,
            darkRed: 0.14, darkGreen: 0.09, darkBlue: 0.07,
            alpha: 0.98
        ),
    ],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

private struct EmberSpec: Identifiable {
    let id: Int
    let x: CGFloat
    let baseY: CGFloat
    let drift: CGFloat
    let size: CGFloat
    let speed: Double
    let phase: Double
    let opacity: Double
}

private let forgeEmbers: [EmberSpec] = [
    .init(id: 0, x: 0.08, baseY: 0.92, drift: 0.26, size: 4, speed: 0.07, phase: 0.0, opacity: 0.34),
    .init(id: 1, x: 0.14, baseY: 0.88, drift: 0.30, size: 3, speed: 0.09, phase: 1.2, opacity: 0.28),
    .init(id: 2, x: 0.18, baseY: 0.95, drift: 0.22, size: 5, speed: 0.06, phase: 2.4, opacity: 0.32),
    .init(id: 3, x: 0.24, baseY: 0.90, drift: 0.24, size: 3, speed: 0.08, phase: 0.8, opacity: 0.26),
    .init(id: 4, x: 0.30, baseY: 0.94, drift: 0.20, size: 4, speed: 0.05, phase: 1.8, opacity: 0.30),
    .init(id: 5, x: 0.37, baseY: 0.89, drift: 0.28, size: 3, speed: 0.07, phase: 3.2, opacity: 0.22),
    .init(id: 6, x: 0.44, baseY: 0.93, drift: 0.18, size: 5, speed: 0.04, phase: 0.5, opacity: 0.18),
    .init(id: 7, x: 0.52, baseY: 0.91, drift: 0.23, size: 4, speed: 0.08, phase: 2.9, opacity: 0.24),
    .init(id: 8, x: 0.61, baseY: 0.96, drift: 0.17, size: 4, speed: 0.05, phase: 1.1, opacity: 0.20),
    .init(id: 9, x: 0.69, baseY: 0.90, drift: 0.25, size: 3, speed: 0.09, phase: 2.1, opacity: 0.24),
    .init(id: 10, x: 0.77, baseY: 0.93, drift: 0.19, size: 5, speed: 0.06, phase: 0.3, opacity: 0.28),
    .init(id: 11, x: 0.84, baseY: 0.88, drift: 0.32, size: 3, speed: 0.10, phase: 1.7, opacity: 0.22),
    .init(id: 12, x: 0.91, baseY: 0.95, drift: 0.21, size: 4, speed: 0.06, phase: 2.7, opacity: 0.24),
]

private enum WorkspaceNavigatorSelection: Hashable {
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
            Text("Open a project, edit prompts, run checks, and review changes.")
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

                    NavigatorSection(title: "Cases") {
                        if model.scenarioSuites.isEmpty {
                            NavigatorPlaceholder(text: "No saved cases yet")
                        } else {
                            ForEach(model.scenarioSuites) { suite in
                                Button {
                                    setSelection(.caseSet(suite.suiteID))
                                } label: {
                                    NavigatorRow(
                                        title: suite.name,
                                        subtitle: "\(suite.cases.count) case(s)",
                                        systemImage: "checklist",
                                        isSelected: resolvedSelection == .caseSet(suite.suiteID),
                                        indentation: 0
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    NavigatorSection(title: "Results") {
                        if model.reviews.isEmpty {
                            NavigatorPlaceholder(text: "Run cases to create results")
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
            Text("This project does not have a prompt yet. Create one or import an existing prompt pack to open the IDE.")
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
        let ordered = preferredOrder.filter { available.contains($0) }
        return ordered
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

private struct WorkspaceTopBar: View {
    @EnvironmentObject private var model: PromptForgeAppModel
    let selection: WorkspaceNavigatorSelection?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(breadcrumbTitle)
                        .font(.headline)
                    Text(breadcrumbSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                HStack(spacing: 8) {
                    Button("Save") {
                        if case .caseSet = selection {
                            model.saveScenarioSuite()
                        } else {
                            model.savePromptWorkspace()
                        }
                    }
                    .buttonStyle(TopBarActionButtonStyle())
                    .disabled(model.selectedPrompt == nil || model.isBusy)

                    actionButton("Check Prompt", systemImage: "bolt.horizontal", enabled: model.selectedPrompt != nil) {
                        model.runQuickBenchmark()
                    }
                    actionButton("Run Cases", systemImage: "checklist", enabled: model.selectedPrompt != nil && model.selectedSuite != nil) {
                        model.runScenarioReview()
                    }
                    actionButton("Try Input", systemImage: "play.square", enabled: model.selectedPrompt != nil) {
                        model.runPlayground()
                    }
                }

                if model.isBusy {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(model.busyLabel.isEmpty ? "Working" : model.busyLabel)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(appAccent)
                    }
                    .padding(.leading, 4)
                }
            }

            Text(toolbarHelpText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(canvasBackground)
    }

    private var breadcrumbTitle: String {
        switch selection {
        case .promptFile(let file):
            let fileTitle = file == "prompt.json" ? "Prompt Settings" : file
            return "\(model.currentPromptName) / \(fileTitle)"
        case .playground:
            return "\(model.currentPromptName) / Try Input"
        case .caseSet(let suiteID):
            let suiteName = model.scenarioSuites.first(where: { $0.suiteID == suiteID })?.name ?? "Case Set"
            return "\(model.projectName) / scenarios / \(suiteName)"
        case .review(let reviewID):
            let suiteName = model.reviews.first(where: { $0.reviewID == reviewID })?.suiteName ?? "Results"
            return "\(model.projectName) / results / \(suiteName)"
        case nil:
            return model.currentPromptName.isEmpty ? model.projectName : model.currentPromptName
        }
    }

    private var breadcrumbSubtitle: String {
        switch selection {
        case .promptFile:
            return model.promptRootPath
        case .playground:
            return "Scratch input sandbox for \(model.selectedPrompt ?? "--")"
        case .caseSet(let suiteID):
            return model.scenarioSuites.first(where: { $0.suiteID == suiteID })?.suiteID ?? suiteID
        case .review(let reviewID):
            return reviewID
        case nil:
            return model.projectPath ?? ""
        }
    }

    private var toolbarHelpText: String {
        switch selection {
        case .promptFile(let file):
            if file == "system.md" || file == "user_template.md" {
                return "This is the live prompt document. Edit it here, ask Forgie in the next pane, then run checks from the toolbar."
            }
            return "This file is part of the prompt pack. Edit metadata here, use the inspector for context, and run checks from the toolbar."
        case .playground:
            return "Try one-off inputs here before turning them into saved cases. Promote useful examples into Cases when they become part of the product contract."
        case .caseSet:
            return "Case sets are saved product tests. Edit examples and checks here, then run them against the current prompt and the baseline."
        case .review:
            return "Results compares the current prompt against the baseline and shows regressions, diffs, and decision history."
        case nil:
            return "Open a prompt pack from the navigator, edit its files, define saved cases, and inspect results in one workspace."
        }
    }

    private func actionButton(_ title: String, systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(TopBarActionButtonStyle())
        .disabled(!enabled || model.isBusy)
    }
}

private struct NavigatorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
            VStack(alignment: .leading, spacing: 4) {
                content
            }
        }
    }
}

private struct NavigatorRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let isSelected: Bool
    let indentation: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isSelected ? appAccent : .secondary)
                .frame(width: 16, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(Color.primary)
                    .lineLimit(2)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, indentation)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? appAccent.opacity(0.16) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? appAccent.opacity(0.35) : Color.clear, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct NavigatorPlaceholder: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
    }
}

private struct WorkspaceInspectorPane: View {
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
                        Text("Open a prompt pack, case set, or result to inspect its metadata here.")
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
                    SoftBadge(label: "Cases", value: "\(model.scenarioSuites.count)")
                    SoftBadge(label: "Results", value: "\(model.reviews.count)")
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Open Folder")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(model.promptRootPath.isEmpty ? "No prompt pack selected." : model.promptRootPath)
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
        PanelCard(title: "Cases") {
            VStack(alignment: .leading, spacing: 12) {
                if let suite = model.activeScenarioSuite {
                    Text("This saved case set is the product contract for `\(suite.name)`. Edit the suite here, keep the selected case in the editor, and run it when you want a real answer on regressions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Select a case set from the navigator to inspect and edit it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Button("Run Case Set") {
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
                    Text("This result compares the current candidate against the baseline on the selected case set.")
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
                        SoftBadge(label: "Cases", value: "\(review.cases.count)")
                    }

                    HStack(spacing: 8) {
                        Button("Promote Candidate") {
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
                Text("Run a case set first to populate review results and decisions.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct PromptWorkspacePane: View {
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
                note: "This file is shown directly from the prompt pack on disk. PromptForge currently edits the main authoring files and metadata from this workspace."
            )
        }
    }
}

private struct PlaygroundWorkspacePane: View {
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

private struct CasesWorkspacePane: View {
    @EnvironmentObject private var model: PromptForgeAppModel

    var body: some View {
        if model.activeScenarioSuite == nil {
            VStack(alignment: .leading, spacing: 14) {
                Text("No Case Set Selected")
                    .font(.title2.weight(.semibold))
                Text("Pick a case set from the navigator or create one from the command bar.")
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
                        subtitle: "Edit the selected case. Its checks define the saved product contract for this prompt.",
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

private struct ResultsWorkspacePane: View {
    @EnvironmentObject private var model: PromptForgeAppModel

    var body: some View {
        if let review = model.latestReview {
            HSplitView {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Result Cases")
                            .font(.headline)
                        Text("Review `\(review.suiteName)` case-by-case. Regressions and flaky outputs are called out here before you promote or keep iterating.")
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
                                PanelCard(title: "Result Detail") {
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
                Text("No Results Yet")
                    .font(.title2.weight(.semibold))
                Text("Run a case set to compare the current prompt against the baseline and inspect regressions here.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(24)
        }
    }
}

private struct PromptMetadataDocument: View {
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

                            LabeledField(label: "Primary Case Sets", text: primarySuitesBinding)
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

private struct EditablePromptFileSurface: View {
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

private struct ReadOnlyPromptFileSurface: View {
    let fileName: String
    let rootPath: String
    let note: String

    var body: some View {
        VStack(spacing: 0) {
            DocumentHeaderBar(title: fileName, subtitle: "Read-only file from the active prompt pack.", accessory: nil)
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

private struct DocumentHeaderBar: View {
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

private struct ForgeAmbientBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: false)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let glowOpacity = colorScheme == .dark ? 0.28 : 0.14
            let emberOpacity = colorScheme == .dark ? 1.0 : 0.55

            ZStack {
                forgeBackdrop

                RadialGradient(
                    colors: [
                        forgeGlow.opacity(glowOpacity + 0.05 * sin(time * 1.6)),
                        appAccent.opacity(glowOpacity * 0.55),
                        .clear,
                    ],
                    center: .center,
                    startRadius: 18,
                    endRadius: 240
                )
                .frame(width: 420, height: 320)
                .offset(x: 520, y: 320 + 10 * sin(time * 1.9))
                .blur(radius: 10)

                RadialGradient(
                    colors: [
                        appAccent.opacity((colorScheme == .dark ? 0.10 : 0.05) + 0.03 * sin(time * 2.8 + 0.8)),
                        .clear,
                    ],
                    center: .center,
                    startRadius: 8,
                    endRadius: 180
                )
                .frame(width: 280, height: 220)
                .offset(x: -520, y: 360 + 8 * sin(time * 2.2))
                .blur(radius: 18)

                Canvas { context, size in
                    for ember in forgeEmbers {
                        let progress = (time * ember.speed + ember.phase).truncatingRemainder(dividingBy: 1.0)
                        let drift = CGFloat(progress) * ember.drift * size.height
                        let x = size.width * ember.x + CGFloat(sin(time * ember.speed * 9 + ember.phase)) * 14
                        let y = size.height * ember.baseY - drift
                        let pulse = 0.45 + 0.55 * ((sin(time * 5.5 + ember.phase) + 1) / 2)
                        let radius = ember.size * (0.9 + pulse * 0.45)
                        let rect = CGRect(x: x, y: y, width: radius, height: radius)
                        context.fill(Path(ellipseIn: rect), with: .color(forgeGlow.opacity(ember.opacity * pulse * emberOpacity)))
                    }
                }
                .allowsHitTesting(false)
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
                        .fill(appAccent)
                        .frame(width: 6, height: 6)
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

private struct TopBarModeButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(configuration.isPressed ? 0.75 : 0.9))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? appAccent : Color.black.opacity(configuration.isPressed ? 0.08 : 0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? appAccent.opacity(0.35) : borderColor, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .opacity(configuration.isPressed ? 0.96 : 1)
    }
}

private struct TopBarActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(appAccent.opacity(configuration.isPressed ? 0.24 : 0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderColor, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct StudioHeaderCard: View {
    @EnvironmentObject private var model: PromptForgeAppModel

    var body: some View {
        PanelCard(title: model.currentPromptName.isEmpty ? (model.selectedPrompt ?? "Prompt") : model.currentPromptName) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(model.selectedPrompt ?? "")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Text(model.promptDraft.purpose.isEmpty ? "Define what this prompt is for and how you will know it is working." : model.promptDraft.purpose)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    ForgieStatusGlyph(active: model.isBusy)
                }
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

private struct PromptIDEPane: View {
    @EnvironmentObject private var model: PromptForgeAppModel

    var body: some View {
        VSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("prompt.md")
                        .font(.headline)
                    Text(model.selectedPrompt ?? "--")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let notice = model.promptSaveNotice, !notice.isEmpty {
                        Text(notice)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if model.promptHasUnsavedChanges {
                        Text("Unsaved changes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()

                TextEditor(text: $model.promptDraft.systemPrompt)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(canvasBackground)
            }
            .background(canvasBackground)

            if !model.promptDiffPreview.isEmpty {
                VStack(spacing: 0) {
                    HStack {
                        Text("Diff")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    Divider()

                    ScrollView {
                        Text(model.promptDiffPreview)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                    }
                }
                .background(sidebarBackground)
                .frame(minHeight: 180, idealHeight: 220)
            }
        }
        .background(canvasBackground)
    }
}

private struct BuilderControlsCard: View {
    @EnvironmentObject private var model: PromptForgeAppModel
    private let permissionModes = ["proposal_only", "auto_apply"]
    private let researchPolicies = ["prompt_only", "allow_external"]

    var body: some View {
        PanelCard(title: "Forgie") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Forgie the forge fox can either stage edits for review or apply them directly. Keep the controls small and stay focused on the prompt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledField(label: "Agent Model", text: $model.promptDraft.builderAgentModel)

                LabeledRow(label: "Permission Mode") {
                    Picker("Permission Mode", selection: $model.promptDraft.builderPermissionMode) {
                        ForEach(permissionModes, id: \.self) { mode in
                            Text(mode.replacingOccurrences(of: "_", with: " ")).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                }

                LabeledRow(label: "Research Policy") {
                    Picker("Research Policy", selection: $model.promptDraft.researchPolicy) {
                        ForEach(researchPolicies, id: \.self) { policy in
                            Text(policy.replacingOccurrences(of: "_", with: " ")).tag(policy)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Text("Effective tools")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                FlowWrap(items: model.effectiveBuilderTools)
            }
        }
    }
}

private struct StudioChatPane: View {
    @EnvironmentObject private var model: PromptForgeAppModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    HStack(spacing: 10) {
                        ForgieStatusGlyph(active: model.isBusy)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Forgie")
                                .font(.headline)
                            Text("The forge fox for edits, failures, and prompt review. System activity lives in the inspector so this thread stays conversational.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if model.isBusy {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if let pending = model.pendingProposal {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Pending edit")
                                .font(.caption.weight(.semibold))
                            Text(pending.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Button("Apply") {
                            model.submitText("/apply")
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Discard") {
                            model.submitText("/discard")
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(12)
                    .background(inputBackground, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(borderColor, lineWidth: 1)
                    )
                }
            }
            .padding(16)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if conversationEntries.isEmpty {
                            PanelCard(title: "Ask Forgie") {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Try asking Forgie:")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Text("Tighten the tone and make the refund policy clearer.")
                                    Text("Why would case-001 fail?")
                                    Text("Run a quick check and summarize the weak cases.")
                                }
                            }
                        } else {
                            ForEach(conversationEntries) { entry in
                                HStack {
                                    if entry.role == .user {
                                        Spacer(minLength: 40)
                                    }
                                    ChatMessageBubble(entry: entry)
                                        .id(entry.id)
                                    if entry.role != .user {
                                        Spacer(minLength: 40)
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                }
                .onChange(of: conversationEntries.count) { _, _ in
                    if let lastID = conversationEntries.last?.id {
                        withAnimation {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                TextField("Ask Forgie to edit, explain, or review the prompt", text: $model.draftMessage, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(inputBackground, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(borderColor, lineWidth: 1)
                    )
                    .lineLimit(1 ... 5)
                    .onSubmit {
                        model.submitDraft()
                    }
                HStack {
                    Text("Use plain language. Slash commands still work for power use.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Send") {
                        model.submitDraft()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(16)
        }
        .frame(maxHeight: .infinity)
        .background(sidebarBackground)
    }

    private var conversationEntries: [TranscriptEntry] {
        model.transcript.filter { entry in
            entry.role == .user || entry.role == .agent
        }
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

                LabeledTextEditor(label: "Release Notes", text: $model.promptDraft.releaseNotes, minHeight: 70, font: .system(.body, design: .default))
                PromptBlocksCard()
                    .environmentObject(model)
                PromptTextEditorCard(title: "System Prompt", text: $model.promptDraft.systemPrompt)
                PromptTextEditorCard(title: "User Template", text: $model.promptDraft.userTemplate)

                HStack(spacing: 10) {
                    Button("Save Workspace") {
                        model.savePromptWorkspace()
                    }
                    .buttonStyle(.bordered)

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
                    .buttonStyle(.bordered)
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
                            if !action.tools.isEmpty {
                                FlowWrap(items: action.tools)
                            }
                            if !action.files.isEmpty {
                                Text(action.files.joined(separator: ", "))
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            HStack(spacing: 8) {
                                Text(action.permissionMode)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                if action.usedResearch {
                                    Text("external research")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(appAccent)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct PromptBlocksCard: View {
    @EnvironmentObject private var model: PromptForgeAppModel
    private let blockTargets = ["system", "user", "shared"]

    var body: some View {
        PanelCard(title: "Prompt Blocks") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Reusable prompt fragments you can keep alongside the canvas and insert on demand.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Add Block") {
                        model.addPromptBlock()
                    }
                    .buttonStyle(.bordered)
                }

                if model.promptDraft.promptBlocks.isEmpty {
                    Text("No prompt blocks yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(model.promptDraft.promptBlocks.enumerated()), id: \.element.id) { index, block in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                TextField("Block title", text: blockBinding(index: index, keyPath: \.title))
                                    .textFieldStyle(.roundedBorder)
                                Picker("Target", selection: blockBinding(index: index, keyPath: \.target)) {
                                    ForEach(blockTargets, id: \.self) { target in
                                        Text(target).tag(target)
                                    }
                                }
                                .pickerStyle(.menu)
                                Toggle("Enabled", isOn: blockEnabledBinding(index: index))
                                    .toggleStyle(.switch)
                            }
                            TextEditor(text: blockBinding(index: index, keyPath: \.body))
                                .font(.system(.body, design: .monospaced))
                                .frame(minHeight: 110)
                                .padding(10)
                                .background(panelBackground, in: RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(borderColor, lineWidth: 1)
                                )
                            HStack(spacing: 10) {
                                Button("Insert into Prompt") {
                                    model.insertPromptBlock(block.blockID)
                                }
                                .buttonStyle(.bordered)
                                Button("Remove") {
                                    model.removePromptBlock(block.blockID)
                                }
                                .buttonStyle(.borderless)
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
    }

    private func blockBinding(index: Int, keyPath: WritableKeyPath<PromptBlockModel, String>) -> Binding<String> {
        Binding(
            get: {
                guard model.promptDraft.promptBlocks.indices.contains(index) else { return "" }
                return model.promptDraft.promptBlocks[index][keyPath: keyPath]
            },
            set: { newValue in
                guard model.promptDraft.promptBlocks.indices.contains(index) else { return }
                model.promptDraft.promptBlocks[index][keyPath: keyPath] = newValue
            }
        )
    }

    private func blockEnabledBinding(index: Int) -> Binding<Bool> {
        Binding(
            get: {
                guard model.promptDraft.promptBlocks.indices.contains(index) else { return false }
                return model.promptDraft.promptBlocks[index].enabled
            },
            set: { newValue in
                guard model.promptDraft.promptBlocks.indices.contains(index) else { return }
                model.promptDraft.promptBlocks[index].enabled = newValue
            }
        )
    }
}

private struct PromptDiffCard: View {
    @EnvironmentObject private var model: PromptForgeAppModel

    var body: some View {
        PanelCard(title: "Draft Diff") {
            if model.promptDiffPreview.isEmpty {
                Text("No draft changes to compare against the last saved workspace.")
                    .foregroundStyle(.secondary)
            } else {
                LabeledReadOnlyCode(label: "Inline Diff", text: model.promptDiffPreview)
            }
        }
    }
}

private struct CommandPaletteSheet: View {
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
            .init(id: "settings", title: "Open Settings", subtitle: "Project, models, auth, and Forgie defaults", isEnabled: true),
            .init(id: "new_prompt", title: "New Prompt", subtitle: "Create a new prompt pack", isEnabled: true),
            .init(id: "new_suite", title: "New Suite", subtitle: "Create a new scenario suite", isEnabled: model.selectedPrompt != nil),
            .init(id: "save_workspace", title: "Save Workspace", subtitle: "Persist prompt metadata and prompt files", isEnabled: model.selectedPrompt != nil),
            .init(id: "quick_check", title: "Quick Check", subtitle: "Run the benchmark on the active prompt", isEnabled: model.selectedPrompt != nil),
            .init(id: "run_suite", title: "Run Suite", subtitle: "Run the selected scenario suite and open review", isEnabled: model.selectedPrompt != nil && model.selectedSuite != nil),
            .init(id: "playground", title: "Run Playground", subtitle: "Generate samples for the current scratch input", isEnabled: model.selectedPrompt != nil),
            .init(id: "studio", title: "Show Studio", subtitle: "Return to prompt authoring", isEnabled: model.selectedPrompt != nil),
            .init(id: "tests", title: "Show Tests", subtitle: "Open scenario authoring", isEnabled: model.selectedPrompt != nil),
            .init(id: "review", title: "Show Review", subtitle: "Inspect regressions and decisions", isEnabled: !model.reviews.isEmpty),
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
        case "studio":
            model.showStudio()
        case "tests":
            model.showTests()
        case "review":
            model.showReview()
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

private struct CommandPaletteItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let isEnabled: Bool
}

private struct ForgieOnboardingCard: View {
    var body: some View {
        HStack(spacing: 18) {
            ForgieMark(size: 120, active: true)
            VStack(alignment: .leading, spacing: 8) {
                Text("Forgie")
                    .font(.system(size: 24, weight: .semibold))
                Text("Your editing agent for prompts, checks, and reviews.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 420, alignment: .leading)
            }
        }
        .padding(18)
        .background(panelBackground, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(borderColor, lineWidth: 1)
        )
    }
}

private struct ForgieStatusGlyph: View {
    let active: Bool

    var body: some View {
        ForgieMark(size: 56, active: active)
    }
}

private struct ForgieMark: View {
    let size: CGFloat
    let active: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            forgeGlow.opacity(active ? 0.42 : 0.18),
                            appAccent.opacity(active ? 0.26 : 0.10),
                            Color.clear,
                        ],
                        center: .center,
                        startRadius: 4,
                        endRadius: size * 0.55
                    )
                )
                .overlay(
                    Circle()
                        .fill(Color(red: 0.23, green: 0.13, blue: 0.08))
                        .padding(size * 0.08)
                )
                .overlay(
                    Circle()
                        .stroke(borderColor, lineWidth: 1.2)
                )
            FoxEarShape()
                .fill(appAccent)
                .frame(width: size * 0.24, height: size * 0.24)
                .offset(x: -size * 0.16, y: -size * 0.24)
            FoxEarShape()
                .fill(appAccent)
                .frame(width: size * 0.24, height: size * 0.24)
                .offset(x: size * 0.16, y: -size * 0.24)
            FoxEarShape()
                .fill(forgeGlow.opacity(0.82))
                .frame(width: size * 0.12, height: size * 0.12)
                .offset(x: -size * 0.16, y: -size * 0.22)
            FoxEarShape()
                .fill(forgeGlow.opacity(0.82))
                .frame(width: size * 0.12, height: size * 0.12)
                .offset(x: size * 0.16, y: -size * 0.22)
            Circle()
                .fill(forgeGlow.opacity(0.92))
                .frame(width: size * 0.42, height: size * 0.30)
                .offset(y: size * 0.14)
            HStack(spacing: size * 0.15) {
                Circle()
                    .fill(Color.black.opacity(0.72))
                    .frame(width: size * 0.06, height: size * 0.06)
                Circle()
                    .fill(Color.black.opacity(0.72))
                    .frame(width: size * 0.06, height: size * 0.06)
            }
            .offset(y: -size * 0.02)
            Circle()
                .fill(Color.black.opacity(0.65))
                .frame(width: size * 0.08, height: size * 0.08)
                .offset(y: size * 0.10)
        }
        .frame(width: size, height: size)
    }
}

private struct FoxEarShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct FlowWrap: View {
    let items: [String]
    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(panelBackground, in: Capsule())
            }
        }
    }
}

private struct ScenarioCaseNavigator: View {
    @EnvironmentObject private var model: PromptForgeAppModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Test Cases")
                    .font(.headline)
                if let suite = model.activeScenarioSuite {
                    Text("\(suite.cases.count) cases in \(suite.name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Each case is a saved product example. Run Cases compares the current prompt against the baseline on these same inputs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button("New Case") {
                        model.createScenarioCase()
                    }
                    .buttonStyle(.bordered)

                    Button("Duplicate") {
                        model.duplicateSelectedScenarioCase()
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.selectedScenarioCase == nil)
                }
            }
            .padding(16)

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
        .background(sidebarBackground)
    }
}

private struct ScenarioIDEPane: View {
    @EnvironmentObject private var model: PromptForgeAppModel

    var body: some View {
        VSplitView {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Text(model.activeScenarioSuite?.name ?? "Case Set")
                            .font(.headline)
                        Text(model.activeScenarioSuite?.suiteID ?? "--")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Run Cases") {
                            model.runScenarioReview()
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Save Case Set") {
                            model.saveScenarioSuite()
                        }
                        .buttonStyle(.bordered)
                    }

                    HStack(spacing: 10) {
                        FlowStep(label: "1", text: "Edit cases")
                        FlowStep(label: "2", text: "Run cases")
                        FlowStep(label: "3", text: "Inspect results")
                    }

                    if let suite = model.activeScenarioSuite {
                        Text("Current case set: \(suite.name). Running cases will execute this set against the current prompt and the baseline, then open Results.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ScenarioSuiteEditor()
                            .environmentObject(model)
                        ScenarioCaseEditor()
                            .environmentObject(model)
                    }
                    .padding(16)
                }
            }
        }
        .background(canvasBackground)
    }
}

private struct ScenarioSuiteEditor: View {
    @EnvironmentObject private var model: PromptForgeAppModel

    var body: some View {
            VStack(alignment: .leading, spacing: 12) {
            LabeledField(label: "Case Set Name", text: suiteBinding(\.name))
            LabeledTextEditor(label: "What This Set Covers", text: suiteBinding(\.description), minHeight: 80, font: .system(.body, design: .default))
            LabeledField(label: "Prompts In Scope", text: linkedPromptsBinding)

            HStack(spacing: 10) {
                if let suite = model.activeScenarioSuite {
                    SoftBadge(label: "Cases", value: "\(suite.cases.count)")
                    SoftBadge(label: "Set ID", value: suite.suiteID)
                }
            }

            Text("Run Cases executes every saved case against the current prompt and the baseline, then opens Results with pass/fail checks and regressions.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let scenarioNotice = model.scenarioNotice, !scenarioNotice.isEmpty {
                Text(scenarioNotice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

private struct FlowStep: View {
    let label: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(appAccent, in: Circle())
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(panelBackground, in: Capsule())
        .overlay(
            Capsule()
                .stroke(borderColor, lineWidth: 1)
        )
    }
}

private struct ScenarioCaseEditor: View {
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
        VStack(alignment: .leading, spacing: 14) {
                Text(model.selectedScenarioCase?.title.isEmpty == false ? (model.selectedScenarioCase?.title ?? "Case") : "Case")
                    .font(.headline)

            if let scenarioCase = model.selectedScenarioCase {
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
                LabeledTextEditor(label: "Context", text: caseBinding(\.contextText), minHeight: 90, font: .system(.body, design: .default))
                LabeledTextEditor(label: "Notes", text: caseBinding(\.notes), minHeight: 90, font: .system(.body, design: .default))
                LabeledTextEditor(label: "Input", text: caseBinding(\.inputJSON), minHeight: 220, font: .system(.caption, design: .monospaced))

                VStack(alignment: .leading, spacing: 12) {
                    Text("Checks")
                        .font(.headline)
                    Text("Checks are the rules this output must pass. Use required text for must-include phrases, max words for length limits, and trait minimum for judged quality floors.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if scenarioCase.assertions.isEmpty {
                        Text("Add checks to define required content, limits, or judged quality thresholds.")
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
                                .background(panelBackground, in: RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(borderColor, lineWidth: 1)
                                )
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
        .background(panelBackground, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(borderColor, lineWidth: 1)
        )
    }
}

private struct ActivityFeedCard: View {
    @EnvironmentObject private var model: PromptForgeAppModel

    var body: some View {
        PanelCard(title: "Forge Log") {
            if activityEntries.isEmpty {
                Text("Run status, helper messages, and warnings will appear here.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(activityEntries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.title)
                                .font(.caption.weight(.semibold))
                            Text(entry.body)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(4)
                        }
                    }
                }
            }
        }
    }

    private var activityEntries: [TranscriptEntry] {
        Array(model.transcript.filter { entry in
            entry.role != .user && entry.role != .agent
        }.suffix(8).reversed())
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
                        .foregroundStyle(.secondary)
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
                            Button("Authenticate Codex") {
                                model.launchCodexLogin()
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
        .background(forgePanelFill, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(borderColor, lineWidth: 1)
        )
        .shadow(color: appAccent.opacity(0.10), radius: 18, x: 0, y: 10)
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
        .background(forgePanelFill, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(borderColor, lineWidth: 1)
        )
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
                .background(inputBackground, in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(borderColor, lineWidth: 1)
                )
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
                .background(inputBackground, in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(borderColor, lineWidth: 1)
                )
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
                .textFieldStyle(.plain)
                .padding(10)
                .background(inputBackground, in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(borderColor, lineWidth: 1)
                )
        }
    }
}

private struct PromptTextEditorCard: View {
    let title: String
    @Binding var text: String
    var diffText: String = ""

    var body: some View {
        PanelCard(title: title) {
            VStack(alignment: .leading, spacing: 12) {
                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 320)
                    .padding(10)
                    .background(canvasBackground, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(borderColor, lineWidth: 1)
                    )

                if !diffText.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Diff")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(diffText)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(canvasBackground, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(borderColor, lineWidth: 1)
                            )
                    }
                }
            }
        }
    }
}

private struct TranscriptBubble: View {
    let entry: TranscriptEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(entry.body)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(panelBackground, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(borderColor, lineWidth: 1)
        )
    }
}

private struct ChatMessageBubble: View {
    let entry: TranscriptEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if entry.role != .user {
                Text(entry.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(entry.body)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(entry.role == .user ? appAccent.opacity(0.20) : inputBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(entry.role == .user ? appAccent.opacity(0.26) : borderColor, lineWidth: 1)
        )
        .frame(maxWidth: 420, alignment: entry.role == .user ? .trailing : .leading)
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
        .background(inputBackground, in: Capsule())
        .overlay(
            Capsule()
                .stroke(borderColor, lineWidth: 1)
        )
    }
}
