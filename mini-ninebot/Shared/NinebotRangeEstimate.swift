import Foundation

/// Where the range figure came from and how much to trust it.
///
/// The community server adapter does not return predictions at all, so
/// `.missing` is the default case in practice — the interface has to present it
/// as normal, not as a failure.
enum NinebotRangeEstimateQuality: Equatable {
    /// Server returned a prediction but says it fell back to its default
    /// algorithm because it lacked samples.
    case serverDefault
    /// Server algorithm, accuracy at or above the confidence threshold.
    case serverConfident(accuracy: Double)
    /// Server algorithm, still calibrating.
    case serverCalibrating
    /// Server responded but gave no usable algorithmic range.
    case serverUnavailable
    /// Server returned no prediction at all.
    case missing
}

/// Where the accuracy percentage itself came from.
enum NinebotRangeAccuracyDetail: Equatable {
    /// Measured against rides that have since completed.
    case measured(verifiedCount: Int)
    /// The server's own algorithmic figure.
    case algorithmic(sampleCount: Int)
    /// Prediction present but no samples behind it.
    case insufficientSamples
    /// No prediction at all.
    case noPrediction
}

/// What the displayed range estimate is actually based on.
enum NinebotLocalEstimateBasis: Equatable {
    /// Server blends the official estimate with observed rides.
    case personalized(sampleCount: Int?)
    /// Server's default algorithm.
    case serverDefault(sampleCount: Int?)
    /// No usable server prediction; showing the vehicle's own figure.
    case missing
}

extension NinebotVehicleState {

    /// Accuracy at or above this reads as trustworthy rather than calibrating.
    static let rangeConfidenceThreshold = 0.82

    // Server contract values. Naming them keeps the comparisons out of the
    // middle of display logic.
    static let accuracySourceMeasured = "measured"
    static let rangeSourceDefault = "default"
    static let rangeSourcePersonalized = "personalized"
    static let rangeSourcePersonalizedBlend = "personalized_blend"

    var rangeEstimateQuality: NinebotRangeEstimateQuality {
        guard usesServerAlgorithmEstimate else {
            return serverPrediction == nil ? .missing : .serverUnavailable
        }
        if serverPrediction?.range.source == Self.rangeSourceDefault {
            return .serverDefault
        }
        if let accuracy = rangeEstimateAccuracy, accuracy >= Self.rangeConfidenceThreshold {
            return .serverConfident(accuracy: accuracy)
        }
        return .serverCalibrating
    }

    var rangeAccuracyDetail: NinebotRangeAccuracyDetail {
        guard let range = serverPrediction?.range else { return .noPrediction }
        guard let sampleCount = range.sampleCount, sampleCount > 0 else {
            return .insufficientSamples
        }
        if range.accuracySource == Self.accuracySourceMeasured {
            return .measured(verifiedCount: range.measuredSampleCount ?? sampleCount)
        }
        return .algorithmic(sampleCount: sampleCount)
    }

    var localEstimateBasis: NinebotLocalEstimateBasis {
        guard let range = serverPrediction?.range,
              let estimatedRange = range.estimatedRange,
              estimatedRange >= 0 else {
            return .missing
        }
        switch range.source ?? "" {
        case Self.rangeSourcePersonalized, Self.rangeSourcePersonalizedBlend:
            return .personalized(sampleCount: range.sampleCount)
        default:
            return .serverDefault(sampleCount: range.sampleCount)
        }
    }

    /// Whether the server supplied a usable algorithmic range.
    var usesServerAlgorithmEstimate: Bool {
        guard let estimatedRange = serverPrediction?.range.estimatedRange,
              estimatedRange >= 0 else {
            return false
        }
        return true
    }
}
