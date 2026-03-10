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
        .frame(minWidth: 1320, minHeight: 840)
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
            HSplitView {
                chatView
                inspectorView
                    .frame(minWidth: 340, idealWidth: 380, maxWidth: 460)
            }
            .background(Color.black.opacity(0.94))
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
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

                Button("Open Project") {
                    model.chooseProjectFolder()
                }
                .buttonStyle(.bordered)
            }

            List(selection: Binding(
                get: { model.selectedPrompt },
                set: { newValue in
                    guard let newValue else { return }
                    Task {
                        await model.openPrompt(newValue, announce: true)
                    }
                }
            )) {
                ForEach(model.prompts) { prompt in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(prompt.version)
                            .font(.system(.body, design: .monospaced))
                        Text(prompt.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(Optional(prompt.version))
                }
            }
            .listStyle(.sidebar)

            Spacer()
        }
        .padding(16)
        .background(Color.black.opacity(0.90))
    }

    private var chatView: some View {
        VStack(spacing: 0) {
            headerCard

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

                TextField(
                    "Ask PromptForge to improve the current prompt, or use a slash command like /bench or /apply",
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

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PromptForge Agent")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                    Text(model.statusSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(model.providerLine)
                        .font(.caption.monospaced())
                    Text(model.sessionLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 18) {
                StatusPill(label: "Prompt", value: model.selectedPrompt ?? "--")
                StatusPill(label: "Latest score", value: model.latestScoreLine)
                StatusPill(label: "Delta", value: model.latestDeltaLine)
                StatusPill(label: "Auth", value: model.authLine)
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [.blue.opacity(0.20), .black.opacity(0.96)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18)
        )
        .padding(18)
    }

    private var inspectorView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                InspectorSection(title: "System Prompt", content: model.systemPrompt)
                InspectorSection(title: "User Template", content: model.userTemplate)
                InspectorKeyValueSection(title: "Benchmark Summary", rows: model.benchmarkRows)
                InspectorCasesSection(title: "Weak Cases", cases: model.weakCases)
                InspectorCasesSection(title: "Failures", cases: model.failureCases)
            }
            .padding(18)
        }
        .background(Color.black.opacity(0.90))
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

private struct InspectorSection: View {
    let title: String
    let content: String

    var bodyView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(content.isEmpty ? "Nothing loaded yet." : content)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
    }

    var body: some View { bodyView }
}

private struct InspectorKeyValueSection: View {
    let title: String
    let rows: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
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
        .padding(14)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct InspectorCasesSection: View {
    let title: String
    let cases: [CaseIssue]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            if cases.isEmpty {
                Text("No cases to show.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
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
        .padding(14)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
    }
}
