import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var battery: BatteryMonitor
    @ObservedObject var energy: EnergyMonitor
    @ObservedObject var peripherals: PeripheralBatteryMonitor
    @StateObject private var stats = BatteryStats()
    var onTestAlert: () -> Void = {}
    @State private var newThreshold: Double = 90
    @State private var hintMessage: String?

    init(settings: AppSettings,
         battery: BatteryMonitor,
         energy: EnergyMonitor,
         peripherals: PeripheralBatteryMonitor = PeripheralBatteryMonitor(),
         onTestAlert: @escaping () -> Void = {}) {
        self.settings = settings
        self.battery = battery
        self.energy = energy
        self.peripherals = peripherals
        self.onTestAlert = onTestAlert
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                // Header
                HStack(alignment: .firstTextBaseline) {
                    Text("Battery").font(.headline)
                    Spacer()
                    Text("\(battery.percentage)%")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                AccordionSection(id: "general", title: "General", defaultOpen: true) {
                    generalSection
                }

                AccordionSection(id: "alerts", title: "Alerts", defaultOpen: true) {
                    alertsSection
                }

                AccordionSection(id: "health", title: "Battery Health") {
                    healthSection
                }

                AccordionSection(id: "temperature", title: "Temperature") {
                    temperatureSection
                }

                AccordionSection(id: "power", title: "Power & Electrical") {
                    powerSection
                }

                AccordionSection(id: "capacity", title: "Capacity Details") {
                    capacitySection
                }

                PeripheralAccordionSection(monitor: peripherals)

                AccordionSection(id: "apps", title: "Apps Using Energy") {
                    EnergyListView(monitor: energy, onAction: handleAction)
                    if let hint = hintMessage {
                        Text(hint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .transition(.opacity)
                    }
                }

                AccordionSection(id: "preferences", title: "Preferences") {
                    preferencesSection
                }

                Divider()

                HStack {
                    Button("Send test alert") { onTestAlert() }
                    Spacer()
                    Button("Quit") { NSApplication.shared.terminate(nil) }
                        .keyboardShortcut("q")
                }
            }
            .padding(16)
            .frame(width: 340)
        }
        .frame(width: 340, height: AccordionSectionConfig.forceOpen == nil ? 480 : nil)
        .onAppear { stats.start() }
        .onDisappear { stats.stop() }
    }

    // MARK: - Sections

    @ViewBuilder private var generalSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            row("Charge", value: "\(battery.percentage)%")
            row("Power Source", value: powerSourceText)
            if let timeText = timeRemainingText {
                row("Time", value: timeText)
            }
            if let powerText = powerFlowText {
                row("State", value: powerText)
            }
        }
        .font(.callout)
    }

    @ViewBuilder private var alertsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Alert Thresholds").font(.caption).foregroundStyle(.secondary)
            if settings.thresholds.isEmpty {
                Text("No thresholds set.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                ForEach(Array(settings.thresholds.enumerated()), id: \.offset) { idx, value in
                    ThresholdRow(
                        value: Binding(
                            get: { Double(value) },
                            set: { settings.setThreshold(at: idx, to: Int($0)) }
                        ),
                        onRemove: { settings.removeThreshold(at: idx) }
                    )
                }
            }
            HStack {
                Slider(value: $newThreshold, in: 1...100, step: 1)
                Text("\(Int(newThreshold))%")
                    .frame(width: 44, alignment: .trailing)
                    .monospacedDigit()
                Button("Add") { settings.addThreshold(Int(newThreshold)) }
            }
            Toggle("Play sound with alert", isOn: $settings.playSound)
                .font(.callout)

            Divider()
            Text("Peripheral Devices").font(.caption).foregroundStyle(.secondary)
            Toggle("Alert on peripheral low battery", isOn: $settings.peripheralAlertsEnabled)
                .font(.callout)
            HStack {
                Text("Low")
                Slider(value: Binding(
                    get: { Double(settings.peripheralLowThreshold) },
                    set: { settings.peripheralLowThreshold = Int($0) }
                ), in: 5...50, step: 1)
                Text("\(settings.peripheralLowThreshold)%")
                    .frame(width: 44, alignment: .trailing)
                    .monospacedDigit()
            }
            .font(.callout)
            .disabled(!settings.peripheralAlertsEnabled)
            HStack {
                Text("Critical")
                Slider(value: Binding(
                    get: { Double(settings.peripheralCriticalThreshold) },
                    set: { settings.peripheralCriticalThreshold = Int($0) }
                ), in: 1...30, step: 1)
                Text("\(settings.peripheralCriticalThreshold)%")
                    .frame(width: 44, alignment: .trailing)
                    .monospacedDigit()
            }
            .font(.callout)
            .disabled(!settings.peripheralAlertsEnabled)
        }
    }

    @ViewBuilder private var healthSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            row("Cycle Count", value: battery.cycleCount.map { "\($0) / \(BatteryMonitor.maxCycles)" } ?? "—")
            row("Health", value: battery.healthPercent.map { "\($0)%" } ?? "—",
                color: healthColor(battery.healthPercent))
            if let status = stats.macOSHealthStatus {
                row("Status", value: status)
            }
            if let cond = stats.macOSHealthCondition {
                row("Condition", value: cond)
            }
            row("Est. Replacement", value: replacementText)
            if let y = stats.ageYears, let m = stats.ageMonths {
                row("Age", value: "\(y)y \(m)m")
            }
            if let d = stats.manufacturedDate {
                row("Manufactured", value: mediumDate(d))
            }
        }
        .font(.callout)
    }

    @ViewBuilder private var temperatureSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let c = stats.temperatureCelsius, let f = stats.temperatureFahrenheit {
                row("Temperature", value: String(format: "%.1f°C · %.1f°F", c, f))
            } else {
                Text("Gathering temperature data…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var powerSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let w = battery.wattage {
                row("Wattage", value: String(format: "%.1f W", w))
            }
            if let v = battery.voltage {
                row("Voltage", value: String(format: "%.2f V", v))
            }
            if let a = battery.amperage {
                row("Amperage", value: String(format: "%.2f A", a))
            }
            HStack {
                Image(systemName: battery.isLowPowerMode ? "battery.25percent" : "battery.100percent")
                    .foregroundStyle(battery.isLowPowerMode ? .yellow : .secondary)
                Text(battery.isLowPowerMode ? "Low Power" : "Automatic")
                Spacer()
                Button("Battery Settings…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.battery") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link)
            }
        }
        .font(.callout)
    }

    @ViewBuilder private var capacitySection: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let d = stats.designCapacityMah {
                row("Design Capacity", value: "\(d) mAh")
            }
            if let m = stats.maxCapacityMah {
                row("Max Capacity", value: "\(m) mAh")
            }
            if let c = stats.currentCapacityMah {
                row("Current Charge", value: "\(c) mAh")
            }
            if stats.designCapacityMah == nil && stats.maxCapacityMah == nil && stats.currentCapacityMah == nil {
                Text("Gathering capacity data…")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
    }

    @ViewBuilder private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Show percentage inside the icon", isOn: $settings.showPercentageInIcon)
            Toggle("Open on startup", isOn: $settings.openOnStartup)
            Divider()
            Button("Hide system battery indicator") {
                SystemBatteryIndicator.hide()
            }
            Text("Tries to toggle Control Center automatically, then opens System Settings → Control Center so you can flip “Battery → Don’t Show in Menu Bar” if it didn’t take.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Tip: ⌘-drag this icon to reposition.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .font(.callout)
    }

    // MARK: - Helpers

    @ViewBuilder private func row(_ label: String, value: String, color: Color? = nil) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(color ?? .secondary)
        }
    }

    private var powerSourceText: String {
        if battery.isPluggedIn { return battery.isCharging ? "Power Adapter" : "Power Adapter (not charging)" }
        return "Battery"
    }

    private var timeRemainingText: String? {
        if let m = battery.timeToFullMinutes, battery.isCharging {
            return "\(formatMinutes(m)) until fully charged"
        }
        if let m = battery.timeToEmptyMinutes, !battery.isPluggedIn {
            return "\(formatMinutes(m)) remaining"
        }
        if battery.isPluggedIn && !battery.isCharging && battery.percentage >= 100 {
            return "Fully charged"
        }
        return nil
    }

    private func handleAction(_ app: AppEnergy, _ action: EnergyRowAction) {
        switch action {
        case .drillIn:
            drillIn(app)
        case .help:
            openHelpSearch(for: app)
        case .forceQuit:
            confirmAndForceQuit(app)
        }
    }

    private func drillIn(_ app: AppEnergy) {
        switch AppDrillIn.openResourceMonitor(for: app) {
        case .opened:
            hintMessage = nil
        case .hint(let message):
            hintMessage = message
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                if hintMessage == message { hintMessage = nil }
            }
        }
    }

    private func openHelpSearch(for app: AppEnergy) {
        let query = "macOS \(app.displayName) process"
        var components = URLComponents(string: "https://www.google.com/search")!
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        if let url = components.url {
            NSWorkspace.shared.open(url)
        }
    }

    private func confirmAndForceQuit(_ app: AppEnergy) {
        let alert = NSAlert()
        alert.messageText = "Force quit \(app.displayName)?"
        alert.informativeText = "Any unsaved changes in this app will be lost."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Force Quit")
        alert.addButton(withTitle: "Cancel")
        if let popoverWindow = NSApp.keyWindow, popoverWindow.isVisible {
            popoverWindow.makeKeyAndOrderFront(nil)
        }
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }
        forceQuit(app)
    }

    private func forceQuit(_ app: AppEnergy) {
        for pid in app.pids {
            if let running = NSRunningApplication(processIdentifier: pid) {
                running.terminate()
            } else {
                kill(pid, SIGTERM)
            }
        }
    }

    private var powerFlowText: String? {
        guard let v = battery.voltage, let a = battery.amperage, let w = battery.wattage else {
            return nil
        }
        let label: String
        if abs(w) < 0.05 {
            label = "Idle"
        } else if w > 0 {
            label = "Charging"
        } else {
            label = "Discharging"
        }
        let watts = String(format: "%.1f W", abs(w))
        let volts = String(format: "%.2f V", v)
        let amps = String(format: "%.2f A", abs(a))
        return "\(label): \(watts) (\(volts) · \(amps))"
    }

    private var replacementText: String {
        guard let date = battery.estimatedReplacementDate else {
            return "Gathering data…"
        }
        if date <= Date() { return "Now" }
        let when = mediumDate(date)
        let years = date.timeIntervalSinceNow / (365.25 * 86_400)
        let suffix: String
        if years >= 1 {
            suffix = String(format: " (~%.1f yr)", years)
        } else {
            let months = years * 12
            suffix = String(format: " (~%.0f mo)", max(months, 1))
        }
        return when + suffix
    }

    private func mediumDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func healthColor(_ pct: Int?) -> Color {
        guard let p = pct else { return .secondary }
        if p >= 80 { return .green }
        if p >= 60 { return .yellow }
        return .red
    }

    private func formatMinutes(_ m: Int) -> String {
        let h = m / 60, r = m % 60
        if h == 0 { return "\(r)m" }
        if r == 0 { return "\(h)h" }
        return "\(h)h \(r)m"
    }
}

private struct ThresholdRow: View {
    @Binding var value: Double
    let onRemove: () -> Void

    var body: some View {
        HStack {
            Slider(value: $value, in: 1...100, step: 1)
            Text("\(Int(value))%")
                .frame(width: 44, alignment: .trailing)
                .monospacedDigit()
            Button { onRemove() } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
        }
    }
}
