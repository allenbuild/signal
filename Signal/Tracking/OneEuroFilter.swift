import Foundation

struct LandmarkFilterResult: Sendable {
    var landmarks: HandLandmarks
    var resetOccurred: Bool
}

struct LandmarkFilterBank: Sendable {
    private var filters: [LandmarkName: VectorOneEuroFilter] = [:]
    private var lastSeen: [LandmarkName: MonotonicTimestamp] = [:]

    mutating func reset() {
        filters.removeAll(keepingCapacity: true)
        lastSeen.removeAll(keepingCapacity: true)
    }

    mutating func filter(
        _ raw: HandLandmarks,
        at timestamp: MonotonicTimestamp,
        palmWidth: Double,
        tuning: GestureTuning,
        forceReset: Bool
    ) -> LandmarkFilterResult {
        if forceReset {
            reset()
        }

        var output = HandLandmarks()
        output.samples.reserveCapacity(LandmarkName.allCases.count)
        var resetOccurred = forceReset
        let jointResetGap = min(max(tuning.filterResetGap, 0), 0.100)

        for name in LandmarkName.allCases {
            guard let sample = raw[name],
                  sample.confidence.isFinite,
                  sample.confidence >= tuning.minimumLandmarkConfidence,
                  TrackingMath.isFinite(sample.position) else {
                continue
            }

            var filter = filters[name] ?? VectorOneEuroFilter()
            var shouldReset = filters[name] == nil

            if let previousSeen = lastSeen[name] {
                let gap = timestamp.duration(since: previousSeen)
                if !gap.isFinite || gap <= 0 {
                    if let current = filter.currentValue {
                        output[name] = LandmarkSample(
                            position: current,
                            confidence: sample.confidence
                        )
                    }
                    // Duplicate, backward, and nonfinite time cannot mutate
                    // filter state or the next accepted numeric sample.
                    continue
                }
                if gap > jointResetGap {
                    shouldReset = true
                }
            } else {
                guard timestamp.rawValue.isFinite else { continue }
                shouldReset = true
            }

            if let previousRaw = filter.previousRaw,
               palmWidth.isFinite,
               palmWidth > TrackingMath.epsilon {
                let normalizedStep = TrackingMath.distance(sample.position, previousRaw) / palmWidth
                if !normalizedStep.isFinite || normalizedStep > tuning.normalizedDiscontinuityStep {
                    shouldReset = true
                }
            }

            let filtered = filter.filter(
                sample.position,
                at: timestamp,
                minimumCutoff: tuning.oneEuroMinimumCutoff,
                derivativeCutoff: tuning.oneEuroDerivativeCutoff,
                beta: tuning.oneEuroBeta,
                reset: shouldReset
            )

            filters[name] = filter
            lastSeen[name] = timestamp
            output[name] = LandmarkSample(position: filtered.point, confidence: sample.confidence)
            resetOccurred = resetOccurred || filtered.didReset
        }

        return LandmarkFilterResult(landmarks: output, resetOccurred: resetOccurred)
    }
}

private struct VectorOneEuroFilter: Sendable {
    private var x = ScalarOneEuroFilter()
    private var y = ScalarOneEuroFilter()
    private(set) var previousRaw: Point2D?
    var currentValue: Point2D? {
        guard let x = x.currentValue, let y = y.currentValue else { return nil }
        return Point2D(x: x, y: y)
    }

    mutating func filter(
        _ value: Point2D,
        at timestamp: MonotonicTimestamp,
        minimumCutoff: Double,
        derivativeCutoff: Double,
        beta: Double,
        reset: Bool
    ) -> (point: Point2D, didReset: Bool) {
        let filteredX = x.filter(
            value.x,
            at: timestamp,
            minimumCutoff: minimumCutoff,
            derivativeCutoff: derivativeCutoff,
            beta: beta,
            reset: reset
        )
        let filteredY = y.filter(
            value.y,
            at: timestamp,
            minimumCutoff: minimumCutoff,
            derivativeCutoff: derivativeCutoff,
            beta: beta,
            reset: reset
        )
        previousRaw = value
        return (
            Point2D(x: filteredX.value, y: filteredY.value),
            filteredX.didReset || filteredY.didReset
        )
    }
}

private struct ScalarOneEuroFilter: Sendable {
    private var previousTimestamp: MonotonicTimestamp?
    private var previousRaw: Double?
    private var filteredValue: Double?
    private var filteredDerivative: Double = 0
    var currentValue: Double? { filteredValue }

    mutating func filter(
        _ value: Double,
        at timestamp: MonotonicTimestamp,
        minimumCutoff: Double,
        derivativeCutoff: Double,
        beta: Double,
        reset requestedReset: Bool
    ) -> (value: Double, didReset: Bool) {
        guard value.isFinite, timestamp.rawValue.isFinite else {
            reset(to: value.isFinite ? value : 0, at: timestamp)
            return (value.isFinite ? value : 0, true)
        }

        guard !requestedReset,
              let previousTimestamp,
              let previousRaw,
              let filteredValue else {
            reset(to: value, at: timestamp)
            return (value, true)
        }

        let dt = timestamp.duration(since: previousTimestamp)
        guard dt.isFinite, dt > 0, dt <= 0.100 else {
            reset(to: value, at: timestamp)
            return (value, true)
        }

        let derivative = (value - previousRaw) / dt
        let derivativeAlpha = Self.alpha(cutoff: derivativeCutoff, dt: dt)
        filteredDerivative = derivativeAlpha * derivative + (1 - derivativeAlpha) * filteredDerivative

        let adaptiveCutoff = minimumCutoff + beta * abs(filteredDerivative)
        let valueAlpha = Self.alpha(cutoff: adaptiveCutoff, dt: dt)
        let nextValue = valueAlpha * value + (1 - valueAlpha) * filteredValue

        self.previousTimestamp = timestamp
        self.previousRaw = value
        self.filteredValue = nextValue
        return (nextValue, false)
    }

    private mutating func reset(to value: Double, at timestamp: MonotonicTimestamp) {
        previousTimestamp = timestamp
        previousRaw = value
        filteredValue = value
        filteredDerivative = 0
    }

    private static func alpha(cutoff: Double, dt: Double) -> Double {
        guard cutoff.isFinite, cutoff > 0, dt.isFinite, dt > 0 else { return 1 }
        let tau = 1 / (2 * Double.pi * cutoff)
        return 1 / (1 + tau / dt)
    }
}
