import SwiftUI

struct PromptSummaryModel: Identifiable, Equatable {
    let version: String
    let name: String
    let description: String

    var id: String { version }
}

struct CaseIssue: Identifiable, Equatable {
    let caseID: String
    let score: String
    let hardFailRate: String
    let reasons: String
    let summary: String

    var id: String { caseID + score + hardFailRate }
}

struct PreparedProposal: Identifiable, Equatable {
    let proposalID: String
    let summary: String
    let diffPreview: String
    let changedFiles: [String]

    var id: String { proposalID }
}

enum TranscriptRole {
    case system
    case user
    case agent
    case result
    case warning

    var tint: Color {
        switch self {
        case .system:
            return .cyan
        case .user:
            return .white
        case .agent:
            return .orange
        case .result:
            return .green
        case .warning:
            return .red
        }
    }

    var background: Color {
        switch self {
        case .system:
            return .blue.opacity(0.10)
        case .user:
            return .white.opacity(0.05)
        case .agent:
            return .orange.opacity(0.10)
        case .result:
            return .green.opacity(0.10)
        case .warning:
            return .red.opacity(0.10)
        }
    }

    var border: Color {
        switch self {
        case .system:
            return .blue.opacity(0.25)
        case .user:
            return .white.opacity(0.08)
        case .agent:
            return .orange.opacity(0.30)
        case .result:
            return .green.opacity(0.30)
        case .warning:
            return .red.opacity(0.30)
        }
    }
}

struct TranscriptEntry: Identifiable, Equatable {
    let id = UUID()
    let role: TranscriptRole
    let title: String
    let body: String
}

struct HelperEvent: Equatable {
    let sequence: Int
    let type: String
    let timestamp: String
    let payload: [String: String]
}

struct ProviderConnectionStatus: Identifiable, Equatable {
    let id: String
    let label: String
    let ready: Bool
    let detail: String
    let source: String
}

struct AppSettingsDraft: Equatable {
    var projectName: String = "PromptForge Project"
    var provider: String = ProviderID.openAI.rawValue
    var judgeProvider: String = ProviderID.openAI.rawValue
    var generationModel: String = "gpt-5.4"
    var judgeModel: String = "gpt-5-mini"
    var agentModel: String = "gpt-5-mini"
    var quickBenchmarkDataset: String = "datasets/core.jsonl"
    var fullEvaluationDataset: String = "datasets/core.jsonl"
    var quickBenchmarkRepeats: Int = 1
    var fullEvaluationRepeats: Int = 1
    var builderPermissionMode: String = "proposal_only"
    var builderResearchPolicy: String = "prompt_only"
}

enum PromptWorkspaceMode: String, CaseIterable, Identifiable {
    case studio
    case tests
    case review

    var id: String { rawValue }

    var title: String {
        switch self {
        case .studio:
            return "Prompt"
        case .tests:
            return "Tests"
        case .review:
            return "Review"
        }
    }
}

struct PromptWorkspaceDraft: Equatable {
    var purpose: String = ""
    var expectedBehavior: String = ""
    var successCriteria: String = ""
    var baselinePromptRef: String = ""
    var primaryScenarioSuites: [String] = []
    var owner: String = ""
    var audience: String = ""
    var releaseNotes: String = ""
    var builderAgentModel: String = "gpt-5-mini"
    var builderPermissionMode: String = "proposal_only"
    var researchPolicy: String = "prompt_only"
    var promptBlocks: [PromptBlockModel] = []
    var systemPrompt: String = ""
    var userTemplate: String = ""
}

struct PromptBlockModel: Identifiable, Equatable {
    let blockID: String
    var title: String
    var body: String
    var target: String
    var enabled: Bool

    var id: String { blockID }
}

struct ScenarioAssertionModel: Identifiable, Equatable {
    let assertionID: String
    var label: String
    var kind: String
    var expectedText: String
    var threshold: Double?
    var trait: String
    var severity: String

    var id: String { assertionID }
}

struct ScenarioCaseModel: Identifiable, Equatable {
    let caseID: String
    var title: String
    var inputJSON: String
    var contextText: String
    var tags: [String]
    var notes: String
    var assertions: [ScenarioAssertionModel]

    var id: String { caseID }
}

struct ScenarioSuiteModel: Identifiable, Equatable {
    let suiteID: String
    var name: String
    var description: String
    var linkedPrompts: [String]
    var cases: [ScenarioCaseModel]
    var createdAt: String
    var updatedAt: String

    var id: String { suiteID }
}

struct PlaygroundSampleModel: Identifiable, Equatable {
    let sampleID: String
    let outputText: String
    let latencyMS: Int
    let totalTokens: Int

    var id: String { sampleID }
}

struct PlaygroundRunModel: Identifiable, Equatable {
    let runID: String
    let createdAt: String
    let inputJSON: String
    let contextText: String
    let candidateSamples: [PlaygroundSampleModel]
    let baselineSamples: [PlaygroundSampleModel]

    var id: String { runID }
}

struct BuilderActionModel: Identifiable, Equatable {
    let actionID: String
    let kind: String
    let title: String
    let details: String
    let files: [String]
    let tools: [String]
    let usedResearch: Bool
    let permissionMode: String
    let createdAt: String

    var id: String { actionID }
}

struct ReviewAssertionModel: Identifiable, Equatable {
    let assertionID: String
    let label: String
    let status: String
    let detail: String

    var id: String { assertionID }
}

struct ReviewCaseModel: Identifiable, Equatable {
    let caseID: String
    let title: String
    let candidateScore: Double?
    let baselineScore: Double?
    let regression: Bool
    let flaky: Bool
    let candidateOutput: String
    let baselineOutput: String
    let diffPreview: String
    let hardFailReasons: [String]
    let assertions: [ReviewAssertionModel]
    let likelyChangedFiles: [String]

    var id: String { caseID }
}

struct ReviewSummaryModel: Identifiable, Equatable {
    let reviewID: String
    let suiteID: String
    let suiteName: String
    let createdAt: String
    let revisionID: String
    let scoreDelta: Double?
    let passRateDelta: Double?
    let cases: [ReviewCaseModel]

    var id: String { reviewID }
}

struct DecisionRecordModel: Identifiable, Equatable {
    let decisionID: String
    let status: String
    let summary: String
    let rationale: String
    let createdAt: String

    var id: String { decisionID }
}
