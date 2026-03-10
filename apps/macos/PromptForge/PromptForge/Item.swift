import AppKit
import Combine
import Foundation
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
}

@MainActor
final class PromptForgeAppModel: ObservableObject {
    @Published var projectPath: String?
    @Published var projectName: String = "PromptForge"
    @Published var draftMessage: String = ""
    @Published var prompts: [PromptSummaryModel] = []
    @Published var selectedPrompt: String?
    @Published var systemPrompt: String = ""
    @Published var userTemplate: String = ""
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

    private var helper: PromptForgeHelperClient?
    private var engineRoot: String?

    init(initialProjectPath: String?, initialEngineRoot: String?) {
        self.engineRoot = initialEngineRoot ?? UserDefaults.standard.string(forKey: "PromptForgeEngineRoot")
        self.projectPath = nil
        if let initialProjectPath {
            Task {
                await openProject(at: initialProjectPath, engineRoot: initialEngineRoot)
            }
        }
    }

    var savedProjectHint: String? {
        UserDefaults.standard.string(forKey: "PromptForgeProjectPath")
    }

    func chooseProjectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                await openProject(at: url.path)
            }
        }
    }

    func createPromptShortcut() {
        submitText("/new draft-\(Int(Date().timeIntervalSince1970))")
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

    func openProject(at path: String, engineRoot: String? = nil) async {
        isBusy = true
        launchError = nil
        pendingProposal = nil
        helper?.shutdown()

        let resolvedEngineRoot = engineRoot ?? self.engineRoot ?? path
        do {
            helper = try PromptForgeHelperClient(projectRoot: path, engineRoot: resolvedEngineRoot)
            self.engineRoot = resolvedEngineRoot
            UserDefaults.standard.set(path, forKey: "PromptForgeProjectPath")
            UserDefaults.standard.set(resolvedEngineRoot, forKey: "PromptForgeEngineRoot")
            projectPath = path
            transcript.removeAll()
            appendTranscript(.system, "Project", "Opened \(path)")
            _ = try await helper?.send(method: "project.open") ?? [:]
            try await refreshStatus()
            try await refreshPrompts()
            if let prompt = selectedPrompt ?? prompts.first?.version {
                await openPrompt(prompt, announce: false)
            } else {
                appendTranscript(.system, "Project", "No prompt packs found. Use /new <name> to create one.")
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
        guard let prompt = selectedPrompt, let helper else {
            appendTranscript(.warning, "PromptForge", "Choose a project and a prompt first.")
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let result = try await helper.send(
                method: "agent.prepare_edit",
                params: ["prompt": prompt, "request": text]
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
                """
            )
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
            appendTranscript(.system, "System prompt", systemPrompt)
        case "/template":
            appendTranscript(.system, "User template", userTemplate)
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
        }
        statusSubtitle = metadata["full_evaluation_dataset"] as? String ?? "Ready"
    }

    private func applyPromptPayload(_ result: [String: Any]) {
        guard let payload = result["prompt"] as? [String: Any] else { return }
        selectedPrompt = payload["version"] as? String ?? selectedPrompt
        systemPrompt = payload["system_prompt"] as? String ?? ""
        userTemplate = payload["user_template"] as? String ?? ""
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
