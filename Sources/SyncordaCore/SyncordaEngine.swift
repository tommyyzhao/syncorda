import AudioToolbox
import CoreAudio
import Darwin
import Foundation
import SyncordaAtomics

private final class AtomicUInt64: @unchecked Sendable {
    private let storage: OpaquePointer

    init(_ initialValue: UInt64 = 0) {
        guard let value = syncorda_atomic_u64_create(initialValue) else { fatalError("Unable to allocate an atomic value") }
        self.storage = value
    }

    deinit { syncorda_atomic_u64_destroy(storage) }

    var value: UInt64 { syncorda_atomic_u64_load(storage) }
    func store(_ value: UInt64) { syncorda_atomic_u64_store(storage, value) }
    func add(_ value: UInt64) { _ = syncorda_atomic_u64_add(storage, value) }
}

private extension AudioDeviceID {
    func syncordaOutputFormat() throws -> AudioStreamBasicDescription {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormat,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var byteCount = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var result = AudioStreamBasicDescription()
        let status = AudioObjectGetPropertyData(self, &address, 0, nil, &byteCount, &result)
        guard status == noErr else { throw SyncordaAudioError.coreAudio(operation: "Read output stream format", status: status) }
        return result
    }

    func syncordaBufferFrameSize() -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSize,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var byteCount = UInt32(MemoryLayout<UInt32>.size)
        var result: UInt32 = 0
        let status = AudioObjectGetPropertyData(self, &address, 0, nil, &byteCount, &result)
        return status == noErr ? Int(result) : 512
    }
}

private final class PhysicalOutputRenderer: @unchecked Sendable {
    let routeUID: String
    let descriptor: AudioDeviceDescriptor
    private let deviceID: AudioDeviceID
    private let sourceRate: Double
    private let timeline: StereoTimeline
    private let outputFormat: AudioStreamBasicDescription
    private let outputRate: Double
    private let reader = DelayedTimelineReader()
    private let scratch: UnsafeMutablePointer<StereoFrame>
    private let scratchCapacity: Int
    private let callbackQueue: DispatchQueue
    private let delayFrames = AtomicUInt64()
    private let gainBits = AtomicUInt64(UInt64(Float(1).bitPattern))
    private let muted = AtomicUInt64()
    private let underrunFrames = AtomicUInt64()
    private let renderedFrames = AtomicUInt64()
    private var ioProcID: AudioDeviceIOProcID?

    init(route: OutputRoute, sourceRate: Double, timeline: StereoTimeline) throws {
        self.routeUID = route.deviceUID
        self.descriptor = try AudioDeviceCatalog.descriptor(forUID: route.deviceUID)
        self.deviceID = try AudioDeviceCatalog.deviceID(forUID: route.deviceUID)
        self.sourceRate = sourceRate
        self.timeline = timeline
        self.outputFormat = try deviceID.syncordaOutputFormat()
        self.outputRate = outputFormat.mSampleRate > 0 ? outputFormat.mSampleRate : descriptor.sampleRate
        guard outputFormat.mFormatID == kAudioFormatLinearPCM,
              (outputFormat.mFormatFlags & kAudioFormatFlagIsFloat) != 0,
              outputFormat.mBitsPerChannel == 32 else {
            throw SyncordaAudioError.unsupportedFormat("\(descriptor.name) is not Float32 linear PCM")
        }
        self.scratchCapacity = max(4_096, deviceID.syncordaBufferFrameSize() * 4)
        self.scratch = .allocate(capacity: scratchCapacity)
        self.scratch.initialize(repeating: .silence, count: scratchCapacity)
        self.callbackQueue = DispatchQueue(label: "io.github.tommyyzhao.syncorda.output.\(route.deviceUID)", qos: .userInteractive)
        self.reader.preRollFrames = max(256, Int((sourceRate * 0.03).rounded()))
        update(route)
    }

    deinit {
        stop()
        scratch.deinitialize(count: scratchCapacity)
        scratch.deallocate()
    }

    func start() throws {
        guard ioProcID == nil else { return }
        var procID: AudioDeviceIOProcID?
        let createStatus = AudioDeviceCreateIOProcIDWithBlock(&procID, deviceID, callbackQueue) { [weak self] _, _, _, outputData, _ in
            guard let self else { return }
            self.render(outputData)
        }
        guard createStatus == noErr else { throw SyncordaAudioError.coreAudio(operation: "Create output callback for \(descriptor.name)", status: createStatus) }
        ioProcID = procID
        let startStatus = AudioDeviceStart(deviceID, procID)
        guard startStatus == noErr else {
            if let procID { AudioDeviceDestroyIOProcID(deviceID, procID) }
            ioProcID = nil
            throw SyncordaAudioError.coreAudio(operation: "Start output device \(descriptor.name)", status: startStatus)
        }
    }

