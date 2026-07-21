import AudioToolbox
import AppKit
import CoreAudio
import Foundation

public enum SyncordaAudioError: LocalizedError, Equatable {
    case coreAudio(operation: String, status: OSStatus)
    case deviceNotFound(String)
    case processNotFound(String)
    case unsupportedFormat(String)
    case noEnabledOutputs

    public var errorDescription: String? {
        switch self {
        case let .coreAudio(operation, status): return "\(operation) failed (Core Audio status \(status))."
        case let .deviceNotFound(uid): return "Output device '\(uid)' is no longer available."
        case let .processNotFound(source): return "No running audio process matched '\(source)'."
        case let .unsupportedFormat(description): return "Unsupported device format: \(description)."
        case .noEnabledOutputs: return "Choose at least one output device."
        }
    }
}

private extension AudioObjectID {
    static let syncordaSystem = AudioObjectID(kAudioObjectSystemObject)
    static let syncordaUnknown = AudioObjectID(kAudioObjectUnknown)

    func syncordaRead<T>(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
        defaultValue: T
    ) throws -> T {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        var byteCount = UInt32(MemoryLayout<T>.size)
        var value = defaultValue
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(self, &address, 0, nil, &byteCount, pointer)
        }
        guard status == noErr else {
            throw SyncordaAudioError.coreAudio(operation: "Read audio property", status: status)
        }
        return value
    }

    func syncordaReadString(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) throws -> String {
        let value: CFString = try syncordaRead(selector, scope: scope, element: element, defaultValue: "" as CFString)
        return value as String
    }

    func syncordaReadBoolean(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> Bool {
        (try? syncordaRead(selector, scope: scope, element: element, defaultValue: UInt32(0))) != 0
    }
}

public enum AudioDeviceCatalog {
    public static func outputs() throws -> [AudioDeviceDescriptor] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var byteCount: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(AudioObjectID.syncordaSystem, &address, 0, nil, &byteCount)
        guard sizeStatus == noErr else {
            throw SyncordaAudioError.coreAudio(operation: "List audio devices", status: sizeStatus)
        }

        var deviceIDs = [AudioDeviceID](repeating: AudioObjectID.syncordaUnknown, count: Int(byteCount) / MemoryLayout<AudioDeviceID>.size)
        let listStatus = AudioObjectGetPropertyData(AudioObjectID.syncordaSystem, &address, 0, nil, &byteCount, &deviceIDs)
        guard listStatus == noErr else {
            throw SyncordaAudioError.coreAudio(operation: "Read audio devices", status: listStatus)
        }

        return deviceIDs.compactMap { deviceID in
            guard let channels = outputChannelCount(for: deviceID), channels > 0,
                  let uid = try? deviceID.syncordaReadString(kAudioDevicePropertyDeviceUID),
                  let name = try? deviceID.syncordaReadString(kAudioObjectPropertyName) else { return nil }
            let sampleRate = (try? deviceID.syncordaRead(kAudioDevicePropertyNominalSampleRate, defaultValue: Double(0))) ?? 0
            let transportCode = (try? deviceID.syncordaRead(kAudioDevicePropertyTransportType, defaultValue: UInt32(0))) ?? 0
            let alive = deviceID.syncordaReadBoolean(kAudioDevicePropertyDeviceIsAlive)
            return AudioDeviceDescriptor(
                uid: uid,
                name: name,
                sampleRate: sampleRate,
                outputChannels: channels,
                transport: transportName(transportCode),
                isAlive: alive
            )
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public static func deviceID(forUID uid: String) throws -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var byteCount: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(AudioObjectID.syncordaSystem, &address, 0, nil, &byteCount)
        guard sizeStatus == noErr else { throw SyncordaAudioError.coreAudio(operation: "List audio devices", status: sizeStatus) }
        var deviceIDs = [AudioDeviceID](repeating: AudioObjectID.syncordaUnknown, count: Int(byteCount) / MemoryLayout<AudioDeviceID>.size)
        let listStatus = AudioObjectGetPropertyData(AudioObjectID.syncordaSystem, &address, 0, nil, &byteCount, &deviceIDs)
        guard listStatus == noErr else { throw SyncordaAudioError.coreAudio(operation: "Read audio devices", status: listStatus) }
        if let id = deviceIDs.first(where: { (try? $0.syncordaReadString(kAudioDevicePropertyDeviceUID)) == uid }) {
            return id
        }
        throw SyncordaAudioError.deviceNotFound(uid)
    }

