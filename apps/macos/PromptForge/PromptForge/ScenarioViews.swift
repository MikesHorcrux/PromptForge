import SwiftUI

struct ScenarioCaseNavigator: View {
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
                Text("Each case is a saved product example. Run Tests compares the current prompt against the baseline on these same inputs.")
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

struct ScenarioSuiteEditor: View {
    @EnvironmentObject private var model: PromptForgeAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledField(label: "Test Suite Name", text: suiteBinding(\.name))
            LabeledTextEditor(label: "What This Set Covers", text: suiteBinding(\.description), minHeight: 80, font: .system(.body, design: .default))
            LabeledField(label: "Prompts In Scope", text: linkedPromptsBinding)

            HStack(spacing: 10) {
                if let suite = model.activeScenarioSuite {
                    SoftBadge(label: "Tests", value: "\(suite.cases.count)")
                    SoftBadge(label: "Set ID", value: suite.suiteID)
                }
            }

            Text("Run Tests executes every saved case against the current prompt and the baseline, then opens Review with pass/fail checks and regressions.")
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

struct FlowStep: View {
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

struct ScenarioCaseEditor: View {
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
