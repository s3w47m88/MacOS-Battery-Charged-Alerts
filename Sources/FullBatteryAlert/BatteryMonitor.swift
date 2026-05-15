import Foundation
import IOKit
import IOKit.ps
import Combine

final class BatteryMonitor: ObservableObject {
    @Published private(set) var percentage: Int = 0
    @Published private(set) var isCharging: Bool = false
    @Published private(set) var isPluggedIn: Bool = false
    /// Minutes to full charge while charging, or nil if unknown/discharging.
    @Published private(set) var timeToFullMinutes: Int? = nil
    /// Minutes to empty while on battery, or nil if unknown/charging.
    @Published private(set) var timeToEmptyMinutes: Int? = nil
    @Published private(set) var isLowPowerMode: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled
    /// Battery terminal voltage in volts.
    @Published private(set) var voltage: Double? = nil
    /// Current flow in amps. Positive when charging, negative when discharging.
    @Published private(set) var amperage: Double? = nil
    /// Power flow in watts (voltage × amperage), signed like amperage.
    @Published private(set) var wattage: Double? = nil
    /// Charge cycles reported by AppleSmartBattery.
    @Published private(set) var cycleCount: Int? = nil
    /// Battery health as MaxCapacity / DesignCapacity, in percent (0–100).
    @Published private(set) var healthPercent: Int? = nil
    /// Projected date the battery will reach `maxCycles`, based on observed cycle rate.
    @Published private(set) var estimatedReplacementDate: Date? = nil

    /// Apple's rated cycle count for modern Mac notebook batteries.
    static let maxCycles: Int = 1000

    private var smartBatteryRefreshTimer: Timer?

    private var runLoopSource: CFRunLoopSource?
    var onChange: ((Int, Bool, Bool) -> Void)?

    init() {
        refresh()
        startObserving()
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSProcessInfoPowerStateDidChange,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        // IOPS callbacks only fire on percentage/charging-state changes, but
        // amperage drifts continuously. Poll AppleSmartBattery on a timer so
        // live wattage stays fresh.
        smartBatteryRefreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.refreshSmartBattery()
        }
    }

    deinit {
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), src, .defaultMode)
        }
        smartBatteryRefreshTimer?.invalidate()
    }

    private func startObserving() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { ctx in
            guard let ctx else { return }
            let mySelf = Unmanaged<BatteryMonitor>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async { mySelf.refresh() }
        }
        if let src = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            runLoopSource = src
            CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .defaultMode)
        }
    }

    func refresh() {
        guard let snap = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snap)?.takeRetainedValue() as? [CFTypeRef]
        else { return }

        for src in sources {
            guard let info = IOPSGetPowerSourceDescription(snap, src)?.takeUnretainedValue() as? [String: Any] else { continue }
            let current = info[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = info[kIOPSMaxCapacityKey] as? Int ?? 100
            let state = info[kIOPSPowerSourceStateKey] as? String ?? ""
            let charging = info[kIOPSIsChargingKey] as? Bool ?? false
            let pct = max > 0 ? Int(round(Double(current) / Double(max) * 100.0)) : 0
            let plugged = (state == kIOPSACPowerValue)
            let toFullRaw = info[kIOPSTimeToFullChargeKey] as? Int ?? -1
            let toEmptyRaw = info[kIOPSTimeToEmptyKey] as? Int ?? -1

            let oldPct = percentage
            let oldCharging = isCharging
            let oldPlugged = isPluggedIn
            percentage = pct
            isCharging = charging
            isPluggedIn = plugged
            timeToFullMinutes = (charging && toFullRaw > 0) ? toFullRaw : nil
            timeToEmptyMinutes = (!plugged && toEmptyRaw > 0) ? toEmptyRaw : nil

            if pct != oldPct || charging != oldCharging || plugged != oldPlugged {
                onChange?(pct, charging, plugged)
            }
            refreshSmartBattery()
            return
        }
    }

    private func refreshSmartBattery() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }

        let voltageMV = readNumber(service: service, key: "Voltage")
        // Prefer InstantAmperage for live current; fall back to averaged Amperage.
        let amperageMA = readNumber(service: service, key: "InstantAmperage")
            ?? readNumber(service: service, key: "Amperage")

        let newVoltage = voltageMV.map { Double($0) / 1000.0 }
        let newAmperage = amperageMA.map { Double($0) / 1000.0 }
        let newWattage: Double? = {
            guard let v = newVoltage, let a = newAmperage else { return nil }
            return v * a
        }()

        if voltage != newVoltage { voltage = newVoltage }
        if amperage != newAmperage { amperage = newAmperage }
        if wattage != newWattage { wattage = newWattage }

        let newCycles = readNumber(service: service, key: "CycleCount").map { Int($0) }
        let design = readNumber(service: service, key: "DesignCapacity").map { Int($0) }
        let maxCap = (readNumber(service: service, key: "AppleRawMaxCapacity")
            ?? readNumber(service: service, key: "MaxCapacity")
            ?? readNumber(service: service, key: "NominalChargeCapacity")).map { Int($0) }

        let newHealth: Int? = {
            guard let d = design, d > 0, let m = maxCap else { return nil }
            return Int(round(Double(m) / Double(d) * 100.0))
        }()

        if cycleCount != newCycles { cycleCount = newCycles }
        if healthPercent != newHealth { healthPercent = newHealth }

        if let c = newCycles {
            updateReplacementEstimate(currentCycles: c)
        }
    }

    private func updateReplacementEstimate(currentCycles: Int) {
        let defaults = UserDefaults.standard
        let baselineKey = "batteryBaselineCycles"
        let baselineDateKey = "batteryBaselineDate"

        let storedBaseline = defaults.object(forKey: baselineKey) as? Int
        let storedDate = defaults.object(forKey: baselineDateKey) as? Date

        guard let baseline = storedBaseline, let date = storedDate, currentCycles >= baseline else {
            // First run, or the battery was replaced (cycles went down). Reset baseline.
            defaults.set(currentCycles, forKey: baselineKey)
            defaults.set(Date(), forKey: baselineDateKey)
            estimatedReplacementDate = nil
            return
        }

        let elapsed = Date().timeIntervalSince(date)
        let cyclesUsed = currentCycles - baseline
        // Need at least a day of observation and at least 1 cycle to project meaningfully.
        guard elapsed >= 86_400, cyclesUsed >= 1 else {
            estimatedReplacementDate = nil
            return
        }
        let cyclesPerSecond = Double(cyclesUsed) / elapsed
        let remaining = Double(BatteryMonitor.maxCycles - currentCycles)
        guard remaining > 0, cyclesPerSecond > 0 else {
            estimatedReplacementDate = Date()
            return
        }
        let secondsLeft = remaining / cyclesPerSecond
        estimatedReplacementDate = Date().addingTimeInterval(secondsLeft)
    }

    private func readNumber(service: io_service_t, key: String) -> Int64? {
        guard let prop = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else {
            return nil
        }
        guard let num = prop as? NSNumber else { return nil }
        var value = num.int64Value
        // Some macOS versions report Amperage as an unsigned 16- or 32-bit
        // value that's actually a two's-complement negative when discharging.
        // Sane mA values are well under 100,000 in magnitude, so re-interpret
        // implausibly large positives as signed-overflow.
        if key.contains("Amperage") {
            if value > 0x7FFFFFFF { value -= 0x100000000 }
            else if value > 0x7FFF && value <= 0xFFFF { value -= 0x10000 }
        }
        return value
    }
}
