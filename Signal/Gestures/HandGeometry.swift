import Foundation

/// Framework-independent hand geometry and pose classification.
public struct HandPoseClassifier: Sendable {
    public init() {}

    public func classify(
        _ hand: TrackedHandSnapshot,
        tuning: GestureTuning = .safeDefaults,
        activePinchEpisode: Bool = false
    ) -> PoseMetrics {
        let tuning = tuning.validated()
        let empty = FingerMetrics(
            extensionScore: 0,
            proximalAngleDegrees: 0,
            distalAngleDegrees: 0,
            reach: 0
        )

        guard hand.associationCertain,
              hand.missingDuration <= 0,
              hand.palmWidth.isFinite,
              hand.palmWidth >= 0.02,
              hand.palmWidth <= 0.80,
              let wrist = position(.wrist, in: hand, tuning: tuning) else {
            return PoseMetrics(
                pose: .lowConfidence,
                thumb: empty,
                index: empty,
                middle: empty,
                ring: empty,
                little: empty,
                pinchRatio: nil,
                palmWidth: hand.palmWidth.isFinite ? max(0, hand.palmWidth) : 0,
                minimumRequiredConfidence: minimumAvailableConfidence(in: hand)
            )
        }

        let indexValue = fingerMetrics(
                mcp: .indexMCP,
                pip: .indexPIP,
                dip: .indexDIP,
                tip: .indexTip,
                wrist: wrist,
                hand: hand,
                tuning: tuning
              )
        let middleFullValue = fingerMetrics(
                mcp: .middleMCP,
                pip: .middlePIP,
                dip: .middleDIP,
                tip: .middleTip,
                wrist: wrist,
                hand: hand,
                tuning: tuning
              )
        let ringFullValue = fingerMetrics(
                mcp: .ringMCP,
                pip: .ringPIP,
                dip: .ringDIP,
                tip: .ringTip,
                wrist: wrist,
                hand: hand,
                tuning: tuning
              )
        let littleFullValue = fingerMetrics(
                mcp: .littleMCP,
                pip: .littlePIP,
                dip: .littleDIP,
                tip: .littleTip,
                wrist: wrist,
                hand: hand,
                tuning: tuning
              )

        // Folded fingers are commonly occluded at their tips. Pointer and pinch
        // classification therefore use proximal evidence (MCP/PIP/DIP), while
        // the full metrics remain available whenever Vision supplied the tip.
        let middleProximal = proximalFingerMetrics(
            mcp: .middleMCP,
            pip: .middlePIP,
            dip: .middleDIP,
            wrist: wrist,
            hand: hand,
            tuning: tuning
        )
        let ringProximal = proximalFingerMetrics(
            mcp: .ringMCP,
            pip: .ringPIP,
            dip: .ringDIP,
            wrist: wrist,
            hand: hand,
            tuning: tuning
        )
        let littleProximal = proximalFingerMetrics(
            mcp: .littleMCP,
            pip: .littlePIP,
            dip: .littleDIP,
            wrist: wrist,
            hand: hand,
            tuning: tuning
        )

        let index = indexValue ?? empty
        let middle = middleFullValue ?? middleProximal ?? empty
        let ring = ringFullValue ?? ringProximal ?? empty
        let little = littleFullValue ?? littleProximal ?? empty

        let thumb = thumbMetrics(wrist: wrist, hand: hand, tuning: tuning)
        let pinchRatio = pinchRatio(in: hand, tuning: tuning)
        let extendedThreshold = tuning.poseEnterScore
        let foldedThreshold = tuning.foldedMaximumScore
        let nonThumbScores = [
            index.extensionScore,
            middle.extensionScore,
            ring.extensionScore,
            little.extensionScore
        ]

        let allFingerTipsAvailable = indexValue != nil && middleFullValue != nil
            && ringFullValue != nil && littleFullValue != nil
        let openPalm = allFingerTipsAvailable
            && nonThumbScores.allSatisfy { $0 >= extendedThreshold }
            && adjacentTipSeparation(in: hand, tuning: tuning) >= 0.55

        let fistThreshold = min(0.30, foldedThreshold)
        let middleThumbContactLikely = activePinchEpisode
            || (pinchRatio.map { $0 <= pinchIntentMaximum(tuning) } ?? false)
        let fist = allFingerTipsAvailable
            && nonThumbScores.allSatisfy { $0 <= fistThreshold }
            && foldedTipCount(in: hand, wrist: wrist, tuning: tuning) >= 3
            && !middleThumbContactLikely

        let pointer = indexValue != nil
            && index.extensionScore >= extendedThreshold
            && isConfidentlyFolded(middleProximal, threshold: foldedThreshold)
            && isConfidentlyFolded(ringProximal, threshold: foldedThreshold)
            && isConfidentlyFolded(littleProximal, threshold: foldedThreshold)
            && !middleThumbContactLikely

        // Pinch semantics are exclusively thumb-to-middle. Index posture is
        // deliberately irrelevant. The open threshold is the outer edge of
        // ambiguous contact; wider separations remain available to pointer
        // classification while the state machine separately rearms there.
        let pinchReady = pinchRatio.map { $0 <= pinchIntentMaximum(tuning) } ?? false

        let pose: PoseKind
        if pinchReady {
            pose = .pinch
        } else if pointer {
            pose = .pointer
        } else if openPalm {
            pose = .openPalm
        } else if fist {
            pose = .fist
        } else {
            pose = .unknown
        }

        let minimumConfidence = minimumRequiredConfidence(for: pose, in: hand)
        return PoseMetrics(
            pose: pose,
            thumb: thumb ?? empty,
            index: index,
            middle: middle,
            ring: ring,
            little: little,
            pinchRatio: pinchRatio,
            indexMiddleTipSeparation: distanceBetween(
                .indexTip,
                .middleTip,
                in: hand,
                tuning: tuning
            ),
            palmWidth: hand.palmWidth,
            minimumRequiredConfidence: minimumConfidence
        )
    }

