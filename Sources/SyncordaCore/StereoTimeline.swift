import Foundation
import SyncordaAtomics

public struct StereoFrame: Equatable, Sendable {
    public var left: Float
    public var right: Float

    public init(left: Float, right: Float) {
        self.left = left
        self.right = right
    }

    public static let silence = StereoFrame(left: 0, right: 0)
}

/// A fixed, lock-free history of a stereo source timeline. One producer writes source frames;
/// each physical device owns its own `DelayedTimelineReader`.
public final class StereoTimeline: @unchecked Sendable {
    public let capacityFrames: Int
    private let storage: UnsafeMutablePointer<StereoFrame>
    private let nextWriteFrame: OpaquePointer

    public init(capacityFrames: Int) {
        precondition(capacityFrames > 1)
        self.capacityFrames = capacityFrames
        self.storage = .allocate(capacity: capacityFrames)
        self.storage.initialize(repeating: .silence, count: capacityFrames)
        guard let atomic = syncorda_atomic_u64_create(0) else {
            fatalError("Unable to allocate atomic cursor")
        }
        self.nextWriteFrame = atomic
    }

    deinit {
        storage.deinitialize(count: capacityFrames)
        storage.deallocate()
        syncorda_atomic_u64_destroy(nextWriteFrame)
    }

    public var latestFrame: UInt64 {
        syncorda_atomic_u64_load(nextWriteFrame)
    }

    /// Writes whole frames to the timeline. Safe for its single real-time producer.
    public func write(_ frames: UnsafeBufferPointer<StereoFrame>) {
        guard !frames.isEmpty else { return }
        let start = syncorda_atomic_u64_load(nextWriteFrame)
        for offset in frames.indices {
            storage[Int((start + UInt64(offset)) % UInt64(capacityFrames))] = frames[offset]
        }
        syncorda_atomic_u64_store(nextWriteFrame, start + UInt64(frames.count))
    }

    public func write(_ frames: [StereoFrame]) {
        frames.withUnsafeBufferPointer(write)
    }

    /// Returns nil when a frame has not arrived yet or has fallen out of the fixed history.
    public func frame(at absoluteFrame: UInt64) -> StereoFrame? {
        let newest = latestFrame
        guard absoluteFrame < newest, newest - absoluteFrame <= UInt64(capacityFrames) else { return nil }
        return storage[Int(absoluteFrame % UInt64(capacityFrames))]
    }
}

/// A per-device reader. Extra delay is expressed in source frames and never affects another device.
public final class DelayedTimelineReader: @unchecked Sendable {
    public var extraDelayFrames: Int {
        didSet { extraDelayFrames = max(0, extraDelayFrames) }
    }
    public var preRollFrames: Int {
        didSet { preRollFrames = max(0, preRollFrames) }
    }

    private var sourcePosition: Double?
    private var lastAppliedDelay: Int?

    public init(extraDelayFrames: Int = 0, preRollFrames: Int = 0) {
        self.extraDelayFrames = max(0, extraDelayFrames)
        self.preRollFrames = max(0, preRollFrames)
    }

    public func reset() {
        sourcePosition = nil
        lastAppliedDelay = nil
    }

    /// Linear-resamples a source timeline to the target device rate. The small correction term
    /// keeps the intended history distance stable when independent physical clocks drift.
    public func render(
        frameCount: Int,
        sourceRate: Double,
        outputRate: Double,
        timeline: StereoTimeline,
        gain: Float = 1,
        muted: Bool = false
    ) -> [StereoFrame] {
        guard frameCount > 0, sourceRate > 0, outputRate > 0, !muted else {
            return Array(repeating: .silence, count: max(0, frameCount))
        }

        let output = UnsafeMutablePointer<StereoFrame>.allocate(capacity: frameCount)
        defer { output.deallocate() }
        _ = render(
            into: output,
            frameCount: frameCount,
            sourceRate: sourceRate,
            outputRate: outputRate,
            timeline: timeline,
            gain: gain,
            muted: muted
        )
        return Array(UnsafeBufferPointer(start: output, count: frameCount))
    }

    /// Real-time rendering form: `output` is supplied by the caller and no heap allocation occurs.
    /// Returns the count of source frames that were not yet available in the timeline.
    @discardableResult
    public func render(
        into output: UnsafeMutablePointer<StereoFrame>,
        frameCount: Int,
        sourceRate: Double,
        outputRate: Double,
        timeline: StereoTimeline,
        gain: Float = 1,
        muted: Bool = false
    ) -> Int {
        guard frameCount > 0 else { return 0 }
        guard sourceRate > 0, outputRate > 0, !muted else {
            for offset in 0..<frameCount { output[offset] = .silence }
            return 0
        }

        if lastAppliedDelay != extraDelayFrames {
            sourcePosition = nil
            lastAppliedDelay = extraDelayFrames
        }

        let newest = timeline.latestFrame
        let desiredLag = UInt64(extraDelayFrames + preRollFrames)

        // Physical output callbacks can begin before the process tap has filled the desired
        // history. Do not let an early (usually the fastest) renderer consume imaginary future
        // frames: it would otherwise remain ahead of the writer and underrun indefinitely.
        guard newest > desiredLag else {
            for offset in 0..<frameCount { output[offset] = .silence }
            return 0
        }
        let desiredPosition = newest > desiredLag ? Double(newest - desiredLag - 1) : 0

        if sourcePosition == nil {
            sourcePosition = desiredPosition
        }

        var position = sourcePosition ?? desiredPosition
        let error = desiredPosition - position
        let correction = max(-0.005, min(0.005, error * 0.0005))
        let increment = (sourceRate / outputRate) * (1 + correction)
        var underruns = 0

        for offset in 0..<frameCount {
            let lowerFrame = UInt64(max(0, floor(position)))
            let fraction = Float(position - floor(position))
            guard let lower = timeline.frame(at: lowerFrame) else {
                output[offset] = .silence
                underruns += 1
                continue
            }
            let upper = timeline.frame(at: lowerFrame + 1) ?? lower
            let frame = StereoFrame(
                left: (lower.left + ((upper.left - lower.left) * fraction)) * gain,
                right: (lower.right + ((upper.right - lower.right) * fraction)) * gain
            )
            output[offset] = frame
            position += increment
        }

        sourcePosition = position
        return underruns
    }
}
