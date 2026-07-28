import Foundation

struct HandAssociationUpdate: Sendable {
    var hands: [TrackedHandSnapshot]
    var quality: TrackingQuality
    var ambiguous: Bool
    var degradationReason: TrackingDegradationReason?
}

struct HandAssociator: Sendable {
    private struct ObservationCandidate: Sendable {
        var observation: RawHandObservation
        var geometry: PalmGeometry
    }

    private struct TrackState: Sendable {
        var id: HandTrackID
        var lastObservationTimestamp: MonotonicTimestamp
        var rawLandmarks: HandLandmarks
        var filteredLandmarks: HandLandmarks
        var center: Point2D
        var palmWidth: Double
        var scaleSource: PalmScaleSource
        var confidence: Double
        var chirality: HandChirality
        var velocity: Point2D
        var missingDuration: TimeInterval
        var associationCertain: Bool
        var filters: LandmarkFilterBank

        func snapshot(at timestamp: MonotonicTimestamp) -> TrackedHandSnapshot {
            TrackedHandSnapshot(
                id: id,
                timestamp: timestamp,
                rawLandmarks: rawLandmarks,
                filteredLandmarks: filteredLandmarks,
                palmWidth: palmWidth,
                palmScaleSource: scaleSource,
                confidence: confidence,
                velocity: velocity,
                missingDuration: missingDuration,
                associationCertain: associationCertain
            )
        }
    }

    private struct Assignment {
        var observationByTrack: [Int?]
        var score: Double

        var matchCount: Int {
            observationByTrack.compactMap { $0 }.count
        }

        var signature: [Int] {
            observationByTrack.map { $0 ?? Int.max }
        }
    }

    private var tracks: [TrackState] = []
    private var nextID: UInt64 = 1
    private var tuning: GestureTuning

    init(tuning: GestureTuning) {
        self.tuning = tuning.validated()
        tracks.reserveCapacity(2)
    }

    mutating func update(tuning: GestureTuning) {
        self.tuning = tuning.validated()
        reset()
    }

    mutating func reset() {
        tracks.removeAll(keepingCapacity: true)
    }

    mutating func process(
        observations: [RawHandObservation],
        at timestamp: MonotonicTimestamp
    ) -> HandAssociationUpdate {
        var candidates: [ObservationCandidate] = []
        candidates.reserveCapacity(min(observations.count, 2))
        var candidateRejectionReasons: [TrackingDegradationReason] = []
        candidateRejectionReasons.reserveCapacity(observations.count)

        for observation in observations {
            guard observation.timestamp.rawValue.isFinite else {
                candidateRejectionReasons.append(.invalidTimestamp)
                continue
            }
            guard observation.observationConfidence.isFinite,
                  (0 ... 1).contains(observation.observationConfidence) else {
                candidateRejectionReasons.append(.visionFailure)
                continue
            }

            switch PalmGeometryEstimator.evaluate(
                landmarks: observation.landmarks,
                minimumConfidence: tuning.minimumLandmarkConfidence
            ) {
            case let .valid(geometry):
                candidates.append(ObservationCandidate(
                    observation: observation,
                    geometry: geometry
                ))
            case .palmAnchorsMissing:
                candidateRejectionReasons.append(.palmAnchorsMissing)
            case .invalidPalmScale:
                candidateRejectionReasons.append(.invalidPalmScale)
            }
        }

        candidates.sort(by: Self.observationOrder)
        let observations = Array(candidates.prefix(2))
        tracks.sort { $0.id < $1.id }
        pruneExpired(at: timestamp)

        let assignmentResult = chooseAssignment(observations: observations, at: timestamp)
        let ambiguity = assignmentAmbiguity(observations: observations, at: timestamp)
        let isAmbiguous = ambiguity.map { $0 < tuning.associationAmbiguityMargin } ?? false
        var matchedObservationIndices = Set<Int>()
        var matchedTrackIndices = Set<Int>()

        for trackIndex in tracks.indices {
            guard trackIndex < assignmentResult.observationByTrack.count,
                  let observationIndex = assignmentResult.observationByTrack[trackIndex],
                  observations.indices.contains(observationIndex) else {
                continue
            }
            update(
                trackAt: trackIndex,
                with: observations[observationIndex],
                at: timestamp,
                ambiguous: isAmbiguous
            )
            matchedTrackIndices.insert(trackIndex)
            matchedObservationIndices.insert(observationIndex)
        }

        for trackIndex in tracks.indices where !matchedTrackIndices.contains(trackIndex) {
            let missing = timestamp.duration(since: tracks[trackIndex].lastObservationTimestamp)
            tracks[trackIndex].missingDuration = max(0, missing.isFinite ? missing : 0)
            tracks[trackIndex].associationCertain = false
            tracks[trackIndex].velocity = TrackingMath.multiply(tracks[trackIndex].velocity, by: 0.5)
        }

        let unmatchedObservations = observations.indices.filter { !matchedObservationIndices.contains($0) }
        makeCapacityForNewTracks(count: unmatchedObservations.count, matchedTrackIndices: matchedTrackIndices)
        for observationIndex in unmatchedObservations where tracks.count < 2 {
            appendTrack(from: observations[observationIndex], at: timestamp)
        }

        pruneExpired(at: timestamp)
        tracks.sort { $0.id < $1.id }

        let hands = tracks.map { $0.snapshot(at: timestamp) }
        let tracking = trackingQuality(at: timestamp, ambiguous: isAmbiguous)
        let degradationReason = tracking.quality == .good
            ? nil
            : candidateRejectionReasons.first ?? tracking.reason
        return HandAssociationUpdate(
            hands: hands,
            quality: tracking.quality,
            ambiguous: isAmbiguous,
            degradationReason: degradationReason
        )
    }

