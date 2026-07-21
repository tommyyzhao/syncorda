import Foundation

public struct ControlRequest: Codable, Equatable, Sendable {
    public var command: String
    public var configuration: RouteConfiguration?
    public var output: OutputRoute?
    public var outputDeviceUID: String?
    public var extraDelayMilliseconds: Double?
    public var gain: Float?
    public var isEnabled: Bool?
    public var isMuted: Bool?
    public var profileName: String?

    public init(
        command: String,
        configuration: RouteConfiguration? = nil,
        output: OutputRoute? = nil,
        outputDeviceUID: String? = nil,
        extraDelayMilliseconds: Double? = nil,
        gain: Float? = nil,
        isEnabled: Bool? = nil,
        isMuted: Bool? = nil,
        profileName: String? = nil
    ) {
        self.command = command
        self.configuration = configuration
        self.output = output
        self.outputDeviceUID = outputDeviceUID
        self.extraDelayMilliseconds = extraDelayMilliseconds
        self.gain = gain
        self.isEnabled = isEnabled
        self.isMuted = isMuted
        self.profileName = profileName
    }
}

public struct ControlResponse: Codable, Equatable, Sendable {
    public var ok: Bool
    public var message: String
    public var status: RouteStatus?

    public init(ok: Bool, message: String, status: RouteStatus? = nil) {
        self.ok = ok
        self.message = message
        self.status = status
    }
}

public enum ControlCommand: String, CaseIterable, Sendable {
    case status
    case start
    case stop
    case update
    case saveProfile = "save-profile"
    case applyProfile = "apply-profile"

    public static func parse(_ request: ControlRequest) -> ControlCommand? {
        ControlCommand(rawValue: request.command)
    }
}

public enum ControlCodec {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        try JSONEncoder().encode(value) + Data([0x0A])
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let line = data.prefix { $0 != 0x0A }
        return try JSONDecoder().decode(T.self, from: line)
    }
}
