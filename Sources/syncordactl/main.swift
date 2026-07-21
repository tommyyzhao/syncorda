import Foundation
import SyncordaCore

enum CLIError: LocalizedError {
    case usage(String)
    case service(String)

    var errorDescription: String? {
        switch self {
        case let .usage(message), let .service(message): return message
        }
    }
}

@main
struct SyncordaControl {
    static func main() {
        do {
            try run(Array(CommandLine.arguments.dropFirst()))
        } catch {
            writeError("syncordactl: \(error.localizedDescription)")
            exit(1)
        }
    }

    private static func run(_ arguments: [String]) throws {
        guard let command = arguments.first else { printHelp(); return }
        let rest = Array(arguments.dropFirst())
        switch command {
        case "help", "--help", "-h": printHelp()
        case "sources":
            guard rest.first == "list" else { throw CLIError.usage("Usage: syncordactl sources list [--json]") }
            try printProcesses(json: rest.contains("--json"))
        case "outputs":
            guard rest.first == "list" else { throw CLIError.usage("Usage: syncordactl outputs list [--json]") }
            try printOutputs(json: rest.contains("--json"))
        case "status":
            try printResponse(sendToService(ControlRequest(command: "status")), json: rest.contains("--json"))
        case "stop":
            try printResponse(sendToService(ControlRequest(command: "stop")), json: rest.contains("--json"))
        case "start":
            let configuration = try parseConfiguration(rest)
            try printResponse(sendToService(ControlRequest(command: "start", configuration: configuration)), json: rest.contains("--json"))
        case "set-delay":
            let output = try requiredOption("--output", in: rest)
            let milliseconds = try Double(requiredOption("--milliseconds", in: rest)) ?? { throw CLIError.usage("--milliseconds must be numeric") }()
            try printResponse(sendToService(ControlRequest(command: "update", outputDeviceUID: output, extraDelayMilliseconds: milliseconds)), json: rest.contains("--json"))
        case "set-volume":
            let output = try requiredOption("--output", in: rest)
            let percent = try Double(requiredOption("--percent", in: rest)) ?? { throw CLIError.usage("--percent must be numeric") }()
            guard (0...100).contains(percent) else { throw CLIError.usage("--percent must be between 0 and 100.") }
            try printResponse(sendToService(ControlRequest(command: "update", outputDeviceUID: output, gain: Float(percent / 100))), json: rest.contains("--json"))
        case "profile":
            try runProfile(rest)
        default:
            throw CLIError.usage("Unknown command '\(command)'. Run syncordactl help.")
        }
    }

    private static func runProfile(_ arguments: [String]) throws {
        guard let action = arguments.first else { throw CLIError.usage("Usage: syncordactl profile save|apply NAME …") }
        let rest = Array(arguments.dropFirst())
        switch action {
        case "save":
            guard let name = rest.first else { throw CLIError.usage("Usage: syncordactl profile save NAME --source BUNDLE --output UID[=DELAY]") }
            let configuration = try parseConfiguration(Array(rest.dropFirst()))
            try printResponse(sendToService(ControlRequest(command: "save-profile", configuration: configuration, profileName: name)), json: arguments.contains("--json"))
        case "apply":
            guard let name = rest.first else { throw CLIError.usage("Usage: syncordactl profile apply NAME") }
            try printResponse(sendToService(ControlRequest(command: "apply-profile", profileName: name)), json: arguments.contains("--json"))
        default:
            throw CLIError.usage("Usage: syncordactl profile save|apply NAME …")
        }
    }

    private static func parseConfiguration(_ arguments: [String]) throws -> RouteConfiguration {
        let sourceValue = try requiredOption("--source", in: arguments)
        let source: SourceSelector
        if let pid = Int32(sourceValue), String(pid) == sourceValue { source = .processID(pid) }
        else { source = .bundleIdentifier(sourceValue) }
        let outputValues = repeatedOptions("--output", in: arguments)
        guard !outputValues.isEmpty else { throw CLIError.usage("At least one --output DEVICE_UID is required.") }
        let outputs = try outputValues.map(parseOutput)
        return RouteConfiguration(source: source, outputs: outputs)
    }

