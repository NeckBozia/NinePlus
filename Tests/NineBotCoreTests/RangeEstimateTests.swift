import XCTest
@testable import NineBotCore

/// The range prediction quality rules. These were three nested if-chains inside
/// string-producing properties, comparing against bare server contract strings
/// like "measured" and "personalized_blend".
final class RangeEstimateTests: XCTestCase {

    private func state(
        battery: Int? = 50,
        endurance: Double? = 40,
        estimatedRange: Double? = nil,
        source: String? = nil,
        accuracyPercent: Double? = nil,
        accuracySource: String? = nil,
        sampleCount: Int? = nil,
        measuredSampleCount: Int? = nil,
        hasPrediction: Bool = false
    ) -> NinebotVehicleState {
        let prediction: NinebotServerPrediction? = hasPrediction
            ? NinebotServerPrediction(
                range: NinebotServerRangePrediction(
                    estimatedRange: estimatedRange,
                    source: source,
                    sampleCount: sampleCount,
                    accuracyPercent: accuracyPercent,
                    accuracySource: accuracySource,
                    measuredSampleCount: measuredSampleCount
                ),
                charging: NinebotServerChargingPrediction()
            )
            : nil
        return NinebotVehicleState(
            battery: battery,
            endurance: endurance,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            serverPrediction: prediction
        )
    }

    // MARK: - Quality
    //
    // With the community server adapter there is no prediction at all, so
    // .missing is the normal case, not an error state.

    func testNoPredictionIsMissing() {
        XCTAssertEqual(state().rangeEstimateQuality, .missing)
        XCTAssertFalse(state().usesServerAlgorithmEstimate)
    }

    func testPredictionWithoutUsableRangeIsUnavailable() {
        // Prediction object present, but no estimatedRange.
        let s = state(estimatedRange: nil, hasPrediction: true)
        XCTAssertEqual(s.rangeEstimateQuality, .serverUnavailable)
        XCTAssertFalse(s.usesServerAlgorithmEstimate)
    }

    func testNegativeRangeCountsAsUnusable() {
        let s = state(estimatedRange: -1, hasPrediction: true)
        XCTAssertEqual(s.rangeEstimateQuality, .serverUnavailable)
    }

    func testZeroRangeIsStillUsable() {
        // The guard is >= 0, so a genuine zero counts.
        let s = state(estimatedRange: 0, hasPrediction: true)
        XCTAssertTrue(s.usesServerAlgorithmEstimate)
    }

    func testDefaultSourceWinsOverAccuracy() {
        // Even with high accuracy, source == "default" reports serverDefault.
        let s = state(estimatedRange: 40, source: "default", accuracyPercent: 95, hasPrediction: true)
        XCTAssertEqual(s.rangeEstimateQuality, .serverDefault)
    }

    func testConfidenceThresholdIsInclusive() {
        // 0.82 exactly qualifies as confident.
        let atThreshold = state(estimatedRange: 40, accuracyPercent: 82, hasPrediction: true)
        XCTAssertEqual(atThreshold.rangeEstimateQuality, .serverConfident(accuracy: 0.82))

        let below = state(estimatedRange: 40, accuracyPercent: 81.9, hasPrediction: true)
        XCTAssertEqual(below.rangeEstimateQuality, .serverCalibrating)
    }

    func testMissingAccuracyMeansCalibrating() {
        let s = state(estimatedRange: 40, hasPrediction: true)
        XCTAssertEqual(s.rangeEstimateQuality, .serverCalibrating)
    }

    func testInsightTextMatchesQuality() {
        XCTAssertEqual(state().rangeModelInsightText, "服务端未返回算法预测，当前显示官方预估。")
        XCTAssertEqual(
            state(estimatedRange: nil, hasPrediction: true).rangeModelInsightText,
            "服务端未给出可用算法续航，当前显示官方预估。"
        )
        XCTAssertEqual(
            state(estimatedRange: 40, source: "default", hasPrediction: true).rangeModelInsightText,
            "服务端样本不足，当前使用默认算法估算。"
        )
        XCTAssertEqual(
            state(estimatedRange: 40, accuracyPercent: 90, hasPrediction: true).rangeModelInsightText,
            "服务端近期样本稳定，估算可信。"
        )
        XCTAssertEqual(
            state(estimatedRange: 40, accuracyPercent: 50, hasPrediction: true).rangeModelInsightText,
            "服务端已根据近期行程持续校准。"
        )
    }

