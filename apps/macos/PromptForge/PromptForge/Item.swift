import AppKit
import Combine
import Foundation
import Security
import SwiftUI

struct LaunchContext {
    let projectPath: String?
    let engineRoot: String?

    init(arguments: [String]) {
        self.projectPath = LaunchContext.value(for: "--project", in: arguments)
        self.engineRoot = LaunchContext.value(for: "--engine-root", in: arguments)
    }

    private static func value(for flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }
}

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
    var provider: String = "openai"
    var judgeProvider: String = "openai"
    var generationModel: String = "gpt-5.4"
    var judgeModel: String = "gpt-5-mini"
    var quickBenchmarkDataset: String = "datasets/core.jsonl"
    var fullEvaluationDataset: String = "datasets/core.jsonl"
}

enum PromptWorkspaceMode: String, CaseIterable, Identifiable {
    case overview
    case editor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:
            return "Overview"
        case .editor:
            return "Editor"
        }
    }
}

struct PromptWorkspaceDraft: Equatable {
    var purpose: String = ""
    var expectedBehavior: String = ""
    var successCriteria: String = ""
    var systemPrompt: String = ""
    var userTemplate: String = ""
}

struct BenchmarkHistoryEntry: Identifiable, Equatable {
    let revisionID: String
    let createdAt: String
    let source: String
    let note: String
    let score: Double?
    let scoreDeltaVsBaseline: Double?
    let passRate: Double?
    let hardFailRate: Double?
    let fullScore: Double?

    var id: String { revisionID }
}

struct BenchmarkTrendPoint: Identifiable, Equatable {
    let revisionID: String
    let score: Double

    var id: String { revisionID }
}

enum KeychainSecretStore {
    private static let service = "com.lunarmothstudios.PromptForge"
    private static let secretKeys = ["OPENAI_API_KEY", "OPENROUTER_API_KEY"]

    static func hydrate(environment: inout [String: String]) {
        for key in secretKeys {
            if let stored = read(key: key), !stored.isEmpty {
                environment[key] = stored
                continue
            }
            guard let inherited = environment[key], !inherited.isEmpty else {
                continue
            }
            _ = write(key: key, value: inherited)
        }
    }

    static func has(key: String) -> Bool {
        guard let value = read(key: key) else {
            return false
        }
        return !value.isEmpty
    }

    static func read(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func write(key: String, value: String) -> Bool {
        let payload = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: payload,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }
        if updateStatus != errSecItemNotFound {
            return false
        }
        var insert = query
        insert[kSecValueData as String] = payload
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    static func delete(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

enum SecurityScopedProjectStore {
    private static let bookmarkKey = "PromptForgeProjectBookmark"
    private static let pathKey = "PromptForgeProjectPath"

    static func save(url: URL) {
        guard let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) else {
            UserDefaults.standard.set(url.path, forKey: pathKey)
            return
        }
        UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
        UserDefaults.standard.set(url.path, forKey: pathKey)
    }

    static func resolve() -> URL? {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else {
            return nil
        }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }
        if isStale {
            save(url: url)
        }
        return url
    }

    static func savedPath() -> String? {
        UserDefaults.standard.string(forKey: pathKey)
    }
}

enum HelperClientError: Error, LocalizedError {
    case invalidResponse
    case helperLaunchFailed(String)
    case socketConnectionFailed(String)
    case requestRejected(String)
    case missingField(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The helper returned an invalid response."
        case .helperLaunchFailed(let detail):
            return detail
        case .socketConnectionFailed(let detail):
            return detail
        case .requestRejected(let detail):
            return detail
        case .missingField(let detail):
            return detail
        }
    }
}

final class PromptForgeHelperClient {
    private let projectRoot: String
    private let engineRoot: String
    private let socketPath: String
    private let token: String
    private var process: Process?

    init(projectRoot: String, engineRoot: String) throws {
        self.projectRoot = projectRoot
        self.engineRoot = engineRoot
        self.socketPath = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("promptforge-\(UUID().uuidString).sock")
            .path
        self.token = UUID().uuidString
        try launchHelper()
    }

    deinit {
        shutdown()
    }

    func shutdown() {
        process?.terminate()
        process = nil
        try? FileManager.default.removeItem(atPath: socketPath)
    }

    nonisolated func send(method: String, params: [String: Any] = [:]) async throws -> [String: Any] {
        try await Task.detached(priority: .userInitiated) {
            try self.sendSync(method: method, params: params)
        }.value
    }

    nonisolated func subscribe(after cursor: Int, timeoutSeconds: Double = 15) async throws -> (cursor: Int, events: [HelperEvent]) {
        let result = try await send(
            method: "events.subscribe",
            params: [
                "after": cursor,
                "timeout_seconds": timeoutSeconds,
                "limit": 50,
            ]
        )
        let nextCursor = result["cursor"] as? Int ?? cursor
        let eventObjects = result["events"] as? [[String: Any]] ?? []
        let events = eventObjects.compactMap(Self.parseEvent(_:))
        return (nextCursor, events)
    }

