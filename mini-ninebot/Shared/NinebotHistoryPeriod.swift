import Foundation

/// How long a vehicle-history series spans, bucketed to the unit it should be
/// read in.
///
/// The bucket boundaries are the interesting part, and they are measured
/// against the number that will be *printed*, not the raw value: 24 displayed
/// hours is a day and 60 displayed minutes is an hour, so a span never reads
/// "60 分钟" or "24 小时".
enum NinebotHistoryPeriod: Equatable {
    /// First and last sample share a timestamp — there is no span yet.
    case justStarted
    case days(Double)
    case hours(Double)
    case minutes(Double)

    /// Once the hour figure prints as this, the span reads in days instead.
    static let dayBoundaryHours = 24.0
    /// Once the minute figure prints as this, the span reads in hours instead.
    static let hourBoundaryMinutes = 60.0

    /// Fraction digits each unit is displayed with. The bucket has to be
    /// decided at the same precision the number is printed at.
    static let hoursFractionDigits = 1
    static let minutesFractionDigits = 0

    /// - Parameter seconds: elapsed time between the first and last sample.
    init(seconds: TimeInterval) {
        guard seconds > 0 else {
            self = .justStarted
            return
        }
        let hours = seconds / 3600
        let minutes = seconds / 60
        if displayRounded(hours, maximumFractionDigits: Self.hoursFractionDigits)
            >= Self.dayBoundaryHours {
            self = .days(hours / 24)
        } else if displayRounded(minutes, maximumFractionDigits: Self.minutesFractionDigits)
            >= Self.hourBoundaryMinutes {
            self = .hours(hours)
        } else {
            self = .minutes(minutes)
        }
    }
}

extension NinebotVehicleHistorySummary {
    var period: NinebotHistoryPeriod {
        NinebotHistoryPeriod(seconds: latest.date.timeIntervalSince(first.date))
    }
}