    private static func parseOutput(_ raw: String) throws -> OutputRoute {
        guard let separator = raw.lastIndex(of: "="), let delay = Double(raw[raw.index(after: separator)...]) else {
            return OutputRoute(deviceUID: raw)
        }
        let uid = String(raw[..<separator])
        guard !uid.isEmpty else { throw CLIError.usage("Output UID cannot be empty.") }
        return OutputRoute(deviceUID: uid, extraDelayMilliseconds: delay)
    }

    private static func requiredOption(_ name: String, in arguments: [String]) throws -> String {
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else {
            throw CLIError.usage("Missing required option \(name).")
        }
        return arguments[index + 1]
    }

    private static func repeatedOptions(_ name: String, in arguments: [String]) -> [String] {
        arguments.enumerated().compactMap { index, argument in
            argument == name && arguments.indices.contains(index + 1) ? arguments[index + 1] : nil
        }
    }

    private static func sendToService(_ request: ControlRequest) throws -> ControlResponse {
        do { return try LocalControlClient.send(request) }
        catch {
            try launchServiceIfPossible()
            for _ in 0..<40 {
                if let response = try? LocalControlClient.send(request) { return response }
                usleep(100_000)
            }
            throw CLIError.service("Syncorda service is not reachable. Launch SyncordaApp once, or set SYNCORDA_APP_PATH to Syncorda.app.")
        }
    }

    private static func launchServiceIfPossible() throws {
        let process = Process()
        if let appPath = ProcessInfo.processInfo.environment["SYNCORDA_APP_PATH"] {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-gj", appPath, "--args", "--headless"]
        } else {
            let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
            let sibling = executable.deletingLastPathComponent().appendingPathComponent("SyncordaApp")
            guard FileManager.default.isExecutableFile(atPath: sibling.path) else { return }
            process.executableURL = sibling
            process.arguments = ["--headless"]
        }
        try process.run()
    }

    private static func printProcesses(json: Bool) throws {
        let processes = try AudioProcessCatalog.processes()
        if json { printJSON(processes); return }
        for process in processes {
            let bundle = process.bundleIdentifier ?? "—"
            print("\(process.pid)\t\(process.isRunning ? "active" : "idle")\t\(process.name)\t\(bundle)")
        }
    }

    private static func printOutputs(json: Bool) throws {
        let outputs = try AudioDeviceCatalog.outputs()
        if json { printJSON(outputs); return }
        for output in outputs {
            let rate = String(format: "%.0f Hz", output.sampleRate)
            print("\(output.uid)\t\(output.name)\t\(output.transport)\t\(rate)\t\(output.outputChannels)ch\t\(output.isAlive ? "available" : "offline")")
        }
    }

    private static func printResponse(_ response: ControlResponse, json: Bool) throws {
        if json { printJSON(response); return }
        print(response.ok ? response.message : "Error: \(response.message)")
        if let status = response.status {
            print("State: \(status.state.rawValue) — \(status.message)")
            for output in status.outputs {
                print("  \(output.name): \(Int((output.gain * 100).rounded()))% volume, +\(String(format: "%.0f", output.extraDelayMilliseconds)) ms, \(output.underruns) underrun frames")
            }
        }
        if !response.ok { throw CLIError.service(response.message) }
    }

    private static func printJSON<T: Encodable>(_ value: T) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(value), let string = String(data: data, encoding: .utf8) { print(string) }
    }

    private static func printHelp() {
        print("""
        syncordactl — control Syncorda from the command line

        syncordactl sources list [--json]
        syncordactl outputs list [--json]
        syncordactl start --source BUNDLE_OR_PID --output DEVICE_UID[=DELAY_MS] [--output …]
        syncordactl set-delay --output DEVICE_UID --milliseconds DELAY_MS
        syncordactl set-volume --output DEVICE_UID --percent 0..100
        syncordactl status [--json]
        syncordactl stop
        syncordactl profile save NAME --source BUNDLE_OR_PID --output DEVICE_UID[=DELAY_MS] [--output …]
        syncordactl profile apply NAME

        A positive delay delays only that output. UIDs come from `syncordactl outputs list`.
        """)
    }

    private static func writeError(_ message: String) {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
    }
}