    private func launchHelper() throws {
        let process = Process()
        let pythonExecutable = "\(engineRoot)/.venv/bin/python"
        if FileManager.default.isExecutableFile(atPath: pythonExecutable) {
            process.executableURL = URL(fileURLWithPath: pythonExecutable)
            process.arguments = [
                "-m",
                "promptforge.helper.server",
                "--project",
                projectRoot,
                "--socket",
                socketPath,
                "--token",
                token,
            ]
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [
                "python3",
                "-m",
                "promptforge.helper.server",
                "--project",
                projectRoot,
                "--socket",
                socketPath,
                "--token",
                token,
            ]
        }

        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = Pipe()

        var environment = ProcessInfo.processInfo.environment
        let pythonPath = "\(engineRoot)/src"
        if let existing = environment["PYTHONPATH"], !existing.isEmpty {
            environment["PYTHONPATH"] = "\(existing):\(pythonPath)"
        } else {
            environment["PYTHONPATH"] = pythonPath
        }
        environment["PF_ENGINE_ROOT"] = engineRoot
        KeychainSecretStore.hydrate(environment: &environment)
        process.environment = environment

        do {
            try process.run()
        } catch {
            throw HelperClientError.helperLaunchFailed("Failed to launch the PromptForge helper: \(error.localizedDescription)")
        }

        self.process = process

        for _ in 0 ..< 50 {
            if FileManager.default.fileExists(atPath: socketPath) {
                return
            }
            if !process.isRunning {
                let detail = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                throw HelperClientError.helperLaunchFailed("The PromptForge helper exited early.\n\(detail)")
            }
            Thread.sleep(forTimeInterval: 0.1)
        }

        let detail = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        throw HelperClientError.helperLaunchFailed("The PromptForge helper did not start in time.\n\(detail)")
    }

    private nonisolated func sendSync(method: String, params: [String: Any]) throws -> [String: Any] {
        let handle = try makeSocketHandle()
        defer {
            try? handle.close()
        }

        let envelope: [String: Any] = [
            "id": UUID().uuidString,
            "token": token,
            "method": method,
            "params": params,
        ]
        let payload = try JSONSerialization.data(withJSONObject: envelope, options: [])
        handle.write(payload)
        handle.write(Data([0x0A]))

        var responseData = Data()
        while true {
            guard let chunk = try handle.read(upToCount: 1), !chunk.isEmpty else {
                break
            }
            if chunk.first == 0x0A {
                break
            }
            responseData.append(chunk)
        }

        guard
            let object = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
            let ok = object["ok"] as? Bool
        else {
            throw HelperClientError.invalidResponse
        }
        if ok {
            return object["result"] as? [String: Any] ?? [:]
        }
        let errorText = object["error"] as? String ?? "Unknown helper failure."
        throw HelperClientError.requestRejected(errorText)
    }

    private nonisolated func makeSocketHandle() throws -> FileHandle {
        let socketFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketFD >= 0 else {
            throw HelperClientError.socketConnectionFailed("Could not create a Unix socket.")
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let maxLength = MemoryLayout.size(ofValue: address.sun_path)
        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= maxLength else {
            close(socketFD)
            throw HelperClientError.socketConnectionFailed("The Unix socket path is too long.")
        }

        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            let rawPointer = UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: CChar.self)
            rawPointer.initialize(repeating: 0, count: maxLength)
            pathBytes.withUnsafeBufferPointer { buffer in
                guard let baseAddress = buffer.baseAddress else { return }
                rawPointer.update(from: baseAddress, count: buffer.count)
            }
        }

        var mutableAddress = address
        let addressLength = socklen_t(MemoryLayout.size(ofValue: mutableAddress))
        let connectResult = withUnsafePointer(to: &mutableAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.connect(
                    socketFD,
                    sockaddrPointer,
                    addressLength
                )
            }
        }
        guard connectResult == 0 else {
            close(socketFD)
            throw HelperClientError.socketConnectionFailed("Could not connect to the PromptForge helper.")
        }
        return FileHandle(fileDescriptor: socketFD, closeOnDealloc: true)
    }

    private nonisolated static func parseEvent(_ object: [String: Any]) -> HelperEvent? {
        guard
            let sequence = object["sequence"] as? Int,
            let type = object["type"] as? String,
            let timestamp = object["timestamp"] as? String
        else {
            return nil
        }
        let payloadObject = object["payload"] as? [String: Any] ?? [:]
        let payload = payloadObject.reduce(into: [String: String]()) { partialResult, item in
            partialResult[item.key] = String(describing: item.value)
        }
        return HelperEvent(sequence: sequence, type: type, timestamp: timestamp, payload: payload)
    }
}

@MainActor
final class PromptForgeAppModel: ObservableObject {
    @Published var projectPath: String?
    @Published var projectName: String = "PromptForge"
    @Published var draftMessage: String = ""
    @Published var prompts: [PromptSummaryModel] = []
    @Published var selectedPrompt: String?
    @Published var selectedWorkspaceMode: PromptWorkspaceMode = .overview
    @Published var currentPromptName: String = ""
    @Published var currentPromptDescription: String = ""
    @Published var promptRootPath: String = ""
    @Published var systemPrompt: String = ""
    @Published var userTemplate: String = ""
    @Published var promptDraft: PromptWorkspaceDraft = .init()
    @Published var promptFiles: [String] = []
    @Published var transcript: [TranscriptEntry] = []
    @Published var benchmarkRows: [(String, String)] = []
    @Published var weakCases: [CaseIssue] = []
    @Published var failureCases: [CaseIssue] = []
    @Published var pendingProposal: PreparedProposal?
    @Published var providerLine: String = "provider --"
    @Published var authLine: String = "auth unknown"
    @Published var sessionLine: String = "session --"
    @Published var latestScoreLine: String = "--"
    @Published var latestDeltaLine: String = "--"
    @Published var statusSubtitle: String = "Open a project to begin."
    @Published var isBusy: Bool = false
    @Published var launchError: String?
    @Published var showSettings: Bool = false
    @Published var settingsMode: String = "settings"
    @Published var settingsDraft: AppSettingsDraft = .init()
    @Published var openAIKeyDraft: String = ""
    @Published var openRouterKeyDraft: String = ""
    @Published var settingsNotice: String?
    @Published var settingsError: String?
    @Published var connectionStatuses: [ProviderConnectionStatus] = []
    @Published var benchmarkHistory: [BenchmarkHistoryEntry] = []
    @Published var benchmarkTrend: [BenchmarkTrendPoint] = []
    @Published var promptSaveNotice: String?