    // MARK: - Accuracy detail

    func testAccuracyDetailWithoutPrediction() {
        XCTAssertEqual(state().rangeAccuracyDetail, .noPrediction)
        XCTAssertEqual(state().rangeEstimateAccuracyDetailText, "服务端未返回算法指标")
    }

    func testAccuracyDetailWithZeroSamples() {
        let s = state(estimatedRange: 40, sampleCount: 0, hasPrediction: true)
        XCTAssertEqual(s.rangeAccuracyDetail, .insufficientSamples)
        XCTAssertEqual(s.rangeEstimateAccuracyDetailText, "服务端样本不足")
    }

    func testMeasuredSourcePrefersTheVerifiedCount() {
        let s = state(
            estimatedRange: 40, accuracySource: "measured",
            sampleCount: 20, measuredSampleCount: 7, hasPrediction: true
        )
        XCTAssertEqual(s.rangeAccuracyDetail, .measured(verifiedCount: 7))
        XCTAssertEqual(s.rangeEstimateAccuracyDetailText, "实测预测误差 · 7 次已验证行程")
    }

    /// When measuredSampleCount is absent it falls back to the overall count.
    func testMeasuredSourceFallsBackToTheSampleCount() {
        let s = state(estimatedRange: 40, accuracySource: "measured", sampleCount: 20, hasPrediction: true)
        XCTAssertEqual(s.rangeAccuracyDetail, .measured(verifiedCount: 20))
    }

    func testNonMeasuredSourceIsAlgorithmic() {
        let s = state(estimatedRange: 40, sampleCount: 12, hasPrediction: true)
        XCTAssertEqual(s.rangeAccuracyDetail, .algorithmic(sampleCount: 12))
        XCTAssertEqual(s.rangeEstimateAccuracyDetailText, "算法服务端 · 12 次有效行程")
    }

    // MARK: - Local estimate basis

    func testBasisIsMissingWithoutAUsableRange() {
        XCTAssertEqual(state().localEstimateBasis, .missing)
        XCTAssertEqual(state(estimatedRange: nil, hasPrediction: true).localEstimateBasis, .missing)
        XCTAssertEqual(state(estimatedRange: -5, hasPrediction: true).localEstimateBasis, .missing)
    }

    func testPersonalizedSources() {
        for source in ["personalized", "personalized_blend"] {
            let s = state(estimatedRange: 40, source: source, sampleCount: 9, hasPrediction: true)
            XCTAssertEqual(s.localEstimateBasis, .personalized(sampleCount: 9), source)
            XCTAssertEqual(
                s.localEstimateBasisText,
                "算法服务端结合官方预估和 9 次有效行程 持续校准。",
                source
            )
        }
    }

    func testUnknownSourceFallsBackToServerDefault() {
        let s = state(estimatedRange: 40, source: "something_new", sampleCount: 3, hasPrediction: true)
        XCTAssertEqual(s.localEstimateBasis, .serverDefault(sampleCount: 3))
        XCTAssertEqual(s.localEstimateBasisText, "服务端默认算法基于 3 次有效行程 计算。")
    }

    /// A missing sample count reads as "历史样本" rather than a number.
    func testAbsentSampleCountUsesGenericWording() {
        let s = state(estimatedRange: 40, source: "personalized", hasPrediction: true)
        XCTAssertEqual(s.localEstimateBasis, .personalized(sampleCount: nil))
        XCTAssertEqual(s.localEstimateBasisText, "算法服务端结合官方预估和 历史样本 持续校准。")
    }
}
