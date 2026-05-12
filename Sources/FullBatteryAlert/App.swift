import SwiftUI
import AppKit
import Combine

@main
struct FullBatteryAlertApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        Settings { EmptyView() } // Required Scene; never shown (LSUIElement).
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private let battery = BatteryMonitor()
    private let energy = EnergyMonitor()

    private var statusItem: NSStatusItem!
    private var settingsPopover: NSPopover!
    private var alertPopover: NSPopover!
    private var alertDismissTimer: Timer?
    private var settingsCancellable: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupPopovers()
        updateIcon()

        // Re-render the icon when the percent-in-icon toggle changes.
        settingsCancellable = settings.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateIcon() }
        }

        battery.onChange = { [weak self] pct, charging, plugged in
            guard let self else { return }
            self.updateIcon()
            AlertManager.shared.handleUpdate(
                percentage: pct, isCharging: charging, isPluggedIn: plugged,
                settings: self.settings,
                onFire: { threshold in
                    self.presentAlertPopover(threshold: threshold, percentage: pct)
                }
            )
        }
        AlertManager.shared.handleUpdate(
            percentage: battery.percentage, isCharging: battery.isCharging, isPluggedIn: battery.isPluggedIn,
            settings: settings, onFire: { _ in }
        )
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(toggleSettings(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func setupPopovers() {
        settingsPopover = NSPopover()
        settingsPopover.behavior = .transient
        settingsPopover.contentSize = NSSize(width: 320, height: 360)
        settingsPopover.contentViewController = NSHostingController(
            rootView: SettingsView(
                settings: settings,
                battery: battery,
                energy: energy,
                onTestAlert: { [weak self] in self?.presentAlertPopover(threshold: 100, percentage: self?.battery.percentage ?? 100) }
            )
        )

        alertPopover = NSPopover()
        alertPopover.behavior = .semitransient
        alertPopover.contentSize = NSSize(width: 280, height: 110)
    }

    private func updateIcon() {
        guard let button = statusItem?.button else { return }
        let pct = max(0, min(100, battery.percentage))
        let img = BatteryIconRenderer.render(
            percentage: pct,
            isCharging: battery.isCharging,
            isPluggedIn: battery.isPluggedIn,
            showPercentage: settings.showPercentageInIcon
        )
        button.image = img
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.toolTip = "\(pct)%" + (battery.isCharging ? " (charging)" : battery.isPluggedIn ? " (plugged in)" : "")
    }

    @objc private func toggleSettings(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if settingsPopover.isShown {
            settingsPopover.performClose(nil)
            energy.stop()
        } else {
            alertPopover.performClose(nil)
            energy.start()
            settingsPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            settingsPopover.contentViewController?.view.window?.makeKey()
        }
    }

    func presentAlertPopover(threshold: Int, percentage: Int) {
        guard let button = statusItem.button else { return }
        let title: String
        let body: String
        if threshold >= 100 {
            title = "Battery Fully Charged"
            body = "Your Mac is at \(percentage)%. Unplug to preserve battery health."
        } else {
            title = "Battery at \(threshold)%"
            body = "Charging is approaching full (\(percentage)%)."
        }
        alertPopover.contentViewController = NSHostingController(
            rootView: AlertBubbleView(title: title, message: body, onDismiss: { [weak self] in
                self?.alertPopover.performClose(nil)
            })
        )
        if !alertPopover.isShown {
            alertPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        alertDismissTimer?.invalidate()
        alertDismissTimer = Timer.scheduledTimer(withTimeInterval: 6.0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.alertPopover.performClose(nil) }
        }
        if settings.playSound {
            NSSound(named: "Glass")?.play()
        }
    }
}
