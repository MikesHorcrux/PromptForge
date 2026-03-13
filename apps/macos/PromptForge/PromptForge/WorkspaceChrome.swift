import SwiftUI

struct WorkspaceTopBar: View {
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
                    actionButton("Run Tests", systemImage: "checklist", enabled: model.selectedPrompt != nil && model.selectedSuite != nil) {
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
            let suiteName = model.scenarioSuites.first(where: { $0.suiteID == suiteID })?.name ?? "Test Suite"
            return "\(model.projectName) / tests / \(suiteName)"
        case .review(let reviewID):
            let suiteName = model.reviews.first(where: { $0.reviewID == reviewID })?.suiteName ?? "Review"
            return "\(model.projectName) / review / \(suiteName)"
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
                return "This is the live prompt document. Edit it here, ask the agent in the next pane, then run checks from the toolbar."
            }
            return "This file is part of the prompt. Edit metadata here, use the inspector for context, and run checks from the toolbar."
        case .playground:
            return "Try one-off inputs here before turning them into saved tests. Promote useful examples into Tests when they become part of the product contract."
        case .caseSet:
            return "Test suites are saved product tests. Edit examples and checks here, then run them against the current prompt and the baseline."
        case .review:
            return "Review compares the current prompt against the baseline and shows regressions, diffs, and decision history."
        case nil:
            return "Open a prompt from the navigator, edit its files, define saved tests, and inspect review results in one workspace."
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

struct NavigatorSection<Content: View>: View {
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

struct NavigatorRow: View {
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

struct NavigatorPlaceholder: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
    }
}

struct TopBarActionButtonStyle: ButtonStyle {
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
