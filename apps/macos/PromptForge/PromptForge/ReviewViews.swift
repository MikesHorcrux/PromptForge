import SwiftUI

struct ReviewCaseRow: View {
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

struct ReviewCaseDetail: View {
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
