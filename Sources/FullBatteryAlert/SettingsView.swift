import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var battery: BatteryMonitor
    var onTestAlert: () -> Void = {}
    @State private var newThreshold: Double = 90

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: batteryIcon)
                    .font(.title2)
                Text("\(battery.percentage)%")
                    .font(.title2.weight(.semibold))
                Spacer()
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Text("Alert thresholds")
                .font(.headline)

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

            Divider()

            Toggle("Play sound with alert", isOn: $settings.playSound)

            Divider()

            HStack {
                Button("Send test alert") { onTestAlert() }
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    private var batteryIcon: String {
        if battery.isCharging { return "battery.100.bolt" }
        switch battery.percentage {
        case 90...: return "battery.100"
        case 65...: return "battery.75"
        case 40...: return "battery.50"
        case 15...: return "battery.25"
        default: return "battery.0"
        }
    }

    private var statusText: String {
        if battery.isCharging { return "Charging" }
        if battery.isPluggedIn { return "Plugged in" }
        return "On battery"
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
            Button {
                onRemove()
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
        }
    }
}
