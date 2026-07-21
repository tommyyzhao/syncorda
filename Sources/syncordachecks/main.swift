import Foundation
import SyncordaCore

enum CheckFailure: Error, CustomStringConvertible {
    case failed(String)
    var description: String {
        switch self { case let .failed(message): message }
    }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw CheckFailure.failed(message) }
}

func chromeConfiguration() -> RouteConfiguration {
    RouteConfiguration(
        source: .bundleIdentifier("com.google.Chrome"),
        outputs: [OutputRoute(deviceUID: "built-in"), OutputRoute(deviceUID: "kitchen", extraDelayMilliseconds: 250)]
    )
}

func testTimelineExpiry() throws {
    let timeline = StereoTimeline(capacityFrames: 4)
    timeline.write((0..<6).map { StereoFrame(left: Float($0), right: Float(-$0)) })
    try expect(timeline.frame(at: 0) == nil, "Old frame 0 should expire")
    try expect(timeline.frame(at: 1) == nil, "Old frame 1 should expire")
    try expect(timeline.frame(at: 2) == StereoFrame(left: 2, right: -2), "Recent frame should remain readable")
    try expect(timeline.frame(at: 5) == StereoFrame(left: 5, right: -5), "Newest completed frame should remain readable")
}

func testIndependentDelays() throws {
    let timeline = StereoTimeline(capacityFrames: 32)
    timeline.write((0..<20).map { StereoFrame(left: Float($0), right: Float($0)) })
    let immediate = DelayedTimelineReader(extraDelayFrames: 0)
    let delayed = DelayedTimelineReader(extraDelayFrames: 5)
    try expect(immediate.render(frameCount: 1, sourceRate: 1, outputRate: 1, timeline: timeline)[0].left == 19, "Immediate reader should start at latest completed frame")
    try expect(delayed.render(frameCount: 1, sourceRate: 1, outputRate: 1, timeline: timeline)[0].left == 14, "Delayed reader should only affect its own position")
}

func testInterpolation() throws {
    let timeline = StereoTimeline(capacityFrames: 32)
    timeline.write((0..<8).map { StereoFrame(left: Float($0 * 10), right: 0) })
    let reader = DelayedTimelineReader(extraDelayFrames: 4)
    let frames = reader.render(frameCount: 4, sourceRate: 2, outputRate: 4, timeline: timeline)
    try expect(frames.map(\.left) == [30, 35, 40, 45], "Reader must linearly resample between source frames")
}

func testReaderWaitsForPreRoll() throws {
    let timeline = StereoTimeline(capacityFrames: 32)
    let reader = DelayedTimelineReader(extraDelayFrames: 0, preRollFrames: 4)
    let startupFrames = reader.render(frameCount: 8, sourceRate: 1, outputRate: 1, timeline: timeline)
    try expect(startupFrames == Array(repeating: .silence, count: 8), "A reader must wait silently for its pre-roll history")

    timeline.write((0..<10).map { StereoFrame(left: Float($0), right: Float($0)) })
    let firstAvailable = reader.render(frameCount: 1, sourceRate: 1, outputRate: 1, timeline: timeline)
    try expect(firstAvailable[0] == StereoFrame(left: 5, right: 5), "A delayed reader must begin at its intended history position after pre-roll")
}

func testMuteDoesNotAdvance() throws {
    let timeline = StereoTimeline(capacityFrames: 16)
    timeline.write((0..<10).map { StereoFrame(left: Float($0), right: Float($0)) })
    let reader = DelayedTimelineReader()
    try expect(reader.render(frameCount: 2, sourceRate: 1, outputRate: 1, timeline: timeline, muted: true) == [.silence, .silence], "Mute should emit silence")
    try expect(reader.render(frameCount: 1, sourceRate: 1, outputRate: 1, timeline: timeline)[0] == StereoFrame(left: 9, right: 9), "Muted frames must not consume timeline frames")
}

func testPersistenceAndProtocol() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let store = ProfileStore(fileURL: directory.appendingPathComponent("profiles.json"))
    let profile = RouteProfile(name: "chrome-kitchen", configuration: chromeConfiguration(), modifiedAt: Date(timeIntervalSince1970: 100))
    try store.save(profile)
    let restoredProfile = try store.named("CHROME-KITCHEN")
    try expect(restoredProfile == profile, "Profiles should persist case-insensitively")
    try expect(OutputRoute(deviceUID: "x", extraDelayMilliseconds: -10).extraDelayMilliseconds == 0, "Delay should clamp at zero")
    try expect(OutputRoute(deviceUID: "x", extraDelayMilliseconds: 2_000).extraDelayMilliseconds == 1_000, "Delay should clamp at one second")
    let request = ControlRequest(command: "start", configuration: chromeConfiguration())
    let encoded = try ControlCodec.encode(request)
    try expect(encoded.last == 0x0A, "Control messages should be newline-delimited")
    let restoredRequest = try ControlCodec.decode(ControlRequest.self, from: encoded)
    try expect(restoredRequest == request, "Control messages should round-trip")
    try expect(ControlCommand.parse(request) == .start, "Control command should parse")
}

func testLocalControlRoundTrip() throws {
    let path = "/tmp/syncorda-check-\(UUID().uuidString).sock"
    let server = LocalControlServer(path: path) { request in
        ControlResponse(ok: request.command == "status", message: "received \(request.command)")
    }
    try server.start()
    defer { server.stop() }
    var fileInfo = stat()
    try expect(stat(path, &fileInfo) == 0, "Local control socket should exist")
    try expect((fileInfo.st_mode & 0o777) == 0o600, "Local control socket should be owner-only")
    let response = try LocalControlClient.send(ControlRequest(command: "status"), path: path)
    try expect(response.ok, "Local control server should accept requests")
    try expect(response.message == "received status", "Local control response should round-trip")
    for _ in 0..<10 {
        let repeated = try LocalControlClient.send(ControlRequest(command: "status"), path: path)
        try expect(repeated.ok, "Local control server should survive repeated requests")
    }
}

@main
struct SyncordaChecks {
    static func main() {
        let checks: [(String, () throws -> Void)] = [
            ("timeline expiry", testTimelineExpiry),
            ("independent delays", testIndependentDelays),
            ("resampling", testInterpolation),
            ("reader pre-roll", testReaderWaitsForPreRoll),
            ("mute behavior", testMuteDoesNotAdvance),
            ("profiles and protocol", testPersistenceAndProtocol),
            ("local control socket", testLocalControlRoundTrip)
        ]
        var failures = 0
        for (name, check) in checks {
            do {
                try check()
                print("PASS  \(name)")
            } catch {
                failures += 1
                print("FAIL  \(name): \(error)")
            }
        }
        if failures > 0 {
            print("\(failures) check(s) failed")
            exit(1)
        }
        print("All \(checks.count) checks passed")
    }
}
