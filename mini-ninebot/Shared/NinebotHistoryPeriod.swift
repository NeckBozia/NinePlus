import Foundation

/// How long a vehicle-history series spans, bucketed to the unit it should be
/// read in.
///
/// The bucket boundaries are the interesting part: a span is reported in days
/// only once it reaches a full day, and in hours only once it reaches a full
/// hour. Below that it reads in whole minutes.
enum NinebotHistoryPeriod: Equatable {
    /// First and last sample share a timestamp — there is no span yet.
    case justStarted
    case days(Double)
    case hours(Double)
    case minutes(Double)

    /// At or above this many hours the span reads in days.
    static let dayBoundaryHours = 24.0
    /// At or above this many hours the span reads in hours rather than minutes.
    static let hourBoundaryHours = 1.0

    /// - Parameter seconds: elapsed time between the first and last sample.
    init(seconds: TimeInterval) {
        guard seconds > 0 else {
            self = .justStarted
            return
        }
        let hours = seconds / 3600
        if hours >= Self.dayBoundaryHours {
            self = .days(hours / 24)
        } else if hours >= Self.hourBoundaryHours {
            self = .hours(hours)
        } else {
            self = .minutes(seconds / 60)
        }
    }
}

extension NinebotVehicleHistorySummary {
    var period: NinebotHistoryPeriod {
        NinebotHistoryPeriod(seconds: latest.date.timeIntervalSince(first.date))
    }
}