    func stop() {
        guard let ioProcID else { return }
        AudioDeviceStop(deviceID, ioProcID)
        AudioDeviceDestroyIOProcID(deviceID, ioProcID)
        self.ioProcID = nil
    }

    func update(_ route: OutputRoute) {
        let milliseconds = max(0, min(1_000, route.extraDelayMilliseconds))
        delayFrames.store(UInt64((milliseconds / 1_000 * sourceRate).rounded()))
        gainBits.store(UInt64(route.gain.bitPattern))
        muted.store((route.isMuted || !route.isEnabled) ? 1 : 0)
    }

    func status() -> OutputRuntimeStatus {
        OutputRuntimeStatus(
            deviceUID: routeUID,
            name: descriptor.name,
            extraDelayMilliseconds: Double(delayFrames.value) / sourceRate * 1_000,
            gain: Float(bitPattern: UInt32(truncatingIfNeeded: gainBits.value)),
            isMuted: muted.value != 0,
            underruns: underrunFrames.value,
            renderedFrames: renderedFrames.value,
            error: nil
        )
    }

    private func render(_ outputData: UnsafeMutablePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(outputData)
        guard let first = buffers.first, first.mData != nil else { return }
        let frameCount = frames(in: first, bufferCount: buffers.count)
        guard frameCount > 0 else { return }
        guard frameCount <= scratchCapacity else {
            zero(buffers)
            underrunFrames.add(UInt64(frameCount))
            return
        }

        let gain = Float(bitPattern: UInt32(truncatingIfNeeded: gainBits.value))
        reader.extraDelayFrames = Int(delayFrames.value)
        let missing = reader.render(
            into: scratch,
            frameCount: frameCount,
            sourceRate: sourceRate,
            outputRate: outputRate,
            timeline: timeline,
            gain: gain,
            muted: muted.value != 0
        )
        if missing > 0 { underrunFrames.add(UInt64(missing)) }
        write(scratch, frameCount: frameCount, to: buffers)
        renderedFrames.add(UInt64(frameCount))
    }

    private func frames(in first: AudioBuffer, bufferCount: Int) -> Int {
        let bytesPerFrame: Int
        if bufferCount > 1 && first.mNumberChannels == 1 {
            bytesPerFrame = MemoryLayout<Float>.size
        } else {
            bytesPerFrame = max(MemoryLayout<Float>.size * max(1, Int(first.mNumberChannels)), Int(outputFormat.mBytesPerFrame))
        }
        return Int(first.mDataByteSize) / bytesPerFrame
    }

    private func write(_ frames: UnsafeMutablePointer<StereoFrame>, frameCount: Int, to buffers: UnsafeMutableAudioBufferListPointer) {
        if buffers.count >= 2, buffers[0].mNumberChannels == 1, buffers[1].mNumberChannels == 1,
           let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
           let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) {
            for index in 0..<frameCount {
                left[index] = frames[index].left
                right[index] = frames[index].right
            }
            if buffers.count > 2 {
                for index in 2..<buffers.count { if let data = buffers[index].mData { memset(data, 0, Int(buffers[index].mDataByteSize)) } }
            }
            return
        }

        guard let data = buffers[0].mData else { return }
        let samples = data.assumingMemoryBound(to: Float.self)
        let channels = max(1, Int(buffers[0].mNumberChannels))
        for index in 0..<frameCount {
            let base = index * channels
            if channels == 1 {
                samples[base] = (frames[index].left + frames[index].right) * 0.5
            } else {
                samples[base] = frames[index].left
                samples[base + 1] = frames[index].right
                if channels > 2 {
                    for channel in 2..<channels { samples[base + channel] = 0 }
                }
            }
        }
        if buffers.count > 1 {
            for index in 1..<buffers.count { if let extra = buffers[index].mData { memset(extra, 0, Int(buffers[index].mDataByteSize)) } }
        }
    }

    private func zero(_ buffers: UnsafeMutableAudioBufferListPointer) {
        for buffer in buffers { if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) } }
    }
}