    func currentSnapshot(at timestamp: MonotonicTimestamp) -> HandAssociationUpdate {
        let hands = tracks.map { track -> TrackedHandSnapshot in
            var snapshot = track.snapshot(at: timestamp)
            snapshot.associationCertain = false
            return snapshot
        }
        let quality: TrackingQuality = hands.isEmpty ? .absent : .degraded
        return HandAssociationUpdate(
            hands: hands,
            quality: quality,
            ambiguous: false,
            degradationReason: hands.isEmpty ? .noHandDetected : .handIdentityLost
        )
    }

    private mutating func update(
        trackAt index: Int,
        with candidate: ObservationCandidate,
        at timestamp: MonotonicTimestamp,
        ambiguous: Bool
    ) {
        var track = tracks[index]
        let dt = timestamp.duration(since: track.lastObservationTimestamp)
        let scaleChange = abs(candidate.geometry.width - track.palmWidth) / max(track.palmWidth, TrackingMath.epsilon)
        let sourceChanged = candidate.geometry.scaleSource != track.scaleSource
        let gapReset = !dt.isFinite || dt <= 0 || dt > tuning.filterResetGap
        let forceReset = gapReset || sourceChanged || scaleChange > tuning.normalizedDiscontinuityStep

        var filters = track.filters
        let filterResult = filters.filter(
            candidate.observation.landmarks,
            at: timestamp,
            palmWidth: candidate.geometry.width,
            tuning: tuning,
            forceReset: forceReset
        )
        let filteredGeometry = PalmGeometryEstimator.estimate(
            landmarks: filterResult.landmarks,
            minimumConfidence: tuning.minimumLandmarkConfidence
        ) ?? candidate.geometry

        var velocity = Point2D(x: 0, y: 0)
        if dt.isFinite, dt > 0, !forceReset {
            let measured = TrackingMath.divide(
                TrackingMath.subtract(filteredGeometry.center, track.center),
                by: dt
            )
            velocity = TrackingMath.blend(track.velocity, measured, newWeight: 0.30)
        }

        track.lastObservationTimestamp = timestamp
        track.rawLandmarks = candidate.observation.landmarks
        track.filteredLandmarks = filterResult.landmarks
        track.center = filteredGeometry.center
        track.palmWidth = filteredGeometry.width
        track.scaleSource = filteredGeometry.scaleSource
        track.confidence = min(candidate.observation.observationConfidence, candidate.geometry.anchorConfidence)
        track.chirality = candidate.observation.chirality
        track.velocity = velocity
        track.missingDuration = 0
        // A matched palm remains the same identity even when one or more
        // landmark filters re-anchor. Gesture consumers clutch/re-anchor their
        // own control joints; filter warm-up is not assignment ambiguity.
        track.associationCertain = !ambiguous
        track.filters = filters
        tracks[index] = track
    }

