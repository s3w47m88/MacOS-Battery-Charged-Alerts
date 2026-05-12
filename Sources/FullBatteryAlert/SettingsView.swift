import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var battery: BatteryMonitor
    @ObservedObject var energy: EnergyMonitor
    var onTestAlert: () -> Void = {}
    @State private var newThreshold: Double = 90
    @State private var hintMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Native-style battery header
            HStack(alignment: .firstTextBaseline) {
                Text("Battery").font(.headline)
                Spacer()
                Text("\(battery.percentage)%")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Power Source: \(powerSourceText)")
                if let timeText = timeRemainingText {
                    Text(timeText).foregroundStyle(.secondary)
                }
            }
            .font(.callout)

            Divider()

            Text("Energy Mode").font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
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
                .font(.callout)
            }
            .font(.callout)

            Divider()

            EnergyListView(monitor: energy, onSelect: handleSelect)
            if let hint = hintMessage {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }

            Divider()

            Text("Alert Thresholds").font(.subheadline.weight(.semibold))

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
                Button("Add") {
                    settings.addThreshold(Int(newThreshold))
                }
            }

            Toggle("Play sound with alert", isOn: $settings.playSound)
                .font(.callout)

            Toggle("Show percentage inside the icon", isOn: $settings.showPercentageInIcon)
                .font(.callout)

            Divider()

            Text("System Battery Indicator").font(.subheadline.weight(.semibold))
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

    private func handleSelect(_ app: AppEnergy) {
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
