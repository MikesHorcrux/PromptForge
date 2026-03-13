import SwiftUI

struct BuilderControlsCard: View {
    @EnvironmentObject private var model: PromptForgeAppModel
    private let permissionModes = ["proposal_only", "auto_apply"]
    private let researchPolicies = ["prompt_only", "allow_external"]

    var body: some View {
        PanelCard(title: "Agent") {
            VStack(alignment: .leading, spacing: 12) {
                Text("The agent can either stage edits for review or apply them directly. Keep the controls small and stay focused on the prompt.")
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

struct StudioChatPane: View {
    @EnvironmentObject private var model: PromptForgeAppModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    HStack(spacing: 10) {
                        ForgieStatusGlyph(active: model.isBusy)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Agent")
                                .font(.headline)
                            Text("Use the agent for edits, failures, and prompt review. System activity lives in the inspector so this thread stays conversational.")
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
                            PanelCard(title: "Ask The Agent") {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Try asking:")
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
                TextField("Ask the agent to edit, explain, or review the prompt", text: $model.draftMessage, axis: .vertical)
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

struct ActivityFeedCard: View {
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
