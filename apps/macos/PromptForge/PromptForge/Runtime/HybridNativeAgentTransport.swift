import Foundation

final class HybridNativeAgentTransport: PromptForgeAgentTransport {
    static var fallbackRequiredMessage: String {
#if DEBUG
        "This action still requires the packaged engine. Rebuild the app with the bundled runtime, or pass a valid --engine-root for local debug runs."
#else
        "This action requires the bundled runtime. Reinstall PromptForge or use an official build."
#endif
    }

    let backend: PromptForgeRuntimeBackend

    private let projectRoot: String
    private let runtimeSelection: EngineRuntimeSelection?
    private let nativeService: NativeProjectService
    private var fallbackTransport: PythonSocketAgentTransport?

    init(projectRoot: String, runtimeSelection: EngineRuntimeSelection?) throws {
        self.projectRoot = projectRoot
        self.runtimeSelection = runtimeSelection
        self.backend = runtimeSelection == nil ? .nativeSwift : .nativeHybrid
        self.nativeService = try NativeProjectService(
            projectRoot: projectRoot,
            codexBinary: runtimeSelection?.configuration.codexBinary
        )
    }

    deinit {
        shutdown()
    }

    func shutdown() {
        fallbackTransport?.shutdown()
        fallbackTransport = nil
    }

    func send(method: String, params: [String: Any]) async throws -> [String: Any] {
        if let typedMethod = PromptForgeServiceMethod(rawValue: method), nativeService.supports(typedMethod) {
            return try nativeService.handle(method: typedMethod, params: params)
        }
        return try await fallback().send(method: method, params: params)
    }

    func subscribe(after cursor: Int, timeoutSeconds: Double) async throws -> (cursor: Int, events: [HelperEvent]) {
        guard let fallbackTransport else {
            let timeout = max(timeoutSeconds, 0)
            if timeout > 0 {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            }
            return (cursor, [])
        }
        return try await fallbackTransport.subscribe(after: cursor, timeoutSeconds: timeoutSeconds)
    }

    private func fallback() throws -> PythonSocketAgentTransport {
        if let fallbackTransport {
            return fallbackTransport
        }
        guard let runtimeSelection else {
            throw HelperClientError.requestRejected(Self.fallbackRequiredMessage)
        }
        let transport = try PythonSocketAgentTransport(projectRoot: projectRoot, engineRoot: runtimeSelection.rootPath)
        fallbackTransport = transport
        return transport
    }
}
