import Foundation

/// Combined power and charging state.
///
/// The ordering is deliberate and load-bearing: fully charged beats charging,
/// and charging beats the power flag. A vehicle at 100% while being ridden
/// reports `.fullyCharged`, not `.poweredOn`. That is the existing iOS
/// behaviour, and both platforms have to agree on it.
enum NinebotPowerStatus: Equatable {
    case fullyCharged
    case charging
    /// `isPoweredOn` is absent. Note this means *the field is missing*, not
    /// that the network is down.
    case offline
    case poweredOn
    case poweredOff
}

/// Whether the vehicle is charging, ignoring the power flag entirely.
enum NinebotChargingState: Equatable {
    case fullyCharged
    case charging
    case notCharging
    /// `isCharging` is absent.
    case unknown
}

/// Outcome of estimating how long charging has left.
enum NinebotChargeEstimate: Equatable {
    /// Not charging, so there is nothing to estimate.
    case notCharging
    /// Charging, but no minute figure is available yet.
    case calculating
    /// Already at or past the target — full, or past 80%.
    case reached
    case minutes(Double)

    var minuteValue: Double? {
        guard case .minutes(let value) = self else { return nil }
        return value
    }
}

/// Outcome of projecting a charge estimate onto a wall clock time.
enum NinebotChargeClock: Equatable {
    /// Not charging, or no minute figure to project.
    case unavailable
    /// Already at or past the target.
    case reached
    case at(Date)
}

extension NinebotVehicleState {

    var powerStatus: NinebotPowerStatus {
        if isFullyCharged { return .fullyCharged }
        if isCharging == true { return .charging }
        guard let isPoweredOn else { return .offline }
        return isPoweredOn ? .poweredOn : .poweredOff
    }

    var chargingState: NinebotChargingState {
        if isFullyCharged { return .fullyCharged }
        guard let isCharging else { return .unknown }
        return isCharging ? .charging : .notCharging
    }

    var fullChargeEstimate: NinebotChargeEstimate {
        Self.chargeEstimate(isCharging: isCharging, minutes: estimatedFullChargeMinutes)
    }

    var chargeTo80Estimate: NinebotChargeEstimate {
        Self.chargeEstimate(isCharging: isCharging, minutes: estimatedChargeTo80Minutes)
    }

    /// Projected time the battery reaches full.  Prefers the server's own
    /// timestamp when it supplied one, rather than adding minutes to
    /// `updatedAt`.
    var fullChargeClock: NinebotChargeClock {
        switch fullChargeEstimate {
        case .notCharging, .calculating:
            return .unavailable
        case .reached:
            return .reached
        case .minutes(let minutes):
            if let estimatedFullAt = serverPrediction?.charging.estimatedFullAt {
                return .at(estimatedFullAt)
            }
            return .at(updatedAt.addingTimeInterval(minutes * 60))
        }
    }

    /// Projected time the battery reaches 80%.  Always derived from
    /// `updatedAt`; the server does not supply an 80% timestamp.
    var chargeTo80Clock: NinebotChargeClock {
        switch chargeTo80Estimate {
        case .notCharging, .calculating:
            return .unavailable
        case .reached:
            return .reached
        case .minutes(let minutes):
            return .at(updatedAt.addingTimeInterval(minutes * 60))
        }
    }

    private static func chargeEstimate(isCharging: Bool?, minutes: Double?) -> NinebotChargeEstimate {
        guard isCharging == true else { return .notCharging }
        guard let minutes else { return .calculating }
        guard minutes > 0 else { return .reached }
        return .minutes(minutes)
    }
}
