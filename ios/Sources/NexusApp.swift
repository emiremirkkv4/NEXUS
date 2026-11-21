import SwiftUI
import Charts

private let navy = Color(red: 0.035, green: 0.055, blue: 0.10)
private let panel = Color(red: 0.075, green: 0.115, blue: 0.18)

@main
struct NexusApp: App {
    @StateObject private var monitor = Monitor()
    var body: some Scene {
        WindowGroup {
            TabView {
                Dashboard().tabItem { Label("Dashboard", systemImage: "waveform.path.ecg") }
                Devices().tabItem { Label("Devices", systemImage: "desktopcomputer") }
                SettingsView().tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
            }
            .environmentObject(monitor)
            .preferredColorScheme(.dark)
            .tint(.cyan)
        }
    }
}

private struct Page<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label("NEXUS   /   MISSION CONTROL", systemImage: "waveform")
                    .font(.caption.monospaced().weight(.bold)).foregroundStyle(.cyan)
                    .accessibilityLabel("Nexus Mission Control")
                Text(title).font(.largeTitle.bold())
                content
            }.padding(20).frame(maxWidth: 620)
        }.frame(maxWidth: .infinity).background(navy)
    }
}

private extension View {
    func card() -> some View {
        padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(panel, in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct Connection: View {
    @EnvironmentObject var monitor: Monitor
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(monitor.status, systemImage: "antenna.radiowaves.left.and.right")
                .foregroundStyle(monitor.status == "Online" ? Color.cyan : Color.secondary)
            Text(monitor.detail).font(.footnote).foregroundStyle(.secondary)
        }.card()
    }
}

private struct Reading: View {
    let title: String
    let value: String
    let symbol: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.subheadline).foregroundStyle(.secondary)
            Text(value).font(.title2.bold().monospacedDigit()).contentTransition(.numericText())
        }.card().accessibilityElement(children: .combine)
    }
}

private struct Dashboard: View {
    @EnvironmentObject var monitor: Monitor
    var sample: Sample? { monitor.samples.last }
    private func percent(_ value: Double?) -> String {
        value.map { $0.formatted(.number.precision(.fractionLength(1))) + "%" } ?? "—"
    }
    var body: some View {
        Page(title: "Dashboard") {
            Connection()
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 135))], spacing: 12) {
                Reading(title: "Processor", value: percent(sample?.cpu_percent), symbol: "cpu")
                Reading(title: "Memory", value: percent(sample?.ram_percent), symbol: "memorychip")
                Reading(title: "System disk", value: percent(sample?.disk_percent), symbol: "internaldrive")
                Reading(title: "Uptime", value: sample.map {
                    "\($0.uptime_seconds / 86400)d \($0.uptime_seconds / 3600 % 24)h \($0.uptime_seconds / 60 % 60)m"
                } ?? "—", symbol: "clock")
            }.animation(.easeOut(duration: 0.25), value: sample?.id)
            VStack(alignment: .leading, spacing: 12) {
                Text("Resource history").font(.headline)
                if monitor.samples.isEmpty {
                    Text("Waiting for the first reading").foregroundStyle(.secondary).frame(height: 140)
                } else {
                    Chart(monitor.samples) { s in
                        LineMark(x: .value("Time", s.time), y: .value("Usage %", s.cpu_percent))
                            .foregroundStyle(by: .value("Resource", "CPU")).symbol(.circle)
                        LineMark(x: .value("Time", s.time), y: .value("Usage %", s.ram_percent))
                            .foregroundStyle(by: .value("Resource", "RAM")).symbol(.square)
                    }.chartForegroundStyleScale(["CPU": Color.cyan, "RAM": Color.blue])
                        .chartYScale(domain: 0...100).frame(height: 165)
                }
            }.card()
            if let sample {
                Text("Last sample  " + sample.time.formatted(date: .omitted, time: .standard))
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
            }
        }
    }
}

private struct Devices: View {
    @EnvironmentObject var monitor: Monitor
    var body: some View {
        Page(title: "Devices") {
            VStack(alignment: .leading, spacing: 8) {
                Label(monitor.samples.last?.hostname ?? "Windows PC", systemImage: "desktopcomputer")
                    .font(.headline)
                Text(monitor.status).foregroundStyle(.cyan)
                if let os = monitor.samples.last?.os { Text(os).font(.caption) }
            }.card()
            ForEach(["ESP32", "ESP32-CAM", "3D printer"], id: \.self) { name in
                VStack(alignment: .leading, spacing: 6) {
                    Text(name).font(.headline)
                    Text("Future integration").font(.caption).foregroundStyle(.secondary)
                }.card()
            }
        }
    }
}

private struct SettingsView: View {
    @EnvironmentObject var monitor: Monitor
    @AppStorage("pcHost") var host = "192.168.0.12"
    @AppStorage("pcPort") var port = "8765"
    @AppStorage("interval") var interval = 2
    @State private var token = ""
    var body: some View {
        Page(title: "Settings") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Windows server").font(.headline)
                Menu("Choose server address") {
                    ForEach(["192.168.0.12", "192.168.56.1", "127.0.0.1"], id: \.self) { address in
                        Button(address) { host = address; token = "" }
                    }
                }
                Text(host == "127.0.0.1" ? "Loopback reaches this phone. A local forward is required to reach the PC." :
                     host == "192.168.56.1" ? "Requires a network route to this PC interface." :
                     "Start the Windows server on the same address.")
                    .font(.footnote).foregroundStyle(.secondary)
                TextField("PC IPv4 address", text: $host).keyboardType(.decimalPad)
                TextField("Server port", text: $port).keyboardType(.numberPad)
                SecureField("Pairing token", text: $token)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                Text("Leave the token blank to reuse the Keychain entry for this address and port.")
                    .font(.footnote).foregroundStyle(.secondary)
                Stepper("Refresh every \(interval)s", value: $interval, in: 2...30)
            }.textFieldStyle(.roundedBorder).disabled(monitor.active).card()
            Button {
                if monitor.active { monitor.disconnect() }
                else {
                    monitor.connect(host: host.trimmingCharacters(in: .whitespacesAndNewlines),
                                    port: port, typedToken: token.trimmingCharacters(in: .whitespacesAndNewlines),
                                    interval: interval)
                    token = ""
                }
            } label: {
                Text(monitor.active ? "Disconnect" : "Connect").frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent)
            Connection()
        }.scrollDismissesKeyboard(.interactively)
    }
}