    private var helper: PromptForgeHelperClient?
    private var engineRoot: String?
    private var eventTask: Task<Void, Never>?
    private var eventCursor: Int = 0
    private var projectScopeURL: URL?
    private var savedPromptDraft: PromptWorkspaceDraft = .init()

    init(initialProjectPath: String?, initialEngineRoot: String?) {
        self.engineRoot = initialEngineRoot ?? UserDefaults.standard.string(forKey: "PromptForgeEngineRoot")
        self.projectPath = nil
        if let initialProjectPath {
            Task {
                await openProject(at: initialProjectPath, engineRoot: initialEngineRoot)
            }
        } else if let bookmarkedProject = SecurityScopedProjectStore.resolve() {
            Task {
                await openProject(url: bookmarkedProject, engineRoot: initialEngineRoot ?? self.engineRoot)
            }
        }
    }

    var savedProjectHint: String? {
        SecurityScopedProjectStore.savedPath()
    }

    var isOnboarding: Bool {
        settingsMode == "onboarding"
    }

    var promptHasUnsavedChanges: Bool {
        promptDraft != savedPromptDraft
    }

    var selectedPromptSummary: PromptSummaryModel? {
        guard let selectedPrompt else { return nil }
        return prompts.first(where: { $0.version == selectedPrompt })
    }

    var recentTranscript: [TranscriptEntry] {
        Array(transcript.suffix(4))
    }