    private mutating func appendTrack(from candidate: ObservationCandidate, at timestamp: MonotonicTimestamp) {
        var filters = LandmarkFilterBank()
        let filterResult = filters.filter(
            candidate.observation.landmarks,
            at: timestamp,
            palmWidth: candidate.geometry.width,
            tuning: tuning,
            forceReset: true
        )
        let filteredGeometry = PalmGeometryEstimator.estimate(
            landmarks: filterResult.landmarks,
            minimumConfidence: tuning.minimumLandmarkConfidence
        ) ?? candidate.geometry

        let track = TrackState(
            id: HandTrackID(rawValue: nextID),
            lastObservationTimestamp: timestamp,
            rawLandmarks: candidate.observation.landmarks,
            filteredLandmarks: filterResult.landmarks,
            center: filteredGeometry.center,
            palmWidth: filteredGeometry.width,
            scaleSource: filteredGeometry.scaleSource,
            confidence: min(candidate.observation.observationConfidence, candidate.geometry.anchorConfidence),
            chirality: candidate.observation.chirality,
            velocity: Point2D(x: 0, y: 0),
            missingDuration: 0,
            associationCertain: true,
            filters: filters
        )
        nextID &+= 1
        tracks.append(track)
    }

    private mutating func pruneExpired(at timestamp: MonotonicTimestamp) {
        tracks.removeAll { track in
            let missing = timestamp.duration(since: track.lastObservationTimestamp)
            return !missing.isFinite || missing > tuning.trackRetentionDuration + 1e-9
        }
    }

    private mutating func makeCapacityForNewTracks(
        count requestedCount: Int,
        matchedTrackIndices: Set<Int>
    ) {
        let needed = max(0, tracks.count + requestedCount - 2)
        guard needed > 0 else { return }

        let removable = tracks.indices
            .filter { !matchedTrackIndices.contains($0) }
            .sorted {
                let lhs = tracks[$0]
                let rhs = tracks[$1]
                if lhs.lastObservationTimestamp != rhs.lastObservationTimestamp {
                    return lhs.lastObservationTimestamp < rhs.lastObservationTimestamp
                }
                return lhs.id < rhs.id
            }
        let indicesToRemove = removable.prefix(needed).sorted(by: >)
        for index in indicesToRemove {
            tracks.remove(at: index)
        }
    }

    private func chooseAssignment(
        observations: [ObservationCandidate],
        at timestamp: MonotonicTimestamp
    ) -> Assignment {
        guard !tracks.isEmpty else { return Assignment(observationByTrack: [], score: 0) }

        var best: Assignment?
        var current = Array<Int?>(repeating: nil, count: tracks.count)

        func enumerate(trackIndex: Int, used: Set<Int>, score: Double) {
            if trackIndex == tracks.count {
                let unmatchedObservationCount = observations.count - used.count
                let candidate = Assignment(
                    observationByTrack: current,
                    score: score + Double(unmatchedObservationCount)
                )
                if Self.isPreferred(candidate, over: best) {
                    best = candidate
                }
                return
            }

            current[trackIndex] = nil
            enumerate(trackIndex: trackIndex + 1, used: used, score: score + 1)

            for observationIndex in observations.indices where !used.contains(observationIndex) {
                guard let cost = associationCost(
                    track: tracks[trackIndex],
                    observation: observations[observationIndex],
                    at: timestamp
                ) else {
                    continue
                }
                current[trackIndex] = observationIndex
                var nextUsed = used
                nextUsed.insert(observationIndex)
                enumerate(trackIndex: trackIndex + 1, used: nextUsed, score: score + cost)
            }
            current[trackIndex] = nil
        }

        enumerate(trackIndex: 0, used: [], score: 0)
        return best ?? Assignment(observationByTrack: Array(repeating: nil, count: tracks.count), score: .infinity)
    }

    private func assignmentAmbiguity(
        observations: [ObservationCandidate],
        at timestamp: MonotonicTimestamp
    ) -> Double? {
        guard tracks.count == 2, observations.count == 2,
              let cost00 = associationCost(track: tracks[0], observation: observations[0], at: timestamp),
              let cost11 = associationCost(track: tracks[1], observation: observations[1], at: timestamp),
              let cost01 = associationCost(track: tracks[0], observation: observations[1], at: timestamp),
              let cost10 = associationCost(track: tracks[1], observation: observations[0], at: timestamp) else {
            return nil
        }
        return abs((cost00 + cost11) - (cost01 + cost10))
    }

