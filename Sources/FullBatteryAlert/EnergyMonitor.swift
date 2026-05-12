import Foundation
import AppKit
import Combine

struct AppEnergy: Identifiable {
    let id: pid_t
    let displayName: String
    let bundleIdentifier: String?
    let icon: NSImage?
    let powerImpact: Double
    let pids: [pid_t]
}

enum EnergyParser {
    struct RawProcess {
        let pid: pid_t
        let command: String
        let powerImpact: Double
    }

    static func parse(_ output: String) -> [RawProcess] {
        var rows: [RawProcess] = []
        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // `top -l 2` prints two samples back-to-back. Each sample has its
            // own "PID ... POWER" column header. Only the second sample has
            // meaningful POWER values, so reset on every header to keep only
            // the most recent batch.
            if trimmed.hasPrefix("PID") && trimmed.contains("POWER") {
                rows.removeAll(keepingCapacity: true)
                continue
            }
            if trimmed.isEmpty { continue }
            let parts = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard parts.count >= 3,
                  let pid = pid_t(parts[0]),
                  let power = Double(parts[parts.count - 1])
            else { continue }
            let command = parts[1..<(parts.count - 1)].joined(separator: " ")
            rows.append(RawProcess(pid: pid, command: command, powerImpact: power))
        }
        return rows
    }
}

@MainActor
final class EnergyMonitor: ObservableObject {
    @Published private(set) var topApps: [AppEnergy] = []

    private let significanceThreshold: Double = 1.0
    private let maxRows: Int = 5
    private let pollInterval: TimeInterval = 5.0

    private var timer: Timer?
    private var isRunning = false

    func start() {
        guard !isRunning else { return }
        isRunning = true
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    private func refresh() {
        // `top -l 2` blocks ~1s between samples, so run it off the main actor;
        // grouping uses NSRunningApplication which is main-actor, so hop back
        // to main once the subprocess returns and publish from there.
        Task.detached(priority: .utility) { [weak self] in
            let raw = Self.runTop()
            let parsed = EnergyParser.parse(raw)
            await self?.publish(parsed: parsed)
        }
    }

    private func publish(parsed: [EnergyParser.RawProcess]) {
        let grouped = Self.group(parsed)
        let filtered = grouped
            .filter { $0.powerImpact > significanceThreshold }
            .sorted { $0.powerImpact > $1.powerImpact }
            .prefix(maxRows)
        topApps = Array(filtered)
    }

    nonisolated private static func runTop() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/top")
        // -l 2 takes two samples ~1s apart. POWER is "energy impact since the
        // previous sample", so the first sample reports 0.0 for everything;
        // only the second sample has real numbers. Without two samples the
        // entire list comes back empty after threshold filtering.
        process.arguments = ["-l", "2", "-stats", "pid,command,power", "-o", "power", "-n", "20"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func group(_ raw: [EnergyParser.RawProcess]) -> [AppEnergy] {
        var byKey: [String: AppEnergy] = [:]
        for row in raw {
            let runningApp = NSRunningApplication(processIdentifier: row.pid)
            let key = runningApp?.bundleIdentifier ?? row.command
            if let existing = byKey[key] {
                byKey[key] = AppEnergy(
                    id: existing.powerImpact >= row.powerImpact ? existing.id : row.pid,
                    displayName: existing.displayName,
                    bundleIdentifier: existing.bundleIdentifier,
                    icon: existing.icon,
                    powerImpact: existing.powerImpact + row.powerImpact,
                    pids: existing.pids + [row.pid]
                )
            } else {
                byKey[key] = AppEnergy(
                    id: row.pid,
                    displayName: runningApp?.localizedName ?? row.command,
                    bundleIdentifier: runningApp?.bundleIdentifier,
                    icon: runningApp?.icon,
                    powerImpact: row.powerImpact,
                    pids: [row.pid]
                )
            }
        }
        return Array(byKey.values)
    }
}
