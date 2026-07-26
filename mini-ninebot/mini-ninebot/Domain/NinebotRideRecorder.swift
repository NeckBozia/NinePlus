import Combine
import CoreLocation
import CoreMotion
import Foundation
import UIKit

/// GPS fix quality as the recorder sees it.  Presentation (title, icon, tint)
/// lives with the view, not here.
enum RecordingGPSQuality: Equatable {
    case waiting
    case stabilizing
    case good
    case weak
    case unavailable
}

@MainActor
final class NinebotRideRecorder: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var isRecording = false
    @Published private(set) var currentSpeedKmh: Double = 0
    @Published private(set) var currentAccelerationG: Double = 0
    @Published private(set) var maxSpeedKmh: Double = 0
    @Published private(set) var maxAccelerationG: Double = 0
    @Published private(set) var gpsQuality: RecordingGPSQuality = .waiting
    @Published private(set) var distanceMeters: Double = 0
    @Published private(set) var points: [NinebotRideTrackPoint] = []
    @Published private(set) var currentLocationPoint: NinebotRideTrackPoint?
    @Published private(set) var startedAt: Date?
    @Published private(set) var endedAt: Date?
    @Published private(set) var lastErrorText: String?

    private let manager = CLLocationManager()
    private let motionManager = CMMotionManager()
    private var vehicleSN: String?
    private var lastLocation: CLLocation?
    private var lastSpeedMPS: Double?
    private var lastAcceptedLocationAt: Date?
    private var smoothedSpeedMPS: Double?
    private var speedSamples: [Double] = []
    private var lastMotionTimestamp: TimeInterval?
    private var smoothedMotionG: Double?
    private var ignoreLocationUntil: Date?
    private var ignoreMotionUntil: Date?
    private var appActiveObserver: NSObjectProtocol?
    private var isBackgroundLocationEnabled = false

    private let maximumReasonableSpeedKmh = 132.0
    private let maximumReasonableGPSAccelerationG = 0.75
    private let maximumReasonableMotionG = 1.35
    private let maximumReasonableSegmentDistance = 160.0
    private let maximumLocationAge: TimeInterval = 6
    private let minimumLocationDeltaTime: TimeInterval = 0.45
    private let maximumLocationDeltaTimeForSpeed: TimeInterval = 6
    private let maximumLocationGapBeforeCooldown: TimeInterval = 8
    private let recoveryCooldownDuration: TimeInterval = 2.2
    private let goodHorizontalAccuracy = 35.0
    private let maximumHorizontalAccuracy = 60.0
    private let maximumDisplayedAccelerationMPS2 = 4.5
    private let maximumDisplayedDecelerationMPS2 = 7.0
    private let maximumMotionSampleGap: TimeInterval = 0.75
    private let motionCooldownDuration: TimeInterval = 1.1

    override init() {
        super.init()
        authorizationStatus = manager.authorizationStatus
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .automotiveNavigation
        manager.distanceFilter = 1
        manager.pausesLocationUpdatesAutomatically = false
        appActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // With background updates running the track never paused, so
                // there is nothing to stabilise.  If they were not running —
                // or the system suspended us anyway — the gap detection in
                // consume(_:) still catches it on the next fix.
                guard !self.isBackgroundLocationEnabled else { return }
                self.enterStabilizationCooldown()
            }
        }
    }

    deinit {
        if let appActiveObserver {
            NotificationCenter.default.removeObserver(appActiveObserver)
        }
    }

    var elapsedSeconds: TimeInterval {
        guard let startedAt else { return 0 }
        let endDate = isRecording ? Date() : (endedAt ?? startedAt)
        return max(endDate.timeIntervalSince(startedAt), 0)
    }

    var distanceKilometers: Double {
        distanceMeters / 1000
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse
    }

    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func startPreview() {
        guard CLLocationManager.locationServicesEnabled() else {
            lastErrorText = "系统定位服务未开启"
            gpsQuality = .unavailable
            return
        }

        if authorizationStatus == .notDetermined {
            requestAuthorization()
            return
        }

        guard isAuthorized else {
            lastErrorText = "需要定位权限才能显示实时位置"
            gpsQuality = .unavailable
            return
        }

        lastErrorText = nil
        if currentLocationPoint == nil {
            gpsQuality = .waiting
        }
        startMotionUpdates()
        manager.startUpdatingLocation()
        manager.requestLocation()
    }

    func stopPreviewIfIdle() {
        guard !isRecording else { return }
        manager.stopUpdatingLocation()
        stopMotionUpdates()
    }

    func start(vehicleSN: String?) {
        lastErrorText = nil
        guard CLLocationManager.locationServicesEnabled() else {
            lastErrorText = "系统定位服务未开启"
            gpsQuality = .unavailable
            return
        }

        if authorizationStatus == .notDetermined {
            requestAuthorization()
            lastErrorText = "请允许定位后再开始记录"
            return
        }

        guard isAuthorized else {
            lastErrorText = "需要定位权限才能记录轨迹"
            gpsQuality = .unavailable
            return
        }

        self.vehicleSN = vehicleSN
        isRecording = true
        currentSpeedKmh = 0
        currentAccelerationG = 0
        maxSpeedKmh = 0
        maxAccelerationG = 0
        distanceMeters = 0
        points = []
        speedSamples = []
        lastLocation = nil
        lastSpeedMPS = nil
        smoothedSpeedMPS = nil
        lastAcceptedLocationAt = nil
        lastMotionTimestamp = nil
        smoothedMotionG = nil
        gpsQuality = .stabilizing
        ignoreLocationUntil = Date().addingTimeInterval(recoveryCooldownDuration)
        ignoreMotionUntil = Date().addingTimeInterval(motionCooldownDuration)
        startedAt = Date()
        endedAt = nil
        setBackgroundLocationUpdates(enabled: true)
        startMotionUpdates()
        manager.startUpdatingLocation()
    }

    /// Keeps location flowing while the app is backgrounded or the screen is
    /// locked.  Only enabled for the duration of a recording — leaving it on
    /// would keep the blue status bar indicator up and drain the battery while
    /// the user is merely previewing.
    private func setBackgroundLocationUpdates(enabled: Bool) {
        guard isBackgroundLocationEnabled != enabled else { return }
        // Requires the `location` entry in UIBackgroundModes; without it this
        // assignment traps.
        manager.allowsBackgroundLocationUpdates = enabled
        manager.showsBackgroundLocationIndicator = enabled
        isBackgroundLocationEnabled = enabled
    }

    func stop() -> NinebotRecordedRide? {
        guard isRecording, let startedAt else { return nil }
        let endedAt = Date()
        isRecording = false
        self.endedAt = endedAt
        setBackgroundLocationUpdates(enabled: false)

        let correctedDistanceMeters = NinebotRecordedRide.recalculatedDistanceMeters(from: points)
        let finalDistanceMeters = correctedDistanceMeters > 0 ? correctedDistanceMeters : distanceMeters
        let durationHours = max(endedAt.timeIntervalSince(startedAt) / 3600, 0)
        let averageSpeed: Double
        if durationHours > 0 {
            averageSpeed = (finalDistanceMeters / 1000) / durationHours
        } else if !speedSamples.isEmpty {
            averageSpeed = speedSamples.reduce(0, +) / Double(speedSamples.count)
        } else {
            averageSpeed = 0
        }

        return NinebotRecordedRide(
            vehicleSN: vehicleSN,
            startedAt: startedAt,
            endedAt: endedAt,
            distanceMeters: finalDistanceMeters,
            maxSpeedKmh: maxSpeedKmh,
            averageSpeedKmh: averageSpeed,
            maxAccelerationG: maxAccelerationG,
            points: points
        )
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            if isAuthorized {
                startPreview()
            } else {
                gpsQuality = .unavailable
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            lastErrorText = error.localizedDescription
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            handleLocations(locations)
        }
    }

    private func handleLocations(_ locations: [CLLocation]) {
        for location in locations where isUsable(location) {
            consume(location)
        }
    }

    private func startMotionUpdates() {
        guard motionManager.isDeviceMotionAvailable, !motionManager.isDeviceMotionActive else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 20.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            Task { @MainActor in
                self?.consumeMotion(motion)
            }
        }
    }

    private func stopMotionUpdates() {
        motionManager.stopDeviceMotionUpdates()
    }

    private func consumeMotion(_ motion: CMDeviceMotion) {
        if let ignoreMotionUntil, Date() < ignoreMotionUntil {
            currentAccelerationG = 0
            return
        }

        if let lastMotionTimestamp {
            let deltaTime = motion.timestamp - lastMotionTimestamp
            if deltaTime <= 0 || deltaTime > maximumMotionSampleGap {
                self.lastMotionTimestamp = motion.timestamp
                smoothedMotionG = nil
                currentAccelerationG = 0
                ignoreMotionUntil = Date().addingTimeInterval(motionCooldownDuration)
                return
            }
        }

        if let lastMotionTimestamp, motion.timestamp < lastMotionTimestamp {
            currentAccelerationG = 0
            return
        }
        lastMotionTimestamp = motion.timestamp

        let acceleration = motion.userAcceleration
        let g = sqrt(
            acceleration.x * acceleration.x +
            acceleration.y * acceleration.y +
            acceleration.z * acceleration.z
        )
        guard g.isFinite, g <= maximumReasonableMotionG else {
            currentAccelerationG = 0
            return
        }

        let normalizedG = g < 0.025 ? 0 : g
        let previousG = smoothedMotionG ?? 0
        let filteredG = previousG + (normalizedG - previousG) * 0.18
        let maxStep = 0.08
        let rateLimitedG = min(max(filteredG, previousG - maxStep), previousG + maxStep)
        smoothedMotionG = min(max(rateLimitedG, 0), maximumReasonableMotionG)

        currentAccelerationG = smoothedMotionG ?? 0
        if isRecording {
            maxAccelerationG = max(maxAccelerationG, currentAccelerationG)
        }
    }

    private func consume(_ location: CLLocation) {
        if let lastLocation, location.timestamp <= lastLocation.timestamp {
            return
        }

        updateGPSQuality(for: location)

        if let ignoreLocationUntil, Date() < ignoreLocationUntil {
            acceptBaselineLocation(location, gpsQuality: .stabilizing)
            return
        }

        let previousLocation = lastLocation
        guard let previousLocation else {
            acceptBaselineLocation(location, gpsQuality: location.horizontalAccuracy <= goodHorizontalAccuracy ? .good : .weak)
            return
        }

        let deltaTime = location.timestamp.timeIntervalSince(previousLocation.timestamp)
        if shouldTreatAsRecoveredLocation(location, deltaTime: deltaTime) {
            enterStabilizationCooldown()
            acceptBaselineLocation(location, gpsQuality: .stabilizing)
            return
        }

        let segmentDistance = location.distance(from: previousLocation)
        guard deltaTime >= minimumLocationDeltaTime else {
            lastLocation = location
            currentLocationPoint = trackPoint(for: location, speedKmh: currentSpeedKmh, accelerationG: currentAccelerationG)
            return
        }

        guard let rawSpeedMPS = speedCandidate(
            from: location,
            previousLocation: previousLocation,
            deltaTime: deltaTime,
            segmentDistance: segmentDistance
        ) else {
            acceptBaselineLocation(location, gpsQuality: .stabilizing)
            return
        }

        let rawSpeedKmh = rawSpeedMPS * 3.6
        guard rawSpeedKmh.isFinite, rawSpeedKmh <= maximumReasonableSpeedKmh else {
            rejectSpeedSample(from: location)
            return
        }

        let previousSmoothedSpeed = smoothedSpeedMPS ?? lastSpeedMPS
        let displaySpeedMPS = smoothedSpeed(rawSpeedMPS, deltaTime: deltaTime)
        let displaySpeedKmh = displaySpeedMPS * 3.6

        currentSpeedKmh = displaySpeedKmh
        if !motionManager.isDeviceMotionActive {
            let gpsAccelerationG = previousSmoothedSpeed.map {
                max((displaySpeedMPS - $0) / max(deltaTime, minimumLocationDeltaTime) / 9.80665, 0)
            } ?? 0
            currentAccelerationG = gpsAccelerationG.isFinite && gpsAccelerationG <= maximumReasonableGPSAccelerationG ? gpsAccelerationG : 0
        }

        let point = trackPoint(for: location, speedKmh: displaySpeedKmh, accelerationG: currentAccelerationG)
        currentLocationPoint = point

        if isRecording {
            maxSpeedKmh = max(maxSpeedKmh, displaySpeedKmh)
            if !motionManager.isDeviceMotionActive {
                maxAccelerationG = max(maxAccelerationG, currentAccelerationG)
            }
            speedSamples.append(displaySpeedKmh)

            if isReliableRecordingSegment(
                location: location,
                previousLocation: previousLocation,
                deltaTime: deltaTime,
                segmentDistance: segmentDistance,
                speedMPS: displaySpeedMPS
            ) {
                distanceMeters += segmentDistance
                points.append(point)
            } else if points.isEmpty {
                points.append(point)
            }
        }

        lastLocation = location
        lastSpeedMPS = displaySpeedMPS
        lastAcceptedLocationAt = location.timestamp
    }

    private func rejectSpeedSample(from location: CLLocation) {
        let point = trackPoint(for: location, speedKmh: 0, accelerationG: 0)
        currentLocationPoint = point
        currentSpeedKmh = 0
        if !motionManager.isDeviceMotionActive {
            currentAccelerationG = 0
        }
        lastLocation = location
        lastSpeedMPS = nil
        smoothedSpeedMPS = nil
        lastAcceptedLocationAt = location.timestamp
        gpsQuality = .stabilizing
        ignoreLocationUntil = Date().addingTimeInterval(recoveryCooldownDuration)
    }

    private func shouldTreatAsRecoveredLocation(_ location: CLLocation, deltaTime: TimeInterval) -> Bool {
        if let lastAcceptedLocationAt {
            let acceptedGap = location.timestamp.timeIntervalSince(lastAcceptedLocationAt)
            if acceptedGap > maximumLocationGapBeforeCooldown {
                return true
            }
        }

        return deltaTime > maximumLocationGapBeforeCooldown
    }

    private func enterStabilizationCooldown() {
        ignoreLocationUntil = Date().addingTimeInterval(recoveryCooldownDuration)
        ignoreMotionUntil = Date().addingTimeInterval(motionCooldownDuration)
        lastSpeedMPS = nil
        smoothedSpeedMPS = nil
        smoothedMotionG = nil
        currentSpeedKmh = 0
        currentAccelerationG = 0
        gpsQuality = .stabilizing
    }

    private func acceptBaselineLocation(_ location: CLLocation, gpsQuality quality: RecordingGPSQuality) {
        let point = trackPoint(for: location, speedKmh: 0, accelerationG: motionManager.isDeviceMotionActive ? currentAccelerationG : 0)
        currentLocationPoint = point
        currentSpeedKmh = 0
        if !motionManager.isDeviceMotionActive {
            currentAccelerationG = 0
        }
        lastLocation = location
        lastSpeedMPS = nil
        smoothedSpeedMPS = nil
        lastAcceptedLocationAt = location.timestamp
        gpsQuality = quality

        if isRecording, points.isEmpty, location.horizontalAccuracy <= maximumHorizontalAccuracy {
            points.append(point)
        }
    }

    private func updateGPSQuality(for location: CLLocation) {
        gpsQuality = location.horizontalAccuracy <= goodHorizontalAccuracy ? .good : .weak
    }

    private func speedCandidate(
        from location: CLLocation,
        previousLocation: CLLocation,
        deltaTime: TimeInterval,
        segmentDistance: Double
    ) -> Double? {
        if location.speed >= 0,
           location.speedAccuracy >= 0,
           location.speedAccuracy <= 6,
           location.horizontalAccuracy <= maximumHorizontalAccuracy,
           location.speed * 3.6 <= maximumReasonableSpeedKmh {
            return max(location.speed, 0)
        }

        guard deltaTime >= minimumLocationDeltaTime,
              deltaTime <= maximumLocationDeltaTimeForSpeed,
              segmentDistance >= 0,
              segmentDistance <= maximumReasonableSegmentDistance,
              location.horizontalAccuracy <= maximumHorizontalAccuracy,
              previousLocation.horizontalAccuracy <= maximumHorizontalAccuracy else {
            return nil
        }

        let impliedSpeedMPS = segmentDistance / deltaTime
        guard impliedSpeedMPS.isFinite,
              impliedSpeedMPS * 3.6 <= maximumReasonableSpeedKmh else {
            return nil
        }
        return max(impliedSpeedMPS, 0)
    }

    private func smoothedSpeed(_ rawSpeedMPS: Double, deltaTime: TimeInterval) -> Double {
        guard let previous = smoothedSpeedMPS else {
            smoothedSpeedMPS = rawSpeedMPS
            return rawSpeedMPS
        }

        let safeDeltaTime = max(deltaTime, minimumLocationDeltaTime)
        let maxDelta = (rawSpeedMPS >= previous ? maximumDisplayedAccelerationMPS2 : maximumDisplayedDecelerationMPS2) * safeDeltaTime
        let limitedSpeed = min(max(rawSpeedMPS, previous - maxDelta), previous + maxDelta)
        let alpha = limitedSpeed >= previous ? 0.34 : 0.48
        let smoothed = previous + (limitedSpeed - previous) * alpha
        smoothedSpeedMPS = max(smoothed, 0)
        return smoothedSpeedMPS ?? 0
    }

    private func isReliableRecordingSegment(
        location: CLLocation,
        previousLocation: CLLocation,
        deltaTime: TimeInterval,
        segmentDistance: Double,
        speedMPS: Double
    ) -> Bool {
        deltaTime >= minimumLocationDeltaTime
            && deltaTime <= maximumLocationDeltaTimeForSpeed
            && segmentDistance >= 0
            && segmentDistance <= maximumReasonableSegmentDistance
            && speedMPS >= 0
            && speedMPS * 3.6 <= maximumReasonableSpeedKmh
            && location.horizontalAccuracy <= maximumHorizontalAccuracy
            && previousLocation.horizontalAccuracy <= maximumHorizontalAccuracy
    }

    private func trackPoint(for location: CLLocation, speedKmh: Double, accelerationG: Double) -> NinebotRideTrackPoint {
        NinebotRideTrackPoint(
            date: location.timestamp,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            speedKmh: speedKmh,
            accelerationG: accelerationG,
            horizontalAccuracy: location.horizontalAccuracy
        )
    }

    private func isUsable(_ location: CLLocation) -> Bool {
        let age = abs(location.timestamp.timeIntervalSinceNow)
        return location.horizontalAccuracy >= 0
            && location.horizontalAccuracy <= maximumHorizontalAccuracy
            && age <= maximumLocationAge
            && (-90...90).contains(location.coordinate.latitude)
            && (-180...180).contains(location.coordinate.longitude)
    }
}
