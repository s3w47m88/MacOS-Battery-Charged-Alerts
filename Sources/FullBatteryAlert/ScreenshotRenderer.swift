import SwiftUI
import AppKit

@MainActor
enum ScreenshotRenderer {
    static func render(settings: AppSettings, battery: BatteryMonitor, energy: EnergyMonitor, to path: String) {
        // Optional override: FBA_ACCORDION_STATE=expanded|collapsed forces every
        // accordion to the given state before the SwiftUI tree reads @AppStorage.
        if let state = ProcessInfo.processInfo.environment["FBA_ACCORDION_STATE"] {
            AccordionSectionConfig.forceOpen = (state == "expanded")
            NSLog("FBA_ACCORDION_STATE=\(state) forceOpen=\(String(describing: AccordionSectionConfig.forceOpen))")
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.appearance = NSAppearance(named: .darkAqua)

        let root = SettingsView(settings: settings, battery: battery, energy: energy)
            .background(Color(nsColor: NSColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1.0)))
            .environment(\.colorScheme, .dark)

        let host = NSHostingView(rootView: root)
        host.appearance = NSAppearance(named: .darkAqua)
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()

        // Place far enough off-screen that it can't appear on any visible display
        // but is still committed to the window server for CGWindowListCreateImage.
        let window = NSWindow(
            contentRect: NSRect(x: -10_000, y: -10_000, width: size.width, height: size.height),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.appearance = NSAppearance(named: .darkAqua)
        window.isOpaque = true
        window.backgroundColor = NSColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1.0)
        window.contentView = host
        window.orderFrontRegardless()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            let windowID = CGWindowID(window.windowNumber)
            guard let cgImage = CGWindowListCreateImage(
                .null, .optionIncludingWindow, windowID, [.bestResolution, .boundsIgnoreFraming]
            ) else {
                NSApp.terminate(nil); return
            }
            let rep = NSBitmapImageRep(cgImage: cgImage)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: path))
            }
            NSApp.terminate(nil)
        }
    }
}
