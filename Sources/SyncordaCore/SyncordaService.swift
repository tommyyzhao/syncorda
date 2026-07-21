import Foundation

@available(macOS 14.2, *)
public final class SyncordaService: @unchecked Sendable {
    private let engine = SyncordaEngine()
    private let profiles: ProfileStore
    private let stateLock = NSLock()
    private var activeConfiguration: RouteConfiguration?
    private var configurationRevision: UInt64 = 0
    private var server: LocalControlServer?

    public init(profileStore: ProfileStore = ProfileStore()) {
        self.profiles = profileStore
    }

    deinit { server?.stop() }

    public func startControlServer(path: String = SyncordaControlSocket.defaultPath) throws {
        guard server == nil else { return }
        let server = LocalControlServer(path: path) { [weak self] request in
            self?.handle(request) ?? ControlResponse(ok: false, message: "Syncorda service has stopped.")
        }
        try server.start()
        self.server = server
    }

    public func start(_ configuration: RouteConfiguration) throws -> RouteStatus {
        try engine.start(configuration)
        stateLock.lock()
        activeConfiguration = configuration
        configurationRevision &+= 1
        stateLock.unlock()
        return engine.status()
    }

    public func stop() -> RouteStatus {
        engine.stop()
        return engine.status()
    }

    public func update(_ route: OutputRoute) -> RouteStatus {
        stateLock.lock()
        if var configuration = activeConfiguration,
           let index = configuration.outputs.firstIndex(where: { $0.deviceUID == route.deviceUID }) {
            configuration.outputs[index] = route
            activeConfiguration = configuration
            configurationRevision &+= 1
        }
        stateLock.unlock()
        engine.update(route)
        return engine.status()
    }

    public func update(
        deviceUID: String,
        extraDelayMilliseconds: Double? = nil,
        gain: Float? = nil,
        isEnabled: Bool? = nil,
        isMuted: Bool? = nil
    ) throws -> RouteStatus {
        stateLock.lock()
        guard var configuration = activeConfiguration,
              let index = configuration.outputs.firstIndex(where: { $0.deviceUID == deviceUID }) else {
            stateLock.unlock()
            throw SyncordaAudioError.deviceNotFound(deviceUID)
        }
        if let extraDelayMilliseconds { configuration.outputs[index].extraDelayMilliseconds = max(0, min(1_000, extraDelayMilliseconds)) }
        if let gain { configuration.outputs[index].gain = max(0, min(4, gain)) }
        if let isEnabled { configuration.outputs[index].isEnabled = isEnabled }
        if let isMuted { configuration.outputs[index].isMuted = isMuted }
        let route = configuration.outputs[index]
        activeConfiguration = configuration
        configurationRevision &+= 1
        stateLock.unlock()
        engine.update(route)
        return engine.status()
    }

    public func status() -> RouteStatus { engine.status() }

    public func configuration() -> RouteConfiguration? {
        stateLock.lock(); defer { stateLock.unlock() }
        return activeConfiguration
    }

    public func snapshot() -> RouteSnapshot {
        stateLock.lock(); defer { stateLock.unlock() }
        return RouteSnapshot(configuration: activeConfiguration, revision: configurationRevision)
    }

    public func handle(_ request: ControlRequest) -> ControlResponse {
        do {
            guard let command = ControlCommand.parse(request) else { return ControlResponse(ok: false, message: "Unknown command '\(request.command)'.") }
            switch command {
            case .status:
                return ControlResponse(ok: true, message: "OK", status: status())
            case .stop:
                return ControlResponse(ok: true, message: "Stopped", status: stop())
            case .start:
                guard let configuration = request.configuration else { return ControlResponse(ok: false, message: "The start command requires a route configuration.") }
                return ControlResponse(ok: true, message: "Started", status: try start(configuration))
            case .update:
                if let output = request.output {
                    return ControlResponse(ok: true, message: "Updated", status: update(output))
                }
                guard let deviceUID = request.outputDeviceUID else { return ControlResponse(ok: false, message: "The update command requires an output device.") }
                return ControlResponse(
                    ok: true,
                    message: "Updated",
                    status: try update(
                        deviceUID: deviceUID,
                        extraDelayMilliseconds: request.extraDelayMilliseconds,
                        gain: request.gain,
                        isEnabled: request.isEnabled,
                        isMuted: request.isMuted
                    )
                )
            case .saveProfile:
                guard let name = request.profileName, !name.isEmpty, let configuration = request.configuration else { return ControlResponse(ok: false, message: "Saving a profile requires --name and a route configuration.") }
                try profiles.save(RouteProfile(name: name, configuration: configuration))
                return ControlResponse(ok: true, message: "Saved profile '\(name)'.", status: status())
            case .applyProfile:
                guard let name = request.profileName, let profile = try profiles.named(name) else { return ControlResponse(ok: false, message: "Profile not found.") }
                return ControlResponse(ok: true, message: "Applied profile '\(profile.name)'.", status: try start(profile.configuration))
            }
        } catch {
            return ControlResponse(ok: false, message: error.localizedDescription, status: status())
        }
    }
}