@available(macOS 14.2, *)
private final class ProcessTapSession: @unchecked Sendable {
    let source: AudioProcessDescriptor
    private let routes: [OutputRoute]
    private let clockDeviceUID: String
    private var tapDescription: CATapDescription?
    private var tapID: AudioObjectID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDeviceID: AudioDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var sourceIOProcID: AudioDeviceIOProcID?
    private var sourceRate: Double = 48_000
    private var timeline: StereoTimeline?
    private var sourceScratch: UnsafeMutablePointer<StereoFrame>?
    private var sourceScratchCapacity = 0
    private var renderers: [PhysicalOutputRenderer] = []
    private let sourceQueue = DispatchQueue(label: "io.github.tommyyzhao.syncorda.source", qos: .userInteractive)

    init(source: AudioProcessDescriptor, routes: [OutputRoute]) throws {
        guard let clock = routes.first?.deviceUID else { throw SyncordaAudioError.noEnabledOutputs }
        self.source = source
        self.routes = routes
        self.clockDeviceUID = clock
    }

    deinit { stop() }

    func start() throws {
        let description = CATapDescription(stereoMixdownOfProcesses: [AudioObjectID(source.objectID)])
        description.uuid = UUID()
        description.muteBehavior = .mutedWhenTapped
        tapDescription = description

        var createdTap = AudioObjectID(kAudioObjectUnknown)
        let tapStatus = AudioHardwareCreateProcessTap(description, &createdTap)
        guard tapStatus == noErr else { throw SyncordaAudioError.coreAudio(operation: "Create process tap", status: tapStatus) }
        tapID = createdTap

        let clockID = try AudioDeviceCatalog.deviceID(forUID: clockDeviceUID)

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Syncorda Tap \(source.pid)",
            kAudioAggregateDeviceUIDKey: "io.github.tommyyzhao.syncorda.tap.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: clockDeviceUID,
            kAudioAggregateDeviceClockDeviceKey: clockDeviceUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: clockDeviceUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true
            ]]
        ]
        var aggregate = AudioObjectID(kAudioObjectUnknown)
        let aggregateStatus = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregate)
        guard aggregateStatus == noErr else { throw SyncordaAudioError.coreAudio(operation: "Create private tap aggregate", status: aggregateStatus) }
        aggregateDeviceID = aggregate

        // The IOProc receives the aggregate's converted stream, not necessarily the tap's
        // nominal stream. Anchor the shared timeline to the aggregate clock so a 44.1 kHz
        // source feeding a 48 kHz clock device cannot make a reader outrun the writer.
        sourceRate = try aggregateNominalSampleRate(aggregateDeviceID)
        if sourceRate <= 0 { sourceRate = (try AudioDeviceCatalog.descriptor(forUID: clockDeviceUID)).sampleRate }
        let historyFrames = max(96_000, Int((sourceRate * 2.5).rounded()))
        timeline = StereoTimeline(capacityFrames: historyFrames)
        sourceScratchCapacity = max(4_096, clockID.syncordaBufferFrameSize() * 4)
        let scratch = UnsafeMutablePointer<StereoFrame>.allocate(capacity: sourceScratchCapacity)
        scratch.initialize(repeating: .silence, count: sourceScratchCapacity)
        sourceScratch = scratch

        var procID: AudioDeviceIOProcID?
        let procStatus = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateDeviceID, sourceQueue) { [weak self] _, inputData, _, outputData, _ in
            guard let self else { return }
            self.capture(inputData)
            self.zero(outputData)
        }
        guard procStatus == noErr else { throw SyncordaAudioError.coreAudio(operation: "Create source callback", status: procStatus) }
        sourceIOProcID = procID
        let sourceStartStatus = AudioDeviceStart(aggregateDeviceID, procID)
        guard sourceStartStatus == noErr else { throw SyncordaAudioError.coreAudio(operation: "Start source tap", status: sourceStartStatus) }

        guard let timeline else { throw SyncordaAudioError.coreAudio(operation: "Initialize source timeline", status: -1) }
        do {
            renderers = try routes.map { try PhysicalOutputRenderer(route: $0, sourceRate: sourceRate, timeline: timeline) }
            try renderers.forEach { try $0.start() }
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        renderers.forEach { $0.stop() }
        renderers = []
        if aggregateDeviceID != AudioObjectID(kAudioObjectUnknown) {
            AudioDeviceStop(aggregateDeviceID, sourceIOProcID)
            if let sourceIOProcID { AudioDeviceDestroyIOProcID(aggregateDeviceID, sourceIOProcID) }
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
        }
        sourceIOProcID = nil
        aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        if tapID != AudioObjectID(kAudioObjectUnknown) { AudioHardwareDestroyProcessTap(tapID) }
        tapID = AudioObjectID(kAudioObjectUnknown)
        tapDescription = nil
        if let sourceScratch {
            sourceScratch.deinitialize(count: sourceScratchCapacity)
            sourceScratch.deallocate()
        }
        sourceScratch = nil
        sourceScratchCapacity = 0
        timeline = nil
    }

    func update(_ route: OutputRoute) {
        renderers.first { $0.routeUID == route.deviceUID }?.update(route)
    }

    func runtimeOutputs() -> [OutputRuntimeStatus] { renderers.map { $0.status() } }

    private func readTapFormat(_ tap: AudioObjectID) throws -> AudioStreamBasicDescription {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var result = AudioStreamBasicDescription()
        let status = AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &result)
        guard status == noErr else { throw SyncordaAudioError.coreAudio(operation: "Read process tap format", status: status) }
        return result
    }

    private func aggregateNominalSampleRate(_ device: AudioDeviceID) throws -> Double {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<Double>.size)
        var result: Double = 0
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &result)
        guard status == noErr else { throw SyncordaAudioError.coreAudio(operation: "Read aggregate sample rate", status: status) }
        return result
    }

    private func capture(_ inputData: UnsafePointer<AudioBufferList>) {
        guard let timeline, let sourceScratch else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
        guard let first = buffers.first, first.mData != nil else { return }
        let frameCount: Int
        if buffers.count >= 2, buffers[0].mNumberChannels == 1, buffers[1].mNumberChannels == 1 {
            frameCount = Int(min(buffers[0].mDataByteSize, buffers[1].mDataByteSize)) / MemoryLayout<Float>.size
            guard frameCount <= sourceScratchCapacity,
                  let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return }
            for index in 0..<frameCount { sourceScratch[index] = StereoFrame(left: left[index], right: right[index]) }
        } else {
            let channels = max(1, Int(first.mNumberChannels))
            frameCount = Int(first.mDataByteSize) / (MemoryLayout<Float>.size * channels)
            guard frameCount <= sourceScratchCapacity, let data = first.mData?.assumingMemoryBound(to: Float.self) else { return }
            for index in 0..<frameCount {
                let offset = index * channels
                let left = data[offset]
                let right = channels > 1 ? data[offset + 1] : left
                sourceScratch[index] = StereoFrame(left: left, right: right)
            }
        }
        timeline.write(UnsafeBufferPointer(start: sourceScratch, count: frameCount))
    }

    private func zero(_ outputData: UnsafeMutablePointer<AudioBufferList>) {
        for buffer in UnsafeMutableAudioBufferListPointer(outputData) {
            if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
        }
    }
}

