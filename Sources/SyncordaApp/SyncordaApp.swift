import AppKit
import Combine
import SwiftUI
import SyncordaCore

@main
struct SyncordaApp: App {
    init() {
        if CommandLine.arguments.contains("--headless") {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    var body: some Scene {
        WindowGroup("Syncorda") {
            if #available(macOS 14.2, *) {
                SyncordaRootView()
            } else {
                ContentUnavailableView(
                    "macOS 14.2 required",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Syncorda needs Core Audio process taps, introduced in macOS 14.2.")
                )
            }
        }
        .defaultSize(width: 960, height: 720)
    }
}

@available(macOS 14.2, *)
private struct OutputRow: Identifiable {
    let device: AudioDeviceDescriptor
    var enabled: Bool
    var delayMilliseconds: Double
    var muted: Bool = false
    var gain: Float = 1

    var id: String { device.uid }
    var route: OutputRoute {
        OutputRoute(
            deviceUID: device.uid,
            extraDelayMilliseconds: delayMilliseconds,
            gain: gain,
            isMuted: muted,
            isEnabled: enabled
        )
    }
}

@available(macOS 14.2, *)
@MainActor
private final class SyncordaViewModel: ObservableObject {
    @Published var processes: [AudioProcessDescriptor] = []
    @Published var outputs: [OutputRow] = []
    @Published var selectedPID: Int32?
    @Published var status = RouteStatus(state: .stopped, message: "Ready to route")
    @Published var errorMessage: String?
    @Published var profileName = "chrome-kitchen"

    private let service = SyncordaService()
    private var lastConfigurationRevision = UInt64.max

    init() {
        do { try service.startControlServer() }
        catch { errorMessage = "Control service: \(error.localizedDescription)" }
        refresh()
    }

