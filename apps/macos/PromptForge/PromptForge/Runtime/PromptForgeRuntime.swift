import Foundation

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

enum EngineRuntimeSource: Equatable {
    case explicit
    case bundled
    case saved
    case projectFallback
}

struct EngineRuntimeManifest: Decodable, Equatable {
    let schemaVersion: Int
    let generatedAt: String?
    let pythonExecutable: String
    let helperModule: String
    let pythonPathEntries: [String]
    let pathEntries: [String]
    let codexBinary: String?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAt = "generated_at"
        case pythonExecutable = "python_executable"
        case helperModule = "helper_module"
        case pythonPathEntries = "python_path_entries"
        case pathEntries = "path_entries"
        case codexBinary = "codex_binary"
    }
}

struct EngineRuntimeConfiguration: Equatable {
    let rootPath: String
    let pythonExecutable: String
    let helperModule: String
    let pythonPathEntries: [String]
    let pathEntries: [String]
    let codexBinary: String?
}

struct EngineRuntimeSelection: Equatable {
    let rootPath: String
    let source: EngineRuntimeSource
    let configuration: EngineRuntimeConfiguration
}

enum EngineRuntimeLocator {
    static let bundledDirectoryName = "engine"
    static let manifestFileName = "runtime-manifest.json"

    static func bundledEngineRoot(resourceURL: URL?) -> String? {
        guard let resourceURL else {
            return nil
        }
        let candidate = resourceURL.appendingPathComponent(bundledDirectoryName).path
        return configuration(for: candidate) != nil ? standardized(candidate) : nil
    }

    static func isValidEngineRoot(_ root: String) -> Bool {
        configuration(for: root) != nil
    }

    static func resolve(
        projectURL: URL,
        explicitEngineRoot: String?,
        savedEngineRoot: String?,
        bundleResourceURL: URL? = Bundle.main.resourceURL
    ) -> EngineRuntimeSelection? {
        let candidates: [(String?, EngineRuntimeSource)] = [
            (explicitEngineRoot, .explicit),
            (bundledEngineRoot(resourceURL: bundleResourceURL), .bundled),
            (savedEngineRoot, .saved),
        ]
        var seen = Set<String>()
        for (candidate, source) in candidates {
            guard let candidate, !candidate.isEmpty else {
                continue
            }
            let standardizedCandidate = standardized(candidate)
            if !seen.insert(standardizedCandidate).inserted {
                continue
            }
            if let configuration = configuration(for: standardizedCandidate) {
                return EngineRuntimeSelection(rootPath: standardizedCandidate, source: source, configuration: configuration)
            }
        }
#if DEBUG
        let projectCandidate = standardized(projectURL.path)
        if seen.insert(projectCandidate).inserted, let configuration = configuration(for: projectCandidate) {
            return EngineRuntimeSelection(rootPath: projectCandidate, source: .projectFallback, configuration: configuration)
        }
#endif
        return nil
    }

    static var missingRuntimeMessage: String {
        "PromptForge could not find a usable bundled runtime. Rebuild the app so it includes the packaged engine, or pass a valid --engine-root in a local debug run."
    }

    private static func standardized(_ path: String) -> String {
        URL(fileURLWithPath: NSString(string: path).expandingTildeInPath).standardizedFileURL.path
    }

