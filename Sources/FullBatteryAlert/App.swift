import SwiftUI
import AppKit

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

    private var statusItem: NSStatusItem!
    private var settingsPopover: NSPopover!
    private var alertPopover: NSPopover!
    private var alertDismissTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupPopovers()
        updateIcon()

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
        let bucket: Int
        switch pct {
        case 88...: bucket = 100
        case 63...: bucket = 75
        case 38...: bucket = 50
        case 13...: bucket = 25
        default: bucket = 0
        }
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
            .applying(.init(scale: .medium))
        // Always use the plain percent variant for accurate fill, then overlay a
        // bolt manually when charging. The SF Symbol "battery.XXpercent.bolt"
        // variants don't preserve the fill bar — they replace it with the bolt —
        // so direct use makes the charging icon look identical at every level.
        guard let base = NSImage(systemSymbolName: "battery.\(bucket)percent", accessibilityDescription: "Battery \(pct)%")?
            .withSymbolConfiguration(config) else { return }
        let final = (battery.isCharging || battery.isPluggedIn)
            ? composeBatteryWithBolt(base: base) ?? base
            : base
        final.isTemplate = true
        button.image = final
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.toolTip = "\(pct)%" + (battery.isCharging ? " (charging)" : battery.isPluggedIn ? " (plugged in)" : "")
    }

    private func composeBatteryWithBolt(base: NSImage) -> NSImage? {
        let boltConfig = NSImage.SymbolConfiguration(pointSize: 9, weight: .heavy)
        guard let bolt = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(boltConfig) else { return nil }
        let size = base.size
        let composed = NSImage(size: size)
        composed.lockFocus()
        base.draw(at: .zero, from: NSRect(origin: .zero, size: size), operation: .sourceOver, fraction: 1.0)
        let boltSize = bolt.size
        let origin = NSPoint(
            x: (size.width - boltSize.width) / 2.0,
            y: (size.height - boltSize.height) / 2.0 - 0.5
        )
        // Knock out a bolt-shaped notch in the fill so the bolt stays legible.
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        bolt.draw(at: origin, from: NSRect(origin: .zero, size: boltSize), operation: .destinationOut, fraction: 1.0)
        // Redraw a slightly inset bolt as the visible glyph.
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        bolt.draw(at: origin, from: NSRect(origin: .zero, size: boltSize), operation: .sourceOver, fraction: 1.0)
        composed.unlockFocus()
        return composed
    }

    @objc private func toggleSettings(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if settingsPopover.isShown {
            settingsPopover.performClose(nil)
        } else {
            alertPopover.performClose(nil)
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