    private func fingerMetrics(
        mcp: LandmarkName,
        pip: LandmarkName,
        dip: LandmarkName,
        tip: LandmarkName,
        wrist: Point2D,
        hand: TrackedHandSnapshot,
        tuning: GestureTuning
    ) -> FingerMetrics? {
        guard let mcpPoint = position(mcp, in: hand, tuning: tuning),
              let pipPoint = position(pip, in: hand, tuning: tuning),
              let dipPoint = position(dip, in: hand, tuning: tuning),
              let tipPoint = position(tip, in: hand, tuning: tuning),
              let baseRay = (mcpPoint - wrist).normalized else {
            return nil
        }

        let proximal = jointAngleDegrees(mcpPoint, pipPoint, dipPoint)
        let distal = jointAngleDegrees(pipPoint, dipPoint, tipPoint)
        guard proximal.isFinite, distal.isFinite else { return nil }

        let reach = (tipPoint - mcpPoint).dot(baseRay) / hand.palmWidth
        guard reach.isFinite else { return nil }

        let score = min(
            straightness(proximal),
            straightness(distal),
            smoothstep(edge0: 0.25, edge1: 0.55, value: reach)
        ).clamped(to: 0 ... 1)

        return FingerMetrics(
            extensionScore: score,
            proximalAngleDegrees: proximal.clamped(to: 0 ... 180),
            distalAngleDegrees: distal.clamped(to: 0 ... 180),
            reach: reach.clamped(to: -4 ... 4)
        )
    }

    private func proximalFingerMetrics(
        mcp: LandmarkName,
        pip: LandmarkName,
        dip: LandmarkName,
        wrist: Point2D,
        hand: TrackedHandSnapshot,
        tuning: GestureTuning
    ) -> FingerMetrics? {
        guard let mcpPoint = position(mcp, in: hand, tuning: tuning),
              let pipPoint = position(pip, in: hand, tuning: tuning),
              let dipPoint = position(dip, in: hand, tuning: tuning),
              let baseRay = (mcpPoint - wrist).normalized else {
            return nil
        }

        let proximal = jointAngleDegrees(mcpPoint, pipPoint, dipPoint)
        let reach = (dipPoint - mcpPoint).dot(baseRay) / hand.palmWidth
        guard proximal.isFinite, reach.isFinite else { return nil }

        let score = min(
            straightness(proximal),
            smoothstep(edge0: 0.16, edge1: 0.38, value: reach)
        ).clamped(to: 0 ... 1)
        return FingerMetrics(
            extensionScore: score,
            proximalAngleDegrees: proximal.clamped(to: 0 ... 180),
            distalAngleDegrees: proximal.clamped(to: 0 ... 180),
            reach: reach.clamped(to: -4 ... 4)
        )
    }

