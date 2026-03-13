import SwiftUI

struct PlaygroundCard: View {
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

struct PlaygroundSampleCard: View {
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