    public static func descriptor(forUID uid: String) throws -> AudioDeviceDescriptor {
        guard let result = try outputs().first(where: { $0.uid == uid }) else { throw SyncordaAudioError.deviceNotFound(uid) }
        return result
    }

    private static func outputChannelCount(for deviceID: AudioDeviceID) -> Int? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var byteCount: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &byteCount)
        guard sizeStatus == noErr, byteCount >= MemoryLayout<AudioBufferList>.size else { return nil }
        let memory = UnsafeMutableRawPointer.allocate(byteCount: Int(byteCount), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { memory.deallocate() }
        let list = memory.assumingMemoryBound(to: AudioBufferList.self)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &byteCount, list)
        guard status == noErr else { return nil }
        return UnsafeMutableAudioBufferListPointer(list).reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func transportName(_ code: UInt32) -> String {
        switch code {
        case kAudioDeviceTransportTypeBuiltIn: return "Built-in"
        case kAudioDeviceTransportTypeBluetooth: return "Bluetooth"
        case kAudioDeviceTransportTypeBluetoothLE: return "Bluetooth LE"
        case kAudioDeviceTransportTypeUSB: return "USB"
        case kAudioDeviceTransportTypeAirPlay: return "AirPlay"
        case kAudioDeviceTransportTypeVirtual: return "Virtual"
        default: return String(format: "0x%08X", code)
        }
    }
}

public enum AudioProcessCatalog {
    public static func processes() throws -> [AudioProcessDescriptor] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var byteCount: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(AudioObjectID.syncordaSystem, &address, 0, nil, &byteCount)
        guard sizeStatus == noErr else { throw SyncordaAudioError.coreAudio(operation: "List audio processes", status: sizeStatus) }
        var objectIDs = [AudioObjectID](repeating: AudioObjectID.syncordaUnknown, count: Int(byteCount) / MemoryLayout<AudioObjectID>.size)
        let listStatus = AudioObjectGetPropertyData(AudioObjectID.syncordaSystem, &address, 0, nil, &byteCount, &objectIDs)
        guard listStatus == noErr else { throw SyncordaAudioError.coreAudio(operation: "Read audio processes", status: listStatus) }
        return objectIDs.compactMap(descriptor(forObjectID:)).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public static func resolve(_ selector: SourceSelector) throws -> AudioProcessDescriptor {
        switch selector {
        case let .processID(pid):
            guard let result = try processes().first(where: { $0.pid == pid }) else { throw SyncordaAudioError.processNotFound("pid \(pid)") }
            return result
        case let .bundleIdentifier(identifier):
            let candidates = try processes().filter {
                guard let bundleID = $0.bundleIdentifier else { return false }
                return bundleID.caseInsensitiveCompare(identifier) == .orderedSame
                    || bundleID.lowercased().hasPrefix(identifier.lowercased() + ".")
            }
            guard let result = candidates.first(where: \.isRunning)
                ?? candidates.first(where: { $0.bundleIdentifier?.caseInsensitiveCompare(identifier) == .orderedSame })
                ?? candidates.first else { throw SyncordaAudioError.processNotFound(identifier) }
            return result
        }
    }

    private static func descriptor(forObjectID objectID: AudioObjectID) -> AudioProcessDescriptor? {
        guard let pid: pid_t = try? objectID.syncordaRead(kAudioProcessPropertyPID, defaultValue: pid_t(0)), pid > 0 else { return nil }
        let bundleID = try? objectID.syncordaReadString(kAudioProcessPropertyBundleID)
        let running = objectID.syncordaReadBoolean(kAudioProcessPropertyIsRunning)
        let name = NSRunningApplication(processIdentifier: pid)?.localizedName
            ?? bundleID?.split(separator: ".").last.map(String.init)
            ?? "PID \(pid)"
        return AudioProcessDescriptor(objectID: objectID, pid: pid, name: name, bundleIdentifier: bundleID?.isEmpty == true ? nil : bundleID, isRunning: running)
    }
}
