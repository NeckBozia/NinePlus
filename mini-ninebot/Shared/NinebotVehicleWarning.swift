import Foundation

/// A condition worth telling the rider about on the dashboard.
///
/// These used to exist only as Chinese strings, and the list was rendered with
/// `ForEach(warnings, id: \.self)` — the wording itself was the list identity,
/// so two warnings phrased alike would have collided. The cases carry ASCII
/// raw values so identity survives any rewording.
enum NinebotVehicleWarning: String, CaseIterable, Identifiable {
    /// Battery below `lowBatteryPercent`.
    case batteryVeryLow = "battery_very_low"
    /// Battery below `guardedBatteryPercent` but not yet very low.
    case batteryLow = "battery_low"
    case poweredOff = "powered_off"
    case unlocked = "unlocked"

    var id: String { rawValue }
}

extension NinebotVehicleState {

    /// At or below this the warning escalates from "偏低" to "尽快充电".
    static let lowBatteryPercent = 15
    /// Below this is worth a softer heads-up.
    static let guardedBatteryPercent = 25

    var warnings: [NinebotVehicleWarning] {
        var warnings: [NinebotVehicleWarning] = []
        if let battery, battery < Self.lowBatteryPercent {
            warnings.append(.batteryVeryLow)
        } else if let battery, battery < Self.guardedBatteryPercent {
            warnings.append(.batteryLow)
        }
        if isPoweredOn == false {
            warnings.append(.poweredOff)
        }
        if isLocked == false {
            warnings.append(.unlocked)
        }
        return warnings
    }
}
