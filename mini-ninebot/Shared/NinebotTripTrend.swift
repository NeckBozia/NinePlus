import Foundation

/// A conclusion the trend analysis reached.  Wording lives with the view — this
/// type carries only which conclusions apply, so the rules and their thresholds
/// can be tested and shared across platforms.
enum NinebotTripInsight: String, Codable, CaseIterable, Identifiable {
    /// One ride is far longer than the daily average, so range estimates lean
    /// harder on recent samples.
    case longRideDominates
    /// Average electricity used per ride is high.
    case highAverageElectricity
    /// Energy per kilometre is high.
    case highEnergyPerKm
    /// Not enough verified range samples yet.
    case fewRangeSamples
    /// Local recordings exist that are not linked to an interface ride.
    case unlinkedLocalRides
    /// Nothing notable — emitted only when no other insight applies.
    case normal

    var id: String { rawValue }
}

/// Aggregates a month of rides into the figures the trend screen shows.
///
/// Derived from the `TripTrendAnalysis` that used to live inside
/// NinebotDashboardView. Numbers and rules live here; the `...Text` properties
/// that format them for display are a view-layer extension.
struct NinebotTripTrend {
    var snapshot: NinebotVehicleSnapshot
    var recordedRides: [NinebotRecordedRide]

    // MARK: - Rule thresholds
    //
    // These decide which insights fire.  They were inline literals inside the
    // view; naming them is the point of pulling this type out.

    /// A single ride longer than the daily average by this factor counts as a
    /// long ride.
    static let longRidePeakRatio = 1.8
    /// Average electricity per ride above this (Wh) counts as high.
    static let highAverageElectricityWh = 12.0
    /// Energy per kilometre above this (Wh/km) counts as high.
    static let highEnergyPerKmWh = 35.0
    /// Fewer verified range samples than this counts as not enough.
    static let sufficientRangeSampleCount = 5
    /// How many recent rides the ride list shows.
    static let recentRideDisplayCount = 8

    // MARK: - Source collections

    var dailyRecords: [NinebotDailyMileageRecord] {
        snapshot.state.dailyMileages.sorted {
            if let left = $0.date, let right = $1.date {
                return left < right
            }
            return $0.day < $1.day
        }
    }

    var rides: [NinebotRideRecord] {
        snapshot.state.rides
    }

    var recentRides: [NinebotRideRecord] {
        Array(rides.prefix(Self.recentRideDisplayCount))
    }

    var rideCount: Int {
        rides.count
    }

    var activeDayCount: Int {
        dailyRecords.count
    }

    // MARK: - Aggregates

    var monthMileage: Double? {
        if let monthMileage = snapshot.state.monthMileage {
            return monthMileage
        }
        guard !dailyRecords.isEmpty else { return nil }
        return dailyRecords.reduce(0) { $0 + $1.mileage }
    }

    var averageDailyMileage: Double? {
        guard let monthMileage, !dailyRecords.isEmpty else { return nil }
        return monthMileage / Double(dailyRecords.count)
    }

    var averageSpeed: Double? {
        let samples = rides.compactMap(\.speed).filter { $0 > 0 }
        guard !samples.isEmpty else { return nil }
        return samples.reduce(0, +) / Double(samples.count)
    }

    var averageUsedElectricity: Double? {
        let samples = rides.compactMap(\.usedElectricity).filter { $0 > 0 }
        guard !samples.isEmpty else { return nil }
        return samples.reduce(0, +) / Double(samples.count)
    }

    var peakRideMileage: Double? {
        rides.compactMap(\.mileage).max()
    }

    /// Prefers the month totals when available, otherwise averages per-ride
    /// energy over per-ride distance.
    var energyPerKm: Double? {
        if let monthMileage, monthMileage > 0,
           let energy = snapshot.state.monthUsedElectricity ?? snapshot.state.monthEnergy {
            return energy / monthMileage
        }

        let samples = rides.compactMap { ride -> Double? in
            guard let mileage = ride.mileage, mileage > 0,
                  let energy = ride.energy, energy > 0 else { return nil }
            return energy / mileage
        }
        guard !samples.isEmpty else { return nil }
        return samples.reduce(0, +) / Double(samples.count)
    }

    // MARK: - Rules

    /// Which conclusions apply, in display order.  Never empty: falls back to
    /// `.normal` when nothing else fires.
    var insights: [NinebotTripInsight] {
        var result: [NinebotTripInsight] = []

        if let peak = peakRideMileage,
           let averageDailyMileage,
           peak > averageDailyMileage * Self.longRidePeakRatio {
            result.append(.longRideDominates)
        }

        if let averageUsedElectricity, averageUsedElectricity > Self.highAverageElectricityWh {
            result.append(.highAverageElectricity)
        }

        if let energyPerKm, energyPerKm > Self.highEnergyPerKmWh {
            result.append(.highEnergyPerKm)
        }

        if snapshot.state.observedRangeSampleCount < Self.sufficientRangeSampleCount {
            result.append(.fewRangeSamples)
        }

        if recordedRides.contains(where: { $0.associatedRideID == nil }) {
            result.append(.unlinkedLocalRides)
        }

        if result.isEmpty {
            result.append(.normal)
        }

        return result
    }
}