    private func associationCost(
        track: TrackState,
        observation: ObservationCandidate,
        at timestamp: MonotonicTimestamp
    ) -> Double? {
        let dt = timestamp.duration(since: track.lastObservationTimestamp)
        guard dt.isFinite, dt > 0, dt <= 0.200 else { return nil }

        let scaleRatio = observation.geometry.width / track.palmWidth
        guard scaleRatio.isFinite,
              scaleRatio >= tuning.associationScaleRatioMinimum,
              scaleRatio <= tuning.associationScaleRatioMaximum else {
            return nil
        }

        let maximumVelocity = 8 * max(track.palmWidth, observation.geometry.width)
        let predictedVelocity = TrackingMath.clampMagnitude(track.velocity, maximum: maximumVelocity)
        let predictedCenter = TrackingMath.add(
            track.center,
            TrackingMath.multiply(predictedVelocity, by: dt)
        )
        let positionCost = TrackingMath.distance(observation.geometry.center, predictedCenter)
            / max(track.palmWidth, observation.geometry.width)
        guard positionCost.isFinite, positionCost <= tuning.associationPositionGate else { return nil }

        let scaleCost = abs(log(scaleRatio))
        var chiralityPenalty = 0.0
        if track.chirality != .unknown,
           observation.observation.chirality != .unknown,
           track.chirality != observation.observation.chirality {
            chiralityPenalty = 0.20
        }
        return positionCost + 0.35 * scaleCost + chiralityPenalty
    }

    private func trackingQuality(
        at timestamp: MonotonicTimestamp,
        ambiguous: Bool
    ) -> (quality: TrackingQuality, reason: TrackingDegradationReason?) {
        guard !tracks.isEmpty else { return (.absent, .noHandDetected) }
        if ambiguous { return (.degraded, .associationAmbiguous) }

        // A current, certainly-associated hand is sufficient for healthy
        // one-hand input. A retained missing second track must not poison it.
        let currentTracks = tracks.filter { $0.missingDuration <= 0 }
        if currentTracks.contains(where: \.associationCertain) {
            return (.good, nil)
        }

        let withinGrace = tracks.contains { track in
            let missing = timestamp.duration(since: track.lastObservationTimestamp)
            return missing.isFinite && missing <= tuning.trackingLossGraceDuration
        }
        return withinGrace
            ? (.degraded, .handIdentityLost)
            : (.absent, .handIdentityLost)
    }

    private static func observationOrder(_ lhs: ObservationCandidate, _ rhs: ObservationCandidate) -> Bool {
        if lhs.geometry.center.x != rhs.geometry.center.x {
            return lhs.geometry.center.x < rhs.geometry.center.x
        }
        if lhs.geometry.center.y != rhs.geometry.center.y {
            return lhs.geometry.center.y < rhs.geometry.center.y
        }
        if lhs.geometry.width != rhs.geometry.width {
            return lhs.geometry.width < rhs.geometry.width
        }
        if lhs.observation.chirality != rhs.observation.chirality {
            return lhs.observation.chirality.rawValue < rhs.observation.chirality.rawValue
        }
        if lhs.observation.observationConfidence != rhs.observation.observationConfidence {
            return lhs.observation.observationConfidence < rhs.observation.observationConfidence
        }

        for name in LandmarkName.allCases {
            let lhsSample = lhs.observation.landmarks[name]
            let rhsSample = rhs.observation.landmarks[name]
            if lhsSample == nil, rhsSample != nil { return true }
            if lhsSample != nil, rhsSample == nil { return false }
            guard let lhsSample, let rhsSample else { continue }

            for (lhsValue, rhsValue) in [
                (lhsSample.position.x, rhsSample.position.x),
                (lhsSample.position.y, rhsSample.position.y),
                (lhsSample.confidence, rhsSample.confidence)
            ] {
                let lhsKey = Self.finiteSortKey(lhsValue)
                let rhsKey = Self.finiteSortKey(rhsValue)
                if lhsKey != rhsKey { return lhsKey < rhsKey }
            }
        }
        return false
    }

    private static func finiteSortKey(_ value: Double) -> Double {
        value.isFinite ? value : .infinity
    }

    private static func isPreferred(_ candidate: Assignment, over current: Assignment?) -> Bool {
        guard let current else { return true }
        if abs(candidate.score - current.score) > 1e-12 {
            return candidate.score < current.score
        }
        if candidate.matchCount != current.matchCount {
            return candidate.matchCount > current.matchCount
        }
        return candidate.signature.lexicographicallyPrecedes(current.signature)
    }
}
