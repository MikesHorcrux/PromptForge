import Foundation

enum ProviderID: String, CaseIterable, Identifiable {
    case openAI = "openai"
    case openRouter = "openrouter"
    case codex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI:
            return "OpenAI"
        case .openRouter:
            return "OpenRouter"
        case .codex:
            return "Codex"
        }
    }
}

struct ProviderCapabilities: Equatable {
    let supportsStreaming: Bool
    let supportsToolCalling: Bool
    let supportsStructuredOutput: Bool
    let supportsPromptCaching: Bool
    let supportsExternalAuthBridge: Bool

    static let openAIResponses = ProviderCapabilities(
        supportsStreaming: true,
        supportsToolCalling: true,
        supportsStructuredOutput: true,
        supportsPromptCaching: false,
        supportsExternalAuthBridge: false
    )

    static let codexCLI = ProviderCapabilities(
        supportsStreaming: true,
        supportsToolCalling: true,
        supportsStructuredOutput: true,
        supportsPromptCaching: false,
        supportsExternalAuthBridge: true
    )
}

enum ProviderAuthState: Equatable {
    case ready
    case needsAuth
    case unavailable
}

struct ProviderAuthStatus: Equatable {
    let state: ProviderAuthState
    let detail: String
    let source: String
}

struct ToolDefinition: Identifiable, Equatable {
    let name: String
    let description: String
    let inputSchemaSummary: String

    var id: String { name }
}

struct ToolCall: Identifiable, Equatable {
    let callID: String
    let toolName: String
    let argumentsJSON: String

    var id: String { callID }
}

struct ToolResult: Equatable {
    let callID: String
    let outputText: String
    let isError: Bool
}

struct AgentMessage: Identifiable, Equatable {
    let messageID: String
    let role: String
    let content: String

    var id: String { messageID }
}

struct AgentRequest: Equatable {
    let systemPrompt: String
    let messages: [AgentMessage]
    let model: String
}

enum AgentStreamEventKind: String {
    case status
    case textDelta
    case toolCall
    case completed
}

struct AgentStreamEvent: Equatable {
    let kind: AgentStreamEventKind
    let text: String
    let toolCall: ToolCall?
}

protocol ModelProvider {
    var id: ProviderID { get }
    var capabilities: ProviderCapabilities { get }

    func authStatus() async -> ProviderAuthStatus
    func streamTurn(
        _ request: AgentRequest,
        tools: [ToolDefinition]
    ) -> AsyncThrowingStream<AgentStreamEvent, Error>
}

enum ProviderRuntimeError: Error, LocalizedError {
    case notImplemented(String)

    var errorDescription: String? {
        switch self {
        case .notImplemented(let detail):
            return detail
        }
    }
}

struct OpenAIResponsesProvider: ModelProvider {
    let id: ProviderID = .openAI
    let capabilities: ProviderCapabilities = .openAIResponses

    func authStatus() async -> ProviderAuthStatus {
        if KeychainSecretStore.has(key: "OPENAI_API_KEY") {
            return ProviderAuthStatus(state: .ready, detail: "API key available.", source: "Keychain")
        }
        return ProviderAuthStatus(state: .needsAuth, detail: "OpenAI API key missing.", source: "Keychain")
    }

    func streamTurn(
        _ request: AgentRequest,
        tools: [ToolDefinition]
    ) -> AsyncThrowingStream<AgentStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: ProviderRuntimeError.notImplemented("OpenAIResponsesProvider is the next Swift-native provider to implement."))
        }
    }
}

struct CodexCLIProvider: ModelProvider {
    let id: ProviderID = .codex
    let capabilities: ProviderCapabilities = .codexCLI

    func authStatus() async -> ProviderAuthStatus {
        ProviderAuthStatus(
            state: .unavailable,
            detail: "Codex CLI bridging is not implemented in the Swift helper yet.",
            source: "Local helper"
        )
    }

    func streamTurn(
        _ request: AgentRequest,
        tools: [ToolDefinition]
    ) -> AsyncThrowingStream<AgentStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: ProviderRuntimeError.notImplemented("CodexCLIProvider is the next compatibility bridge to port into Swift."))
        }
    }
}

enum PromptForgeProviderCatalog {
    static let builtInProviders: [ProviderID] = ProviderID.allCases
}