    func chooseProjectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                await openProject(url: url)
            }
        }
    }

    private func beginProjectScope(for url: URL) -> Bool {
        projectScopeURL?.stopAccessingSecurityScopedResource()
        projectScopeURL = nil
        guard url.startAccessingSecurityScopedResource() else {
            return false
        }
        projectScopeURL = url
        return true
    }

    private func resolveEngineRoot(projectURL: URL, explicitEngineRoot: String?) -> String {
        let candidates = [explicitEngineRoot, engineRoot]
            .compactMap { root -> String? in
                guard let root, !root.isEmpty else {
                    return nil
                }
                return NSString(string: root).expandingTildeInPath
            }
        for candidate in candidates {
            let pythonExecutable = URL(fileURLWithPath: candidate).appendingPathComponent(".venv/bin/python").path
            let helperModule = URL(fileURLWithPath: candidate).appendingPathComponent("src/promptforge/helper/server.py").path
            if FileManager.default.isExecutableFile(atPath: pythonExecutable),
               FileManager.default.fileExists(atPath: helperModule)
            {
                return URL(fileURLWithPath: candidate).standardizedFileURL.path
            }
        }
        return projectURL.path
    }

    func createPromptShortcut() {
        submitText("/new draft-\(Int(Date().timeIntervalSince1970))")
    }

    func showOverview() {
        selectedWorkspaceMode = .overview
    }

    func showEditor() {
        selectedWorkspaceMode = .editor
    }

    func savePromptWorkspace() {
        Task {
            _ = await persistPromptWorkspace()
        }
    }

    func runQuickBenchmark() {
        Task {
            await runHelperMethod("bench.run_quick")
        }
    }

    func runFullEvaluation() {
        Task {
            await runHelperMethod("eval.run_full")
        }
    }

    func submitDraft() {
        let text = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draftMessage = ""
        submitText(text)
    }

    func submitText(_ text: String) {
        Task {
            await handleInput(text)
        }
    }

    func openSettings(onboarding: Bool = false) {
        Task {
            await loadSettings(openingMode: onboarding ? "onboarding" : "settings")
        }
    }

    func openProject(at path: String, engineRoot: String? = nil) async {
        await openProject(url: URL(fileURLWithPath: path), engineRoot: engineRoot)
    }

    func openProject(url: URL, engineRoot: String? = nil) async {
        isBusy = true
        launchError = nil
        pendingProposal = nil
        promptSaveNotice = nil
        eventTask?.cancel()
        eventTask = nil
        eventCursor = 0
        helper?.shutdown()
        let path = url.path
        guard beginProjectScope(for: url) else {
            launchError = "PromptForge needs folder access to open this project. Choose the project folder again to re-grant access."
            isBusy = false
            return
        }
        SecurityScopedProjectStore.save(url: url)
        let resolvedEngineRoot = resolveEngineRoot(projectURL: url, explicitEngineRoot: engineRoot)
        do {
            helper = try PromptForgeHelperClient(projectRoot: path, engineRoot: resolvedEngineRoot)
            self.engineRoot = resolvedEngineRoot
            UserDefaults.standard.set(path, forKey: "PromptForgeProjectPath")
            UserDefaults.standard.set(resolvedEngineRoot, forKey: "PromptForgeEngineRoot")
            projectPath = path
            selectedWorkspaceMode = .overview
            transcript.removeAll()
            appendTranscript(.system, "Project", "Opened \(path)")
            _ = try await helper?.send(method: "project.open") ?? [:]
            startEventStream()
            try await refreshStatus()
            try await refreshPrompts()
            if let prompt = selectedPrompt ?? prompts.first?.version {
                await openPrompt(prompt, announce: false)
            } else {
                appendTranscript(.system, "Project", "No prompt packs found. Use /new <name> to create one.")
            }
            if !UserDefaults.standard.bool(forKey: "PromptForgeCompletedOnboarding") {
                await loadSettings(openingMode: "onboarding")
            }
        } catch {
            helper?.shutdown()
            helper = nil
            projectPath = nil
            launchError = error.localizedDescription
            appendTranscript(.warning, "Launch error", error.localizedDescription)
        }
        isBusy = false
    }

    func saveSettings() {
        Task {
            await persistSettings()
        }
    }

    func launchCodexLogin() {
        settingsError = nil
        settingsNotice = nil
        let script = """
        tell application "Terminal"
            activate
            do script "codex login"
        end tell
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        do {
            try process.run()
            settingsNotice = "Opened Terminal for `codex login`. Refresh connection status after completing the flow."
        } catch {
            settingsError = "Could not launch Codex login: \(error.localizedDescription)"
        }
    }

    func clearKey(kind: String) {
        switch kind {
        case "openai":
            _ = KeychainSecretStore.delete(key: "OPENAI_API_KEY")
            openAIKeyDraft = ""
        case "openrouter":
            _ = KeychainSecretStore.delete(key: "OPENROUTER_API_KEY")
            openRouterKeyDraft = ""
        default:
            break
        }
        refreshLocalConnectionStatuses()
    }

    func openPrompt(_ prompt: String, announce: Bool) async {
        guard let helper else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let promptResult = try await helper.send(method: "prompt.get", params: ["prompt": prompt])
            applyPromptPayload(promptResult)
            let insightResult = try await helper.send(method: "insights.latest", params: ["prompt": prompt])
            applyInsightsPayload(insightResult)
            try await refreshStatus()
            if announce {
                appendTranscript(.system, "Prompt", "Opened prompt \(prompt)")
            }
        } catch {
            appendTranscript(.warning, "Prompt", error.localizedDescription)
        }
    }

    private func handleInput(_ rawText: String) async {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        appendTranscript(.user, "You", text)
        if text.hasPrefix("/") {
            await handleSlashCommand(text)
            return
        }
        await agentChat(text)
    }

    private func agentChat(_ request: String) async {
        guard let prompt = selectedPrompt, let helper else {
            appendTranscript(.warning, "PromptForge", "Choose a project and a prompt first.")
            return
        }
        guard await persistPromptWorkspace(showNoChangeNotice: false) else {
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let result = try await helper.send(
                method: "agent.chat",
                params: ["prompt": prompt, "request": request]
            )
            let chatPayload = result["chat"] as? [String: Any] ?? [:]
            let message = chatPayload["message"] as? String ?? ""
            let chatKind = chatPayload["kind"] as? String ?? "reply"

            if let proposal = proposalFromResult(result) {
                pendingProposal = proposal
                let changedFiles = proposal.changedFiles.isEmpty ? "No file changes." : "Files: \(proposal.changedFiles.joined(separator: ", "))"
                let summary = proposal.summary.isEmpty ? message : proposal.summary
                appendTranscript(.agent, "Proposal \(proposal.proposalID)", "\(summary)\n\n\(changedFiles)")
                if !proposal.diffPreview.isEmpty {
                    appendTranscript(.result, "Diff preview", proposal.diffPreview)
                }
            } else if !message.isEmpty {
                let title = chatKind == "reply" ? "PromptForge" : "Agent"
                appendTranscript(.agent, title, message)
            } else {
                throw HelperClientError.missingField("The helper did not return a message.")
            }

            if result["revision"] != nil || result["insights"] != nil {
                applyResultPayload(result)
            }
        } catch {
            appendTranscript(.warning, "Chat failed", error.localizedDescription)
        }
    }

    private func coachPrompt(_ request: String) async {
        guard let prompt = selectedPrompt, let helper else {
            appendTranscript(.warning, "PromptForge", "Choose a project and a prompt first.")
            return
        }
        guard await persistPromptWorkspace(showNoChangeNotice: false) else {
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let result = try await helper.send(
                method: "coach.reply",
                params: ["prompt": prompt, "request": request]
            )
            guard let reply = result["reply"] as? String, !reply.isEmpty else {
                throw HelperClientError.missingField("The helper did not return a reply.")
            }
            appendTranscript(.agent, "Coach", reply)
        } catch {
            appendTranscript(.warning, "Chat failed", error.localizedDescription)
        }
    }

    private func prepareEditProposal(_ request: String) async {
        guard let prompt = selectedPrompt, let helper else {
            appendTranscript(.warning, "PromptForge", "Choose a project and a prompt first.")
            return
        }
        guard await persistPromptWorkspace(showNoChangeNotice: false) else {
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let result = try await helper.send(
                method: "agent.prepare_edit",
                params: ["prompt": prompt, "request": request]
            )
            guard let proposal = proposalFromResult(result) else {
                throw HelperClientError.missingField("The helper did not return a proposal.")
            }
            pendingProposal = proposal
            let changedFiles = proposal.changedFiles.isEmpty ? "No file changes." : "Files: \(proposal.changedFiles.joined(separator: ", "))"
            appendTranscript(.agent, "Proposal \(proposal.proposalID)", "\(proposal.summary)\n\n\(changedFiles)")
            appendTranscript(.result, "Diff preview", proposal.diffPreview.isEmpty ? "No diff was produced." : proposal.diffPreview)
        } catch {
            appendTranscript(.warning, "Proposal failed", error.localizedDescription)
        }
    }

    private func startEventStream() {
        guard let helper else { return }
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    let response = try await helper.subscribe(after: eventCursor)
                    await MainActor.run {
                        self.eventCursor = max(self.eventCursor, response.cursor)
                        self.consume(events: response.events)
                    }
                } catch {
                    if Task.isCancelled {
                        return
                    }
                    await MainActor.run {
                        self.appendTranscript(.warning, "Event stream", error.localizedDescription)
                    }
                    return
                }
            }
        }
    }

    private func consume(events: [HelperEvent]) {
        for event in events {
            guard let method = event.payload["method"] else {
                continue
            }
            switch event.type {
            case "request.started":
                if let line = streamStartLine(for: method) {
                    appendTranscript(.system, "Activity", line)
                }
            case "request.completed":
                if let line = streamCompletedLine(for: method) {
                    appendTranscript(.result, "Activity", line)
                }
            case "request.failed":
                let detail = event.payload["error"] ?? "Unknown helper error."
                appendTranscript(.warning, "Activity", "\(method) failed: \(detail)")
            default:
                break
            }
        }
    }

    private func streamStartLine(for method: String) -> String? {
        switch method {
        case "agent.chat":
            return "Agent is working through your request."
        case "coach.reply":
            return "Thinking through prompt guidance."
        case "agent.prepare_edit":
            return "Preparing staged edit proposal."
        case "agent.apply_prepared_edit":
            return "Applying staged edit."
        case "bench.run_quick":
            return "Running quick benchmark."
        case "eval.run_full":
            return "Running full evaluation."
        case "prompts.create":
            return "Creating prompt pack."
        case "prompts.clone":
            return "Cloning prompt pack."
        case "prompts.export":
            return "Exporting prompt pack."
        case "revisions.restore":
            return "Restoring prompt revision."
        default:
            return nil
        }
    }

    private func streamCompletedLine(for method: String) -> String? {
        switch method {
        case "agent.chat":
            return "Agent finished the request."
        case "coach.reply":
            return "Returned prompt guidance."
        case "agent.prepare_edit":
            return "Prepared staged edit proposal."
        case "agent.apply_prepared_edit":
            return "Applied staged edit."
        case "bench.run_quick":
            return "Quick benchmark finished."
        case "eval.run_full":
            return "Full evaluation finished."
        case "prompts.create":
            return "Prompt pack created."
        case "prompts.clone":
            return "Prompt pack cloned."
        case "prompts.export":
            return "Prompt pack exported."
        case "revisions.restore":
            return "Prompt revision restored."
        default:
            return nil
        }
    }

    private func handleSlashCommand(_ commandLine: String) async {
        let parts = commandLine.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let command = parts.first?.lowercased() else { return }
        switch command {
        case "/help":
            appendTranscript(
                .system,
                "Commands",
                """
                /prompts
                /open <name>
                /new <name>
                /clone <source> <name>
                /status
                /coach <request>
                /edit <request>
                /save
                /prompt
                /template
                /bench
                /full
                /diff
                /failures
                /apply
                /discard
                /undo
                /export <name>

                Any message without a slash is treated as agent chat for the active prompt.
                """
            )
        case "/coach":
            let request = String(commandLine.dropFirst(command.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !request.isEmpty else {
                appendTranscript(.warning, "Command", "Usage: /coach <request>")
                return
            }
            await coachPrompt(request)
        case "/edit":
            let request = String(commandLine.dropFirst(command.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !request.isEmpty else {
                appendTranscript(.warning, "Command", "Usage: /edit <request>")
                return
            }
            await prepareEditProposal(request)
        case "/save":
            _ = await persistPromptWorkspace()
        case "/prompts":
            let list = prompts.map { "\($0.version)  \( $0.name )" }.joined(separator: "\n")
            appendTranscript(.system, "Prompt packs", list.isEmpty ? "No prompt packs in this project." : list)
        case "/open":
            guard parts.count >= 2 else {
                appendTranscript(.warning, "Command", "Usage: /open <name>")
                return
            }
            await openPrompt(parts[1], announce: true)
        case "/new":
            guard parts.count >= 2 else {
                appendTranscript(.warning, "Command", "Usage: /new <name>")
                return
            }
            await createPrompt(parts[1], fromPrompt: nil)
        case "/clone":
            guard parts.count >= 3 else {
                appendTranscript(.warning, "Command", "Usage: /clone <source> <name>")
                return
            }
            await clonePrompt(source: parts[1], target: parts[2])
        case "/status":
            do {
                try await refreshStatus()
                appendTranscript(
                    .system,
                    "Status",
                    "\(providerLine)\n\(authLine)\n\(sessionLine)\nLatest score: \(latestScoreLine)"
                )
            } catch {
                appendTranscript(.warning, "Status", error.localizedDescription)
            }
        case "/prompt":
            appendTranscript(.system, "System prompt", promptDraft.systemPrompt)
        case "/template":
            appendTranscript(.system, "User template", promptDraft.userTemplate)
        case "/bench":
            await runHelperMethod("bench.run_quick")
        case "/full":
            await runHelperMethod("eval.run_full")
        case "/diff":
            if let pendingProposal {
                appendTranscript(.system, "Pending diff", pendingProposal.diffPreview)
            } else {
                let diffText = benchmarkRows
                    .filter { $0.0 != "Latest score" }
                    .map { "\($0.0): \($0.1)" }
                    .joined(separator: "\n")
                appendTranscript(.system, "Latest benchmark delta", diffText.isEmpty ? "No diff available yet." : diffText)
            }
        case "/failures":
            let failureText = failureCases
                .map { "\($0.caseID) | score \($0.score) | \($0.reasons)\n\($0.summary)" }
                .joined(separator: "\n\n")
            appendTranscript(.system, "Failures", failureText.isEmpty ? "No hard-failing cases." : failureText)
        case "/apply":
            await applyPendingProposal()
        case "/discard":
            await discardPendingProposal()
        case "/undo":
            await undoLatestRevision()
        case "/export":
            guard parts.count >= 2 else {
                appendTranscript(.warning, "Command", "Usage: /export <name>")
                return
            }
            await exportPrompt(named: parts[1])
        default:
            appendTranscript(.warning, "Command", "Unknown command: \(command)")
        }
    }

    private func createPrompt(_ name: String, fromPrompt: String?) async {
        guard let helper else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            _ = try await helper.send(
                method: "prompts.create",
                params: ["prompt": name, "from_prompt": fromPrompt as Any]
            )
            try await refreshPrompts()
            await openPrompt(name, announce: true)
            selectedWorkspaceMode = .editor
        } catch {
            appendTranscript(.warning, "Create prompt", error.localizedDescription)
        }
    }

    private func clonePrompt(source: String, target: String) async {
        guard let helper else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            _ = try await helper.send(
                method: "prompts.clone",
                params: ["source": source, "name": target]
            )
            try await refreshPrompts()
            await openPrompt(target, announce: true)
            selectedWorkspaceMode = .editor
        } catch {
            appendTranscript(.warning, "Clone prompt", error.localizedDescription)
        }
    }

    private func applyPendingProposal() async {
        guard let helper, let prompt = selectedPrompt, let pendingProposal else {
            appendTranscript(.warning, "Apply", "There is no pending proposal to apply.")
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let result = try await helper.send(
                method: "agent.apply_prepared_edit",
                params: ["prompt": prompt, "proposal_id": pendingProposal.proposalID]
            )
            self.pendingProposal = nil
            applyResultPayload(result)
            await openPrompt(prompt, announce: false)
        } catch {
            appendTranscript(.warning, "Apply", error.localizedDescription)
        }
    }

    private func discardPendingProposal() async {
        guard let helper, let prompt = selectedPrompt, let pendingProposal else {
            appendTranscript(.warning, "Discard", "There is no pending proposal to discard.")
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            _ = try await helper.send(
                method: "agent.discard_prepared_edit",
                params: ["prompt": prompt, "proposal_id": pendingProposal.proposalID]
            )
            self.pendingProposal = nil
            appendTranscript(.system, "Discarded", "Proposal \(pendingProposal.proposalID) was discarded.")
        } catch {
            appendTranscript(.warning, "Discard", error.localizedDescription)
        }
    }

    private func runHelperMethod(_ method: String) async {
        guard let helper, let prompt = selectedPrompt else {
            appendTranscript(.warning, "PromptForge", "Choose a prompt first.")
            return
        }
        guard await persistPromptWorkspace(showNoChangeNotice: false) else {
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let result = try await helper.send(method: method, params: ["prompt": prompt])
            applyResultPayload(result)
            await openPrompt(prompt, announce: false)
        } catch {
            appendTranscript(.warning, method, error.localizedDescription)
        }
    }

    private func undoLatestRevision() async {
        guard let helper, let prompt = selectedPrompt else {
            appendTranscript(.warning, "Undo", "Choose a prompt first.")
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let result = try await helper.send(method: "revisions.list", params: ["prompt": prompt])
            guard let revisions = result["revisions"] as? [[String: Any]], revisions.count >= 2 else {
                appendTranscript(.warning, "Undo", "There is no earlier revision to restore.")
                return
            }
            guard let revisionID = revisions[revisions.count - 2]["revision_id"] as? String else {
                throw HelperClientError.missingField("The helper did not return a revision id.")
            }
            let restore = try await helper.send(
                method: "revisions.restore",
                params: ["prompt": prompt, "revision_id": revisionID]
            )
            applyResultPayload(restore)
            await openPrompt(prompt, announce: false)
        } catch {
            appendTranscript(.warning, "Undo", error.localizedDescription)
        }
    }

    private func exportPrompt(named name: String) async {
        guard let helper, let prompt = selectedPrompt else {
            appendTranscript(.warning, "Export", "Choose a prompt first.")
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let result = try await helper.send(
                method: "prompts.export",
                params: ["prompt": prompt, "name": name]
            )
            let exportedPath = result["exported"] as? String ?? name
            try await refreshPrompts()
            appendTranscript(.result, "Exported", "Saved prompt pack to \(exportedPath)")
        } catch {
            appendTranscript(.warning, "Export", error.localizedDescription)
        }
    }

    private func loadSettings(openingMode: String) async {
        guard let helper else {
            settingsError = "Open a project before editing settings."
            return
        }
        isBusy = true
        settingsError = nil
        settingsNotice = nil
        defer { isBusy = false }
        do {
            let payload = try await helper.send(method: "settings.get")
            applySettingsPayload(payload)
            settingsMode = openingMode
            showSettings = true
        } catch {
            settingsError = error.localizedDescription
            appendTranscript(.warning, "Settings", error.localizedDescription)
        }
    }

    private func persistSettings() async {
        guard let helper else {
            settingsError = "Open a project before saving settings."
            return
        }
        isBusy = true
        settingsError = nil
        settingsNotice = nil
        defer { isBusy = false }

        let openAIKey = openAIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let openRouterKey = openRouterKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !openAIKey.isEmpty {
            _ = KeychainSecretStore.write(key: "OPENAI_API_KEY", value: openAIKey)
            openAIKeyDraft = ""
        }
        if !openRouterKey.isEmpty {
            _ = KeychainSecretStore.write(key: "OPENROUTER_API_KEY", value: openRouterKey)
            openRouterKeyDraft = ""
        }

        do {
            let onboardingMode = isOnboarding
            let currentProjectPath = projectPath
            let currentEngineRoot = engineRoot
            let payload = try await helper.send(
                method: "settings.update",
                params: [
                    "name": settingsDraft.projectName,
                    "preferred_provider": settingsDraft.provider,
                    "preferred_judge_provider": settingsDraft.judgeProvider,
                    "preferred_generation_model": settingsDraft.generationModel,
                    "preferred_judge_model": settingsDraft.judgeModel,
                    "quick_benchmark_dataset": settingsDraft.quickBenchmarkDataset,
                    "full_evaluation_dataset": settingsDraft.fullEvaluationDataset,
                ]
            )
            applySettingsPayload(payload)
            settingsNotice = "Settings saved."
            if onboardingMode {
                UserDefaults.standard.set(true, forKey: "PromptForgeCompletedOnboarding")
            }
            showSettings = false
            if let currentProjectPath {
                await openProject(at: currentProjectPath, engineRoot: currentEngineRoot)
            }
        } catch {
            settingsError = error.localizedDescription
        }
    }

    private func persistPromptWorkspace(showNoChangeNotice: Bool = true) async -> Bool {
        guard let helper, let prompt = selectedPrompt else {
            appendTranscript(.warning, "Save prompt", "Choose a prompt before saving.")
            return false
        }
        guard promptHasUnsavedChanges else {
            if showNoChangeNotice {
                promptSaveNotice = "No prompt changes to save."
            }
            return true
        }
        isBusy = true
        promptSaveNotice = nil
        defer { isBusy = false }
        do {
            let result = try await helper.send(
                method: "prompt.save",
                params: [
                    "prompt": prompt,
                    "system_prompt": promptDraft.systemPrompt,
                    "user_template": promptDraft.userTemplate,
                    "purpose": promptDraft.purpose,
                    "expected_behavior": promptDraft.expectedBehavior,
                    "success_criteria": promptDraft.successCriteria,
                ]
            )
            applyPromptPayload(result)
            applyResultPayload(result)
            promptSaveNotice = "Saved prompt workspace."
            appendTranscript(.result, "Prompt saved", "Saved overview fields and prompt files for \(prompt).")
            return true
        } catch {
            promptSaveNotice = error.localizedDescription
            appendTranscript(.warning, "Save prompt", error.localizedDescription)
            return false
        }
    }

    private func applySettingsPayload(_ payload: [String: Any]) {
        if let settingsPayload = payload["settings"] as? [String: Any] {
            settingsDraft = AppSettingsDraft(
                projectName: settingsPayload["name"] as? String ?? projectName,
                provider: settingsPayload["preferred_provider"] as? String ?? "openai",
                judgeProvider: settingsPayload["preferred_judge_provider"] as? String ?? settingsDraft.provider,
                generationModel: settingsPayload["preferred_generation_model"] as? String ?? "gpt-5.4",
                judgeModel: settingsPayload["preferred_judge_model"] as? String ?? "gpt-5-mini",
                quickBenchmarkDataset: settingsPayload["quick_benchmark_dataset"] as? String ?? "datasets/core.jsonl",
                fullEvaluationDataset: settingsPayload["full_evaluation_dataset"] as? String ?? "datasets/core.jsonl"
            )
        }
        if let authPayload = payload["auth"] as? [String: Any] {
            applyConnectionPayload(authPayload)
        }
    }

    private func applyConnectionPayload(_ authPayload: [String: Any]) {
        let rawConnections = authPayload["connections"] as? [String: Any] ?? [:]
        let connectionPayloads = rawConnections.reduce(into: [String: [String: Any]]()) { partialResult, item in
            if let payload = item.value as? [String: Any] {
                partialResult[item.key] = payload
            }
        }
        let openAIKeyLoaded = KeychainSecretStore.has(key: "OPENAI_API_KEY")
        let openRouterKeyLoaded = KeychainSecretStore.has(key: "OPENROUTER_API_KEY")
        connectionStatuses = [
            ProviderConnectionStatus(
                id: "openai",
                label: "OpenAI",
                ready: (connectionPayloads["openai"]?["ready"] as? Bool ?? false) || openAIKeyLoaded,
                detail: connectionPayloads["openai"]?["detail"] as? String ?? (openAIKeyLoaded ? "API key available." : "API key missing."),
                source: openAIKeyLoaded ? "Keychain" : "Not loaded"
            ),
            ProviderConnectionStatus(
                id: "openrouter",
                label: "OpenRouter",
                ready: (connectionPayloads["openrouter"]?["ready"] as? Bool ?? false) || openRouterKeyLoaded,
                detail: connectionPayloads["openrouter"]?["detail"] as? String ?? (openRouterKeyLoaded ? "API key available." : "API key missing."),
                source: openRouterKeyLoaded ? "Keychain" : "Not loaded"
            ),
            ProviderConnectionStatus(
                id: "codex",
                label: "Codex",
                ready: connectionPayloads["codex"]?["ready"] as? Bool ?? false,
                detail: connectionPayloads["codex"]?["detail"] as? String ?? "Codex status unknown.",
                source: "Local login session"
            ),
        ]
    }

    private func refreshLocalConnectionStatuses() {
        applyConnectionPayload([:])
    }

    private func refreshPrompts() async throws {
        guard let helper else { return }
        let promptResult = try await helper.send(method: "prompts.list")
        guard let promptPayloads = promptResult["prompts"] as? [[String: Any]] else {
            throw HelperClientError.missingField("The helper did not return a prompt list.")
        }
        prompts = promptPayloads.compactMap { payload in
            guard let version = payload["version"] as? String else { return nil }
            let name = payload["name"] as? String ?? version
            let description = payload["description"] as? String ?? ""
            return PromptSummaryModel(version: version, name: name, description: description)
        }
        if selectedPrompt == nil {
            selectedPrompt = prompts.first?.version
        }
    }

    private func refreshStatus() async throws {
        guard let helper else { return }
        let statusPayload = try await helper.send(method: "status.get")
        guard
            let project = statusPayload["project"] as? [String: Any],
            let metadata = project["metadata"] as? [String: Any]
        else {
            throw HelperClientError.invalidResponse
        }
        projectName = metadata["name"] as? String ?? "PromptForge Project"
        selectedPrompt = statusPayload["active_prompt"] as? String ?? selectedPrompt
        sessionLine = "session \(statusPayload["active_session"] as? String ?? "--")"
        if
            let auth = statusPayload["auth"] as? [String: Any],
            let provider = auth["provider"] as? [String: Any],
            let judge = auth["judge"] as? [String: Any]
        {
            let providerName = provider["name"] as? String ?? "--"
            let judgeName = judge["name"] as? String ?? "--"
            providerLine = "\(providerName) -> judge \(judgeName)"
            let providerDetail = provider["detail"] as? String ?? ""
            authLine = providerDetail
            applyConnectionPayload(auth)
        }
        statusSubtitle = metadata["full_evaluation_dataset"] as? String ?? "Ready"
    }

    private func refreshBenchmarkHistory() async throws {
        guard let helper, let prompt = selectedPrompt else {
            benchmarkHistory = []
            benchmarkTrend = []
            return
        }
        let payload = try await helper.send(method: "benchmarks.history", params: ["prompt": prompt])
        let historyPayloads = payload["history"] as? [[String: Any]] ?? []
        let trendPayloads = payload["trend"] as? [[String: Any]] ?? []
        benchmarkHistory = historyPayloads.compactMap { item in
            guard
                let revisionID = item["revision_id"] as? String,
                let createdAt = item["created_at"] as? String,
                let source = item["source"] as? String
            else {
                return nil
            }
            return BenchmarkHistoryEntry(
                revisionID: revisionID,
                createdAt: createdAt,
                source: source,
                note: item["note"] as? String ?? "",
                score: item["score"] as? Double,
                scoreDeltaVsBaseline: item["score_delta_vs_baseline"] as? Double,
                passRate: item["pass_rate"] as? Double,
                hardFailRate: item["hard_fail_rate"] as? Double,
                fullScore: item["full_score"] as? Double
            )
        }
        benchmarkTrend = trendPayloads.compactMap { item in
            guard
                let revisionID = item["revision_id"] as? String,
                let score = item["score"] as? Double
            else {
                return nil
            }
            return BenchmarkTrendPoint(revisionID: revisionID, score: score)
        }
    }

    private func applyPromptPayload(_ result: [String: Any]) {
        guard let payload = result["prompt"] as? [String: Any] else { return }
        selectedPrompt = payload["version"] as? String ?? selectedPrompt
        currentPromptName = payload["name"] as? String ?? selectedPrompt ?? ""
        currentPromptDescription = payload["description"] as? String ?? ""
        promptRootPath = payload["root"] as? String ?? ""
        systemPrompt = payload["system_prompt"] as? String ?? ""
        userTemplate = payload["user_template"] as? String ?? ""
        promptDraft = PromptWorkspaceDraft(
            purpose: payload["purpose"] as? String ?? "",
            expectedBehavior: payload["expected_behavior"] as? String ?? "",
            successCriteria: payload["success_criteria"] as? String ?? "",
            systemPrompt: systemPrompt,
            userTemplate: userTemplate
        )
        savedPromptDraft = promptDraft
        promptFiles = payload["files"] as? [String] ?? []
        promptSaveNotice = nil
        Task {
            try? await refreshBenchmarkHistory()
        }
    }

    private func applyInsightsPayload(_ result: [String: Any]) {
        let insightObject = (result["insights"] as? [String: Any]) ?? result
        if let sessionID = insightObject["session_id"] as? String {
            sessionLine = "session \(sessionID)"
        }
        if let statusRows = insightObject["status_rows"] as? [[Any]], !statusRows.isEmpty {
            benchmarkRows = statusRows.compactMap { row in
                guard row.count >= 2, let key = row[0] as? String, let value = row[1] as? String else {
                    return nil
                }
                return (key, value)
            }
            latestScoreLine = benchmarkRows.first(where: { $0.0 == "Latest score" })?.1 ?? latestScoreLine
        }
        if let diffRows = insightObject["diff_rows"] as? [[Any]], !diffRows.isEmpty {
            let parsed = diffRows.compactMap { row -> (String, String)? in
                guard row.count >= 2, let key = row[0] as? String, let value = row[1] as? String else {
                    return nil
                }
                return (key, value)
            }
            latestDeltaLine = parsed.first(where: { $0.0 == "Score delta" })?.1 ?? latestDeltaLine
        }
        weakCases = parseCases(insightObject["weak_cases"] as? [[String: Any]] ?? [])
        failureCases = parseCases(insightObject["failures"] as? [[String: Any]] ?? [])
    }

    private func applyResultPayload(_ result: [String: Any]) {
        if let resultPayload = result["result"] as? [String: Any] {
            let summary = resultPayload["summary"] as? String ?? "Completed."
            let diffPreview = resultPayload["diff_preview"] as? String ?? ""
            appendTranscript(.result, "Result", summary)
            if !diffPreview.isEmpty {
                appendTranscript(.result, "Diff", diffPreview)
            }
        } else if let revision = result["revision"] as? [String: Any] {
            let revisionID = revision["revision_id"] as? String ?? "revision"
            appendTranscript(.result, "Run complete", "Updated \(revisionID).")
        }
        if result["insights"] != nil {
            applyInsightsPayload(result)
        }
        Task {
            try? await refreshBenchmarkHistory()
        }
    }

    private func proposalFromResult(_ result: [String: Any]) -> PreparedProposal? {
        guard let proposal = result["proposal"] as? [String: Any] else { return nil }
        guard let proposalID = proposal["proposal_id"] as? String else { return nil }
        let summary = proposal["summary"] as? String ?? "Prepared a prompt proposal."
        let diffPreview = proposal["diff_preview"] as? String ?? ""
        let changedFiles = proposal["changed_files"] as? [String] ?? []
        return PreparedProposal(
            proposalID: proposalID,
            summary: summary,
            diffPreview: diffPreview,
            changedFiles: changedFiles
        )
    }

    private func parseCases(_ payload: [[String: Any]]) -> [CaseIssue] {
        payload.compactMap { item in
            guard let caseID = item["case_id"] as? String else { return nil }
            return CaseIssue(
                caseID: caseID,
                score: item["score"] as? String ?? "--",
                hardFailRate: item["hard_fail_rate"] as? String ?? "--",
                reasons: item["reasons"] as? String ?? "--",
                summary: item["summary"] as? String ?? "--"
            )
        }
    }

    private func appendTranscript(_ role: TranscriptRole, _ title: String, _ body: String) {
        transcript.append(TranscriptEntry(role: role, title: title, body: body))
    }
}
