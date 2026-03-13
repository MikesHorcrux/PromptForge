import Darwin
import Foundation

final class PythonSocketAgentTransport: PromptForgeAgentTransport {
    let backend: PromptForgeRuntimeBackend = .pythonSocket

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
            method: PromptForgeServiceMethod.eventsSubscribe,
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
        guard let runtimeConfiguration = EngineRuntimeLocator.configuration(for: engineRoot) else {
            throw HelperClientError.helperLaunchFailed(EngineRuntimeLocator.missingRuntimeMessage)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: runtimeConfiguration.pythonExecutable)
        process.arguments = [
            "-m",
            runtimeConfiguration.helperModule,
            "--project",
            projectRoot,
            "--socket",
            socketPath,
            "--token",
            token,
        ]

        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = Pipe()

        var environment = ProcessInfo.processInfo.environment
        let pythonPath = runtimeConfiguration.pythonPathEntries.joined(separator: ":")
        if !pythonPath.isEmpty {
            if let existing = environment["PYTHONPATH"], !existing.isEmpty {
                environment["PYTHONPATH"] = "\(pythonPath):\(existing)"
            } else {
                environment["PYTHONPATH"] = pythonPath
            }
        }
        let bundledPath = runtimeConfiguration.pathEntries.joined(separator: ":")
        if !bundledPath.isEmpty {
            if let existing = environment["PATH"], !existing.isEmpty {
                environment["PATH"] = "\(bundledPath):\(existing)"
            } else {
                environment["PATH"] = bundledPath
            }
        }
        environment["PF_ENGINE_ROOT"] = engineRoot
        if let codexBinary = runtimeConfiguration.codexBinary {
            environment["PF_CODEX_BIN"] = codexBinary
        }
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
                Darwin.connect(socketFD, sockaddrPointer, addressLength)
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