    private func isConfidentlyFolded(
        _ metrics: FingerMetrics?,
        threshold: Double
    ) -> Bool {
        guard let metrics else { return false }
        return metrics.extensionScore <= threshold
    }

    private func thumbMetrics(
        wrist: Point2D,
        hand: TrackedHandSnapshot,
        tuning: GestureTuning
    ) -> FingerMetrics? {
        guard let cmc = position(.thumbCMC, in: hand, tuning: tuning),
              let mp = position(.thumbMP, in: hand, tuning: tuning),
              let ip = position(.thumbIP, in: hand, tuning: tuning),
              let tip = position(.thumbTip, in: hand, tuning: tuning),
              let thumbRay = (mp - cmc).normalized else {
            return nil
        }

        let proximal = jointAngleDegrees(cmc, mp, ip)
        let distal = jointAngleDegrees(mp, ip, tip)
        guard proximal.isFinite, distal.isFinite else { return nil }

        let reach = (tip - mp).dot(thumbRay) / hand.palmWidth
        guard reach.isFinite else { return nil }

        let score = min(
            straightness(proximal),
            straightness(distal),
            smoothstep(edge0: 0.18, edge1: 0.42, value: reach)
        ).clamped(to: 0 ... 1)

        return FingerMetrics(
            extensionScore: score,
            proximalAngleDegrees: proximal.clamped(to: 0 ... 180),
            distalAngleDegrees: distal.clamped(to: 0 ... 180),
            reach: reach.clamped(to: -4 ... 4)
        )
    }

    private func pinchRatio(
        in hand: TrackedHandSnapshot,
        tuning: GestureTuning
    ) -> Double? {
        let required: [LandmarkName] = [
            .thumbMP, .thumbIP, .thumbTip,
            .middleMCP, .middlePIP, .middleDIP, .middleTip,
            .wrist
        ]
        guard required.allSatisfy({ position($0, in: hand, tuning: tuning) != nil }),
              let thumb = position(.thumbTip, in: hand, tuning: tuning),
              let middle = position(.middleTip, in: hand, tuning: tuning) else {
            return nil
        }
        let ratio = thumb.distance(to: middle) / hand.palmWidth
        return ratio.isFinite ? ratio.clamped(to: 0 ... 10) : nil
    }

    private func adjacentTipSeparation(
        in hand: TrackedHandSnapshot,
        tuning: GestureTuning
    ) -> Double {
        let pairs: [(LandmarkName, LandmarkName)] = [
            (.indexTip, .middleTip),
            (.middleTip, .ringTip),
            (.ringTip, .littleTip)
        ]
        let sum = pairs.compactMap {
            distanceBetween($0.0, $0.1, in: hand, tuning: tuning)
        }.reduce(0, +)
        return sum.isFinite ? sum : 0
    }

    private func foldedTipCount(
        in hand: TrackedHandSnapshot,
        wrist: Point2D,
        tuning: GestureTuning
    ) -> Int {
        let anchors: [LandmarkName] = [.indexMCP, .middleMCP, .ringMCP, .littleMCP]
        let anchorPoints = anchors.compactMap { position($0, in: hand, tuning: tuning) }
        guard anchorPoints.count >= 3 else { return 0 }
        let sum = anchorPoints.reduce(wrist * 2, +)
        let center = sum / Double(anchorPoints.count + 2)
        let tips: [LandmarkName] = [.indexTip, .middleTip, .ringTip, .littleTip]
        return tips.compactMap { position($0, in: hand, tuning: tuning) }
            .filter { $0.distance(to: center) / hand.palmWidth <= 0.85 }
            .count
    }

    private func distanceBetween(
        _ lhs: LandmarkName,
        _ rhs: LandmarkName,
        in hand: TrackedHandSnapshot,
        tuning: GestureTuning
    ) -> Double? {
        guard let a = position(lhs, in: hand, tuning: tuning),
              let b = position(rhs, in: hand, tuning: tuning) else {
            return nil
        }
        let result = a.distance(to: b) / hand.palmWidth
        return result.isFinite ? result : nil
    }