    func refresh() {
        do {
            processes = try AudioProcessCatalog.processes().filter(\.isRunning)
            let currentRows = Dictionary(uniqueKeysWithValues: outputs.map { ($0.id, $0) })
            outputs = try AudioDeviceCatalog.outputs().map { device in
                guard let previous = currentRows[device.uid] else {
                    return OutputRow(
                        device: device,
                        enabled: device.uid == "BuiltInSpeakerDevice",
                        delayMilliseconds: device.uid == "BuiltInSpeakerDevice" ? 0 : 250
                    )
                }
                return OutputRow(
                    device: device,
                    enabled: previous.enabled,
                    delayMilliseconds: previous.delayMilliseconds,
                    muted: previous.muted,
                    gain: previous.gain
                )
            }
            if selectedPID == nil {
                selectedPID = processes.first(where: { $0.bundleIdentifier?.lowercased().hasPrefix("com.google.chrome") == true })?.pid ?? processes.first?.pid
            }
            status = service.status()
            errorMessage = nil
            synchronizeConfigurationIfNeeded()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func start() {
        guard let selectedPID else { errorMessage = "Choose a running audio source."; return }
        let configuration = RouteConfiguration(source: .processID(selectedPID), outputs: outputs.map(\.route))
        do {
            status = try service.start(configuration)
            synchronizeConfigurationIfNeeded()
            errorMessage = nil
        } catch {
            status = service.status()
            errorMessage = error.localizedDescription
        }
    }

    func stop() { status = service.stop() }

    func updateLive(_ row: OutputRow) {
        guard status.state == .running else { return }
        status = service.update(row.route)
        synchronizeConfigurationIfNeeded()
    }

    func saveProfile() {
        guard let selectedPID, !profileName.isEmpty else { errorMessage = "Give this profile a name."; return }
        let configuration = RouteConfiguration(source: .processID(selectedPID), outputs: outputs.map(\.route))
        let response = service.handle(ControlRequest(command: "save-profile", configuration: configuration, profileName: profileName))
        if !response.ok { errorMessage = response.message }
    }

    func pollStatus() {
        status = service.status()
        synchronizeConfigurationIfNeeded()
    }

    private func synchronizeConfigurationIfNeeded() {
        let snapshot = service.snapshot()
        guard snapshot.revision != lastConfigurationRevision else { return }
        defer { lastConfigurationRevision = snapshot.revision }
        guard let configuration = snapshot.configuration else { return }

        for index in outputs.indices {
            guard let route = configuration.outputs.first(where: { $0.deviceUID == outputs[index].device.uid }) else {
                outputs[index].enabled = false
                continue
            }
            outputs[index].enabled = route.isEnabled
            outputs[index].delayMilliseconds = route.extraDelayMilliseconds
            outputs[index].muted = route.isMuted
            outputs[index].gain = route.gain
        }

        switch configuration.source {
        case let .processID(pid):
            selectedPID = pid
        case let .bundleIdentifier(bundleIdentifier):
            selectedPID = (try? AudioProcessCatalog.resolve(.bundleIdentifier(bundleIdentifier)))?.pid
        }
    }
}

@available(macOS 14.2, *)
private struct SyncordaRootView: View {
    @StateObject private var model = SyncordaViewModel()
    private let statusTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                sourceSection
                outputsSection
                routeControls

                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: 1_080, alignment: .leading)
            .padding(24)
        }
        .onReceive(statusTimer) { _ in model.pollStatus() }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 38, height: 38)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text("Syncorda")
                    .font(.title2.weight(.semibold))
                Text("Route one app to local speakers with independent timing.")
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 16)
            Label(model.status.state.rawValue.capitalized, systemImage: statusSymbol)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(statusColor)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(statusColor.opacity(0.12), in: Capsule())
        }
    }

    private var sourceSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Audio source", selection: $model.selectedPID) {
                    Text("Choose a source").tag(Int32?.none)
                    ForEach(model.processes) { process in
                        Text("\(process.name) — \(process.bundleIdentifier ?? "unknown")").tag(Optional(process.pid))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    Text("Select the app process whose normal route Syncorda should take over.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Refresh", systemImage: "arrow.clockwise", action: model.refresh)
                        .labelStyle(.titleAndIcon)
                }
            }
            .padding(.top, 3)
        } label: {
            Label("Source", systemImage: "waveform")
                .font(.headline)
        }
    }

    private var outputsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("Outputs", systemImage: "hifispeaker.2")
                    .font(.headline)
                Spacer()
                Text("Changes apply immediately while routing")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if model.outputs.isEmpty {
                ContentUnavailableView("No output devices found", systemImage: "speaker.slash", description: Text("Connect or enable an output in macOS, then refresh."))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach($model.outputs) { $row in
                        OutputRouteCard(row: $row, onUpdate: model.updateLive)
                    }
                }
            }
        }
    }

    private var routeControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Label(model.status.message, systemImage: statusSymbol)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer(minLength: 12)
                TextField("Profile name", text: $model.profileName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                Button("Save Profile", action: model.saveProfile)
            }

            HStack {
                Text("Use the wide sliders for quick changes; type an exact value or use the stepper for fine adjustment.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if model.status.state == .running {
                    Button("Stop Routing", systemImage: "stop.fill", role: .destructive, action: model.stop)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                } else {
                    Button("Start Routing", systemImage: "play.fill", action: model.start)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(16)
        .background(.bar, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var statusColor: Color {
        switch model.status.state {
        case .running: .green
        case .failed: .red
        case .starting: .orange
        case .stopped: .secondary
        }
    }

    private var statusSymbol: String {
        switch model.status.state {
        case .running: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .starting: "arrow.triangle.2.circlepath"
        case .stopped: "pause.circle"
        }
    }
}

@available(macOS 14.2, *)
private struct OutputRouteCard: View {
    @Binding var row: OutputRow
    let onUpdate: (OutputRow) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: transportSymbol)
                    .symbolRenderingMode(.hierarchical)
                    .font(.title2)
                    .foregroundStyle(row.enabled ? Color.accentColor : .secondary)
                    .frame(width: 30)

                Toggle(isOn: $row.enabled) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.device.name)
                            .font(.headline)
                        Text("\(row.device.transport) · \(Int(row.device.sampleRate)) Hz · \(row.device.uid)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .toggleStyle(.switch)

                Spacer(minLength: 12)

                Toggle("Mute", isOn: $row.muted)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            Divider()

            VStack(spacing: 13) {
                LabeledContent {
                    HStack(spacing: 10) {
                        Slider(value: volumePercent, in: 0...100, step: 0.1)
                            .frame(minWidth: 300, idealWidth: 380, maxWidth: .infinity)
                            .accessibilityLabel("Volume for \(row.device.name)")
                        TextField("Volume", value: volumePercent, format: .number.precision(.fractionLength(0...1)))
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 76)
                            .accessibilityLabel("Exact volume percentage for \(row.device.name)")
                        Text("%")
                            .foregroundStyle(.secondary)
                            .frame(width: 12, alignment: .leading)
                        Stepper("Adjust volume", value: volumePercent, in: 0...100, step: 0.1)
                            .labelsHidden()
                            .accessibilityLabel("Adjust volume for \(row.device.name) by 0.1 percent")
                    }
                } label: {
                    Text("Volume")
                        .frame(width: 64, alignment: .leading)
                }

                LabeledContent {
                    HStack(spacing: 10) {
                        Slider(value: $row.delayMilliseconds, in: 0...1_000, step: 1)
                            .frame(minWidth: 300, idealWidth: 380, maxWidth: .infinity)
                            .accessibilityLabel("Delay for \(row.device.name)")
                        TextField("Delay", value: $row.delayMilliseconds, format: .number.precision(.fractionLength(0)))
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 76)
                            .accessibilityLabel("Exact delay in milliseconds for \(row.device.name)")
                        Text("ms")
                            .foregroundStyle(.secondary)
                            .frame(width: 18, alignment: .leading)
                        Stepper("Adjust delay", value: $row.delayMilliseconds, in: 0...1_000, step: 1)
                            .labelsHidden()
                            .accessibilityLabel("Adjust delay for \(row.device.name) by one millisecond")
                    }
                } label: {
                    Text("Delay")
                        .frame(width: 64, alignment: .leading)
                }
            }
            .disabled(!row.enabled)
            .opacity(row.enabled ? 1 : 0.55)

            Text("Positive delay holds this output back. Turning on an inactive output requires a route restart to create its renderer.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.separator.opacity(0.55), lineWidth: 1)
        }
        .onChange(of: row.enabled) { _, _ in onUpdate(row) }
        .onChange(of: row.muted) { _, _ in onUpdate(row) }
        .onChange(of: row.gain) { _, _ in onUpdate(row) }
        .onChange(of: row.delayMilliseconds) { _, _ in onUpdate(row) }
    }

    private var volumePercent: Binding<Double> {
        Binding(
            get: { Double(row.gain) * 100 },
            set: { row.gain = Float(max(0, min(100, $0)) / 100) }
        )
    }

    private var transportSymbol: String {
        switch row.device.transport {
        case "Bluetooth", "Bluetooth LE": "wave.3.right.circle"
        case "AirPlay": "rectangle.inset.filled.airplay"
        case "USB": "cable.connector"
        case "Built-in": "laptopcomputer"
        case "Virtual": "circle.dotted.circle"
        default: "speaker.wave.2"
        }
    }
}