    static func configuration(for root: String) -> EngineRuntimeConfiguration? {
        let standardizedRoot = standardized(root)
        let rootURL = URL(fileURLWithPath: standardizedRoot)
        let manifestURL = rootURL.appendingPathComponent(manifestFileName)

        if
            let data = try? Data(contentsOf: manifestURL),
            let manifest = try? JSONDecoder().decode(EngineRuntimeManifest.self, from: data)
        {
            let pythonExecutable = rootURL.appendingPathComponent(manifest.pythonExecutable).path
            guard FileManager.default.isExecutableFile(atPath: pythonExecutable) else {
                return nil
            }

            let pythonPathEntries = manifest.pythonPathEntries.map { rootURL.appendingPathComponent($0).path }
            guard !pythonPathEntries.isEmpty else {
                return nil
            }

            let pathEntries = manifest.pathEntries.map { rootURL.appendingPathComponent($0).path }
            let codexBinary = manifest.codexBinary.map { rootURL.appendingPathComponent($0).path }

            if let codexBinary, !FileManager.default.isExecutableFile(atPath: codexBinary) {
                return nil
            }

            return EngineRuntimeConfiguration(
                rootPath: standardizedRoot,
                pythonExecutable: pythonExecutable,
                helperModule: manifest.helperModule,
                pythonPathEntries: pythonPathEntries,
                pathEntries: pathEntries,
                codexBinary: codexBinary
            )
        }

        let pythonExecutable = rootURL.appendingPathComponent(".venv/bin/python").path
        let helperModule = rootURL.appendingPathComponent("src/promptforge/helper/server.py").path
        guard
            FileManager.default.isExecutableFile(atPath: pythonExecutable),
            FileManager.default.fileExists(atPath: helperModule)
        else {
            return nil
        }

        return EngineRuntimeConfiguration(
            rootPath: standardizedRoot,
            pythonExecutable: pythonExecutable,
            helperModule: "promptforge.helper.server",
            pythonPathEntries: [rootURL.appendingPathComponent("src").path],
            pathEntries: [],
            codexBinary: nil
        )
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

enum PromptForgeRuntimeBackend: String, Equatable {
    case pythonSocket
    case nativeXPC

    var displayName: String {
        switch self {
        case .pythonSocket:
            return "Python socket helper"
        case .nativeXPC:
            return "native Swift helper"
        }
    }
}

enum PromptForgeServiceMethod: String, CaseIterable {
    case eventsSubscribe = "events.subscribe"
    case health = "health"
    case statusGet = "status.get"
    case settingsGet = "settings.get"
    case connectionsRefresh = "connections.refresh"
    case connectionsCodexDeviceAuth = "connections.codex.device_auth"
    case connectionsCodexLoginAPIKey = "connections.codex.login_api_key"
    case settingsUpdate = "settings.update"
    case projectOpen = "project.open"
    case projectCreate = "project.create"
    case promptsList = "prompts.list"
    case promptsCreate = "prompts.create"
    case promptsClone = "prompts.clone"
    case promptsImport = "prompts.import"
    case promptsExport = "prompts.export"
    case promptGet = "prompt.get"
    case promptSave = "prompt.save"
    case scenariosList = "scenarios.list"
    case scenariosGet = "scenarios.get"
    case scenariosCreate = "scenarios.create"
    case scenariosSave = "scenarios.save"
    case playgroundRun = "playground.run"
    case reviewRunSuite = "review.run_suite"
    case reviewLatest = "review.latest"
    case builderActions = "builder.actions"
    case decisionsList = "decisions.list"
    case decisionsRecord = "decisions.record"
    case decisionsPromote = "decisions.promote"
    case agentPrepareEdit = "agent.prepare_edit"
    case coachReply = "coach.reply"
    case agentChat = "agent.chat"
    case agentApplyPreparedEdit = "agent.apply_prepared_edit"
    case agentDiscardPreparedEdit = "agent.discard_prepared_edit"
    case benchRunQuick = "bench.run_quick"
    case evalRunFull = "eval.run_full"
    case revisionsList = "revisions.list"
    case revisionsRestore = "revisions.restore"
    case insightsLatest = "insights.latest"
    case insightsFailures = "insights.failures"
}

protocol PromptForgeAgentTransport: AnyObject {
    var backend: PromptForgeRuntimeBackend { get }
    func shutdown()
    func send(method: String, params: [String: Any]) async throws -> [String: Any]
    func subscribe(after cursor: Int, timeoutSeconds: Double) async throws -> (cursor: Int, events: [HelperEvent])
}

extension PromptForgeAgentTransport {
    func send(method: String) async throws -> [String: Any] {
        try await send(method: method, params: [:])
    }

    func send(method: PromptForgeServiceMethod, params: [String: Any] = [:]) async throws -> [String: Any] {
        try await send(method: method.rawValue, params: params)
    }

    func subscribe(after cursor: Int) async throws -> (cursor: Int, events: [HelperEvent]) {
        try await subscribe(after: cursor, timeoutSeconds: 15)
    }
}

enum PromptForgeTransportFactory {
    static func makeTransport(
        projectRoot: String,
        runtimeSelection: EngineRuntimeSelection
    ) throws -> any PromptForgeAgentTransport {
        try PythonSocketAgentTransport(projectRoot: projectRoot, engineRoot: runtimeSelection.rootPath)
    }
}
