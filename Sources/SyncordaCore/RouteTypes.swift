import Foundation

public struct AudioDeviceDescriptor: Codable, Equatable, Identifiable, Sendable {
    public let uid: String
    public let name: String
    public let sampleRate: Double
    public let outputChannels: Int
    public let transport: String
    public let isAlive: Bool

    public var id: String { uid }

    public init(uid: String, name: String, sampleRate: Double, outputChannels: Int, transport: String, isAlive: Bool = true) {
        self.uid = uid
        self.name = name
        self.sampleRate = sampleRate
        self.outputChannels = outputChannels
        self.transport = transport
        self.isAlive = isAlive
    }
}

public struct AudioProcessDescriptor: Codable, Equatable, Identifiable, Sendable {
    public let objectID: UInt32
    public let pid: Int32
    public let name: String
    public let bundleIdentifier: String?
    public let isRunning: Bool

    public var id: UInt32 { objectID }

    public init(objectID: UInt32, pid: Int32, name: String, bundleIdentifier: String?, isRunning: Bool) {
        self.objectID = objectID
        self.pid = pid
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.isRunning = isRunning
    }
}

public enum SourceSelector: Codable, Equatable, Sendable {
    case processID(Int32)
    case bundleIdentifier(String)

    private enum CodingKeys: String, CodingKey { case kind, value }
    private enum Kind: String, Codable { case processID, bundleIdentifier }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(Kind.self, forKey: .kind) {
        case .processID: self = .processID(try values.decode(Int32.self, forKey: .value))
        case .bundleIdentifier: self = .bundleIdentifier(try values.decode(String.self, forKey: .value))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .processID(pid):
            try values.encode(Kind.processID, forKey: .kind)
            try values.encode(pid, forKey: .value)
        case let .bundleIdentifier(identifier):
            try values.encode(Kind.bundleIdentifier, forKey: .kind)
            try values.encode(identifier, forKey: .value)
        }
    }
}

public struct OutputRoute: Codable, Equatable, Identifiable, Sendable {
    public let deviceUID: String
    /// Additional delay applied to this specific device. Positive values delay this device.
    public var extraDelayMilliseconds: Double
    public var gain: Float
    public var isMuted: Bool
    public var isEnabled: Bool

    public var id: String { deviceUID }

    public init(deviceUID: String, extraDelayMilliseconds: Double = 0, gain: Float = 1, isMuted: Bool = false, isEnabled: Bool = true) {
        self.deviceUID = deviceUID
        self.extraDelayMilliseconds = max(0, min(1_000, extraDelayMilliseconds))
        self.gain = max(0, min(4, gain))
        self.isMuted = isMuted
        self.isEnabled = isEnabled
    }
}

public struct RouteConfiguration: Codable, Equatable, Sendable {
    public var source: SourceSelector
    public var outputs: [OutputRoute]

    public init(source: SourceSelector, outputs: [OutputRoute]) {
        self.source = source
        self.outputs = outputs
    }

    public var enabledOutputs: [OutputRoute] { outputs.filter(\.isEnabled) }
}

public struct RouteProfile: Codable, Equatable, Identifiable, Sendable {
    public var name: String
    public var configuration: RouteConfiguration
    public var modifiedAt: Date

    public var id: String { name }

    public init(name: String, configuration: RouteConfiguration, modifiedAt: Date = .now) {
        self.name = name
        self.configuration = configuration
        self.modifiedAt = modifiedAt
    }
}

public enum RouteState: String, Codable, Sendable {
    case stopped
    case starting
    case running
    case failed
}

public struct OutputRuntimeStatus: Codable, Equatable, Identifiable, Sendable {
    public let deviceUID: String
    public var name: String
    public var extraDelayMilliseconds: Double
    public var gain: Float
    public var isMuted: Bool
    public var underruns: UInt64
    public var renderedFrames: UInt64
    public var error: String?

    public var id: String { deviceUID }
}

public struct RouteStatus: Codable, Equatable, Sendable {
    public var state: RouteState
    public var message: String
    public var source: AudioProcessDescriptor?
    public var outputs: [OutputRuntimeStatus]

    public init(state: RouteState, message: String, source: AudioProcessDescriptor? = nil, outputs: [OutputRuntimeStatus] = []) {
        self.state = state
        self.message = message
        self.source = source
        self.outputs = outputs
    }
}

public struct RouteSnapshot: Sendable {
    public let configuration: RouteConfiguration?
    public let revision: UInt64

    public init(configuration: RouteConfiguration?, revision: UInt64) {
        self.configuration = configuration
        self.revision = revision
    }
}
