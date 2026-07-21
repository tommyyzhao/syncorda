import Foundation

public final class ProfileStore: @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    public init(fileURL: URL = ProfileStore.defaultFileURL()) {
        self.fileURL = fileURL
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public static func defaultFileURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Syncorda", isDirectory: true).appendingPathComponent("profiles.json")
    }

    public func all() throws -> [RouteProfile] {
        lock.lock(); defer { lock.unlock() }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return try decoder.decode([RouteProfile].self, from: Data(contentsOf: fileURL))
    }

    public func save(_ profile: RouteProfile) throws {
        lock.lock(); defer { lock.unlock() }
        var profiles: [RouteProfile]
        if FileManager.default.fileExists(atPath: fileURL.path) {
            profiles = try decoder.decode([RouteProfile].self, from: Data(contentsOf: fileURL))
        } else {
            profiles = []
        }
        profiles.removeAll { $0.name.caseInsensitiveCompare(profile.name) == .orderedSame }
        profiles.append(profile)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(profiles).write(to: fileURL, options: .atomic)
    }

    public func named(_ name: String) throws -> RouteProfile? {
        try all().first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
}
