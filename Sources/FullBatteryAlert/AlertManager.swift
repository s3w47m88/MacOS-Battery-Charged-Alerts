import Foundation

final class AlertManager {
    static let shared = AlertManager()

    private var firedThresholds: Set<Int> = []
    private init() {}

    func handleUpdate(percentage: Int, isCharging: Bool, isPluggedIn: Bool,
                      settings: AppSettings,
                      onFire: (Int) -> Void) {
        // Reset when unplugged or below the lowest threshold
        if !isPluggedIn || percentage < (settings.thresholds.min() ?? 0) {
            firedThresholds.removeAll()
            return
        }
        for threshold in settings.thresholds.sorted() {
            if percentage >= threshold && !firedThresholds.contains(threshold) {
                firedThresholds.insert(threshold)
                onFire(threshold)
            }
        }
    }
}