@available(macOS 14.2, *)
public final class SyncordaEngine: @unchecked Sendable {
    private let controlLock = NSLock()
    private var session: ProcessTapSession?
    private var currentStatus = RouteStatus(state: .stopped, message: "Ready")

    public init() {}

    public func start(_ configuration: RouteConfiguration) throws {
        let enabledOutputs = configuration.enabledOutputs
        guard !enabledOutputs.isEmpty else { throw SyncordaAudioError.noEnabledOutputs }
        controlLock.lock()
        defer { controlLock.unlock() }
        stopLocked()
        currentStatus = RouteStatus(state: .starting, message: "Starting route…")
        do {
            let source = try AudioProcessCatalog.resolve(configuration.source)
            let newSession = try ProcessTapSession(source: source, routes: enabledOutputs)
            try newSession.start()
            session = newSession
            currentStatus = RouteStatus(state: .running, message: "Routing \(source.name)", source: source, outputs: newSession.runtimeOutputs())
        } catch {
            currentStatus = RouteStatus(state: .failed, message: error.localizedDescription)
            throw error
        }
    }

    public func stop() {
        controlLock.lock()
        defer { controlLock.unlock() }
        stopLocked()
        currentStatus = RouteStatus(state: .stopped, message: "Stopped")
    }

    public func update(_ route: OutputRoute) {
        controlLock.lock()
        defer { controlLock.unlock() }
        session?.update(route)
        if let session, currentStatus.state == .running {
            currentStatus.outputs = session.runtimeOutputs()
        }
    }

    public func status() -> RouteStatus {
        controlLock.lock()
        defer { controlLock.unlock() }
        if let session, currentStatus.state == .running { currentStatus.outputs = session.runtimeOutputs() }
        return currentStatus
    }

    private func stopLocked() {
        session?.stop()
        session = nil
    }
}