    private func position(
        _ name: LandmarkName,
        in hand: TrackedHandSnapshot,
        tuning: GestureTuning
    ) -> Point2D? {
        guard let raw = hand.rawLandmarks[name],
              raw.confidence.isFinite,
              raw.confidence >= tuning.minimumLandmarkConfidence,
              let filtered = hand.filteredLandmarks[name],
              filtered.position.isFinite else {
            return nil
        }
        return filtered.position
    }

    private func minimumRequiredConfidence(
        for pose: PoseKind,
        in hand: TrackedHandSnapshot
    ) -> Double {
        var required: [LandmarkName]
        switch pose {
        case .pointer:
            required = [
                .wrist,
                .indexMCP, .indexPIP, .indexDIP, .indexTip,
                .middleMCP, .middlePIP, .middleDIP,
                .ringMCP, .ringPIP, .ringDIP,
                .littleMCP, .littlePIP, .littleDIP
            ]
        case .pinch:
            required = [
                .wrist,
                .thumbMP, .thumbIP, .thumbTip,
                .middleMCP, .middlePIP, .middleDIP, .middleTip
            ]
        case .openPalm, .fist, .scroll, .unknown, .lowConfidence:
            return minimumAvailableConfidence(in: hand)
        }
        if pose == .pinch {
            switch hand.palmScaleSource {
            case .indexToLittleMCP:
                required.append(.littleMCP)
            case .wristToMiddleMCP:
                required.append(.middleMCP)
            case .unavailable:
                break
            }
        }
        let values = required.compactMap { name -> Double? in
            guard let value = hand.rawLandmarks[name]?.confidence, value.isFinite else {
                return nil
            }
            return value
        }
        return values.count == required.count ? (values.min() ?? 0) : 0
    }

    private func minimumAvailableConfidence(in hand: TrackedHandSnapshot) -> Double {
        let values = hand.rawLandmarks.samples.values.compactMap { sample in
            sample.confidence.isFinite ? sample.confidence : nil
        }
        return values.min() ?? 0
    }

    private func jointAngleDegrees(_ a: Point2D, _ b: Point2D, _ c: Point2D) -> Double {
        guard let first = (a - b).normalized,
              let second = (c - b).normalized else {
            return .nan
        }
        let cosine = first.dot(second).clamped(to: -1 ... 1)
        return acos(cosine) * 180 / .pi
    }

    private func straightness(_ degrees: Double) -> Double {
        smoothstep(edge0: 135, edge1: 165, value: degrees)
    }

    private func smoothstep(edge0: Double, edge1: Double, value: Double) -> Double {
        guard edge0.isFinite, edge1.isFinite, value.isFinite, edge1 > edge0 else {
            return 0
        }
        let t = ((value - edge0) / (edge1 - edge0)).clamped(to: 0 ... 1)
        return t * t * (3 - 2 * t)
    }

    private func pinchIntentMaximum(_ tuning: GestureTuning) -> Double {
        tuning.pinchIntentRatio
    }
}

extension Point2D {
    static let zero = Point2D(x: 0, y: 0)

    var isFinite: Bool { x.isFinite && y.isFinite }
    var magnitude: Double { hypot(x, y) }

    var normalized: Point2D? {
        let length = magnitude
        guard length.isFinite, length > 1e-12 else { return nil }
        return self / length
    }

    func dot(_ other: Point2D) -> Double {
        x * other.x + y * other.y
    }

    func distance(to other: Point2D) -> Double {
        (self - other).magnitude
    }

    static func + (lhs: Point2D, rhs: Point2D) -> Point2D {
        Point2D(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    static func - (lhs: Point2D, rhs: Point2D) -> Point2D {
        Point2D(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    static prefix func - (value: Point2D) -> Point2D {
        Point2D(x: -value.x, y: -value.y)
    }

    static func * (lhs: Point2D, rhs: Double) -> Point2D {
        Point2D(x: lhs.x * rhs, y: lhs.y * rhs)
    }

    static func / (lhs: Point2D, rhs: Double) -> Point2D {
        Point2D(x: lhs.x / rhs, y: lhs.y / rhs)
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
