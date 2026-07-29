import Foundation

/// Tunable thresholds used only by deterministic command-pose recognition.
///
/// Control pointer and pinch tuning remain owned by `GestureTuning`.
public struct CommandGestureTuning: Equatable, Sendable {
    public var minimumGestureConfidence: Double
    public var thumbVerticalMinimum: Double
    public var thumbVerticalDominance: Double
    public var cShapeMinimumExtension: Double
    public var cShapeMaximumExtension: Double
    public var cShapeMinimumJointAngle: Double
    public var cShapeMaximumJointAngle: Double
    public var cShapeMinimumThumbIndexGap: Double
    public var cShapeMaximumThumbIndexGap: Double
    public var cShapeMinimumTipRadius: Double
    public var fistMaximumTipRadius: Double

    public init(
        minimumGestureConfidence: Double = 0.58,
        thumbVerticalMinimum: Double = 0.42,
        thumbVerticalDominance: Double = 1.10,
        cShapeMinimumExtension: Double = 0.12,
        cShapeMaximumExtension: Double = 0.72,
        cShapeMinimumJointAngle: Double = 82,
        cShapeMaximumJointAngle: Double = 155,
        cShapeMinimumThumbIndexGap: Double = 0.42,
        cShapeMaximumThumbIndexGap: Double = 1.30,
        cShapeMinimumTipRadius: Double = 0.46,
        fistMaximumTipRadius: Double = 0.85
    ) {
        self.minimumGestureConfidence = minimumGestureConfidence
        self.thumbVerticalMinimum = thumbVerticalMinimum
        self.thumbVerticalDominance = thumbVerticalDominance
        self.cShapeMinimumExtension = cShapeMinimumExtension
        self.cShapeMaximumExtension = cShapeMaximumExtension
        self.cShapeMinimumJointAngle = cShapeMinimumJointAngle
        self.cShapeMaximumJointAngle = cShapeMaximumJointAngle
        self.cShapeMinimumThumbIndexGap = cShapeMinimumThumbIndexGap
        self.cShapeMaximumThumbIndexGap = cShapeMaximumThumbIndexGap
        self.cShapeMinimumTipRadius = cShapeMinimumTipRadius
        self.fistMaximumTipRadius = fistMaximumTipRadius
    }

    fileprivate func validated() -> Self {
        var result = self
        result.minimumGestureConfidence = result.minimumGestureConfidence.finiteClamped(to: 0 ... 1)
        result.thumbVerticalMinimum = result.thumbVerticalMinimum.finiteClamped(to: 0.05 ... 2)
        result.thumbVerticalDominance = result.thumbVerticalDominance.finiteClamped(to: 1 ... 4)
        result.cShapeMinimumExtension = result.cShapeMinimumExtension.finiteClamped(to: 0 ... 0.80)
        result.cShapeMaximumExtension = result.cShapeMaximumExtension.finiteClamped(
            to: (result.cShapeMinimumExtension + 0.01) ... 0.95
        )
        result.cShapeMinimumJointAngle = result.cShapeMinimumJointAngle.finiteClamped(to: 30 ... 150)
        result.cShapeMaximumJointAngle = result.cShapeMaximumJointAngle.finiteClamped(
            to: (result.cShapeMinimumJointAngle + 1) ... 175
        )
        result.cShapeMinimumThumbIndexGap = result.cShapeMinimumThumbIndexGap.finiteClamped(to: 0.05 ... 2)
        result.cShapeMaximumThumbIndexGap = result.cShapeMaximumThumbIndexGap.finiteClamped(
            to: (result.cShapeMinimumThumbIndexGap + 0.01) ... 4
        )
        result.cShapeMinimumTipRadius = result.cShapeMinimumTipRadius.finiteClamped(to: 0.05 ... 2)
        result.fistMaximumTipRadius = result.fistMaximumTipRadius.finiteClamped(to: 0.10 ... 2)
        return result
    }
}

/// Stateless, deterministic recognition for Signal's eight command poses.
///
/// The classifier consumes the existing Control geometry metrics but never
/// mutates or emits through the Control gesture state machine. Callers must
/// still apply stable-hold, one-shot, mode, and editor gates before executing
/// a command.
public struct CommandGestureClassifier: Sendable {
    private let controlTuning: GestureTuning
    private let tuning: CommandGestureTuning

    public init(
        controlTuning: GestureTuning = .safeDefaults,
        tuning: CommandGestureTuning = .init()
    ) {
        self.controlTuning = controlTuning.validated()
        self.tuning = tuning.validated()
    }

    public func classify(
        _ hand: TrackedHandSnapshot,
        poseMetrics suppliedMetrics: PoseMetrics? = nil,
        pinchActive: Bool = false
    ) -> CommandGestureCandidate? {
        guard isUsable(hand), !pinchActive else { return nil }

        let metrics = suppliedMetrics ?? HandPoseClassifier().classify(
            hand,
            tuning: controlTuning,
            activePinchEpisode: false
        )
        guard metrics.palmWidth.isFinite,
              metrics.palmWidth > 0 else { return nil }

        if let candidate = recognizeThumbDirection(hand: hand, metrics: metrics) {
            return candidate
        }
        if let candidate = recognizeCShape(hand: hand, metrics: metrics) {
            return candidate
        }
        if let candidate = recognizeNumber(hand: hand, metrics: metrics) {
            return candidate
        }
        return recognizeFist(hand: hand, metrics: metrics)
    }

    private func recognizeNumber(
        hand: TrackedHandSnapshot,
        metrics: PoseMetrics
    ) -> CommandGestureCandidate? {
        let state = FingerState(metrics: metrics, tuning: controlTuning)
        let specification: (
            gesture: CommandGesture,
            extended: [CommandFinger],
            folded: [CommandFinger],
            requireThumb: Bool
        )?

        switch (state.index, state.middle, state.ring, state.little) {
        case (.extended, .folded, .folded, .folded):
            specification = (.one, [.index], [.middle, .ring, .little], false)
        case (.extended, .extended, .folded, .folded):
            specification = (.two, [.index, .middle], [.ring, .little], false)
        case (.extended, .extended, .extended, .folded):
            specification = (.three, [.index, .middle, .ring], [.little], false)
        case (.extended, .extended, .extended, .extended)
            where state.thumb == .folded:
            specification = (
                .four,
                [.index, .middle, .ring, .little],
                [.thumb],
                true
            )
        default:
            specification = nil
        }

        guard let specification else { return nil }
        var required = palmRequiredJoints(for: hand)
        for finger in specification.extended {
            required.formUnion(finger.fullChain)
        }
        for finger in specification.folded where finger != .thumb {
            required.formUnion(finger.proximalChain)
        }
        if specification.requireThumb {
            required.formUnion(CommandFinger.thumb.fullChain)
        }

        let supports = specification.extended.map {
            extensionSupport(metrics[$0].extensionScore)
        } + specification.folded.map {
            foldedSupport(metrics[$0].extensionScore)
        }
        return makeCandidate(
            specification.gesture,
            shapeConfidence: supports.min() ?? 0,
            required: required,
            hand: hand
        )
    }

    private func recognizeThumbDirection(
        hand: TrackedHandSnapshot,
        metrics: PoseMetrics
    ) -> CommandGestureCandidate? {
        let state = FingerState(metrics: metrics, tuning: controlTuning)
        guard state.thumb == .extended,
              state.index == .folded,
              state.middle == .folded,
              state.ring == .folded,
              state.little == .folded,
              let thumbCMC = position(.thumbCMC, in: hand),
              let thumbTip = position(.thumbTip, in: hand) else {
            return nil
        }

        let vector = thumbTip - thumbCMC
        let vertical = vector.y / hand.palmWidth
        let horizontal = abs(vector.x / hand.palmWidth)
        let magnitude = abs(vertical)
        guard magnitude >= tuning.thumbVerticalMinimum,
              magnitude >= horizontal * tuning.thumbVerticalDominance else {
            return nil
        }

        var required = palmRequiredJoints(for: hand)
        required.formUnion(CommandFinger.thumb.fullChain)
        for finger in CommandFinger.nonThumb {
            required.formUnion(finger.proximalChain)
        }
        let directionSupport = ramp(
            magnitude,
            from: tuning.thumbVerticalMinimum,
            to: tuning.thumbVerticalMinimum * 1.8
        )
        let dominanceSupport = ramp(
            magnitude / max(horizontal, 0.000_1),
            from: tuning.thumbVerticalDominance,
            to: tuning.thumbVerticalDominance * 1.8
        )
        let foldedSupports = CommandFinger.nonThumb.map {
            foldedSupport(metrics[$0].extensionScore)
        }
        let shape = (
            [extensionSupport(metrics.thumb.extensionScore), directionSupport, dominanceSupport]
                + foldedSupports
        ).min() ?? 0
        return makeCandidate(
            vertical > 0 ? .thumbsUp : .thumbsDown,
            shapeConfidence: shape,
            required: required,
            hand: hand
        )
    }

    private func recognizeCShape(
        hand: TrackedHandSnapshot,
        metrics: PoseMetrics
    ) -> CommandGestureCandidate? {
        let fingers = CommandFinger.nonThumb
        let fingerMetrics = fingers.map { metrics[$0] }
        guard fingerMetrics.allSatisfy({
            $0.extensionScore >= tuning.cShapeMinimumExtension
                && $0.extensionScore <= tuning.cShapeMaximumExtension
                && $0.proximalAngleDegrees >= tuning.cShapeMinimumJointAngle
                && $0.proximalAngleDegrees <= tuning.cShapeMaximumJointAngle
                && $0.distalAngleDegrees >= tuning.cShapeMinimumJointAngle
                && $0.distalAngleDegrees <= tuning.cShapeMaximumJointAngle
        }),
        let gap = normalizedDistance(.thumbTip, .indexTip, in: hand),
        gap >= tuning.cShapeMinimumThumbIndexGap,
        gap <= tuning.cShapeMaximumThumbIndexGap,
        let tipRadii = nonThumbTipRadii(in: hand),
        tipRadii.allSatisfy({ $0 >= tuning.cShapeMinimumTipRadius }) else {
            return nil
        }

        var required = palmRequiredJoints(for: hand)
        for finger in CommandFinger.allCases {
            required.formUnion(finger.fullChain)
        }
        let extensionCenter = (
            tuning.cShapeMinimumExtension + tuning.cShapeMaximumExtension
        ) / 2
        let extensionHalfWidth = (
            tuning.cShapeMaximumExtension - tuning.cShapeMinimumExtension
        ) / 2
        let extensionSupports = fingerMetrics.map {
            1 - min(
                1,
                abs($0.extensionScore - extensionCenter)
                    / max(extensionHalfWidth, 0.000_1)
            )
        }
        let gapCenter = (
            tuning.cShapeMinimumThumbIndexGap + tuning.cShapeMaximumThumbIndexGap
        ) / 2
        let gapHalfWidth = (
            tuning.cShapeMaximumThumbIndexGap - tuning.cShapeMinimumThumbIndexGap
        ) / 2
        let gapSupport = 1 - min(
            1,
            abs(gap - gapCenter) / max(gapHalfWidth, 0.000_1)
        )
        let radiusSupport = tipRadii.map {
            ramp(
                $0,
                from: tuning.cShapeMinimumTipRadius,
                to: tuning.cShapeMinimumTipRadius * 1.8
            )
        }.min() ?? 0
        let rawShapeConfidence = (
            [gapSupport, radiusSupport] + extensionSupports
        ).min() ?? 0
        return makeCandidate(
            .cShape,
            // Passing every bounded C constraint is meaningful evidence even
            // near one tolerance edge. Retain margin in the confidence value
            // without turning the accepted band itself into a second,
            // narrower hidden threshold.
            shapeConfidence: 0.60 + 0.40 * rawShapeConfidence,
            required: required,
            hand: hand
        )
    }

    private func recognizeFist(
        hand: TrackedHandSnapshot,
        metrics: PoseMetrics
    ) -> CommandGestureCandidate? {
        let state = FingerState(metrics: metrics, tuning: controlTuning)
        guard state.index == .folded,
              state.middle == .folded,
              state.ring == .folded,
              state.little == .folded,
              state.thumb != .extended,
              let radii = nonThumbTipRadii(in: hand),
              radii.filter({ $0 <= tuning.fistMaximumTipRadius }).count >= 3 else {
            return nil
        }

        var required = palmRequiredJoints(for: hand)
        for finger in CommandFinger.allCases {
            required.formUnion(finger.fullChain)
        }
        let foldedSupports = CommandFinger.nonThumb.map {
            foldedSupport(metrics[$0].extensionScore)
        }
        let radiusSupports = radii.sorted().prefix(3).map {
            1 - ramp(
                $0,
                from: tuning.fistMaximumTipRadius * 0.55,
                to: tuning.fistMaximumTipRadius
            )
        }
        return makeCandidate(
            .fist,
            shapeConfidence: (foldedSupports + radiusSupports).min() ?? 0,
            required: required,
            hand: hand
        )
    }

    private func makeCandidate(
        _ gesture: CommandGesture,
        shapeConfidence: Double,
        required: Set<LandmarkName>,
        hand: TrackedHandSnapshot
    ) -> CommandGestureCandidate? {
        guard let jointConfidence = requiredConfidence(required, in: hand),
              hand.confidence.isFinite else { return nil }
        let confidence = min(
            shapeConfidence.finiteClamped(to: 0 ... 1),
            jointConfidence,
            hand.confidence.finiteClamped(to: 0 ... 1)
        )
        guard confidence >= tuning.minimumGestureConfidence else { return nil }
        return CommandGestureCandidate(
            gesture: gesture,
            confidence: confidence,
            requiredJointConfidence: jointConfidence
        )
    }

    private func isUsable(_ hand: TrackedHandSnapshot) -> Bool {
        hand.associationCertain
            && hand.missingDuration <= 0
            && hand.palmWidth.isFinite
            && hand.palmWidth >= 0.02
            && hand.palmWidth <= 0.80
            && hand.confidence.isFinite
            && hand.confidence >= controlTuning.minimumLandmarkConfidence
    }

    private func palmRequiredJoints(
        for hand: TrackedHandSnapshot
    ) -> Set<LandmarkName> {
        var result: Set<LandmarkName> = [.wrist]
        switch hand.palmScaleSource {
        case .indexToLittleMCP:
            result.formUnion([.indexMCP, .littleMCP])
        case .wristToMiddleMCP:
            result.insert(.middleMCP)
        case .unavailable:
            break
        }
        return result
    }

    private func requiredConfidence(
        _ required: Set<LandmarkName>,
        in hand: TrackedHandSnapshot
    ) -> Double? {
        var values: [Double] = []
        values.reserveCapacity(required.count)
        for name in required {
            guard let raw = hand.rawLandmarks[name],
                  raw.confidence.isFinite,
                  raw.confidence >= controlTuning.minimumLandmarkConfidence,
                  let filtered = hand.filteredLandmarks[name],
                  filtered.position.x.isFinite,
                  filtered.position.y.isFinite else {
                return nil
            }
            values.append(raw.confidence)
        }
        return values.min()
    }

    private func position(
        _ name: LandmarkName,
        in hand: TrackedHandSnapshot
    ) -> Point2D? {
        guard let raw = hand.rawLandmarks[name],
              raw.confidence.isFinite,
              raw.confidence >= controlTuning.minimumLandmarkConfidence,
              let filtered = hand.filteredLandmarks[name],
              filtered.position.x.isFinite,
              filtered.position.y.isFinite else {
            return nil
        }
        return filtered.position
    }

    private func normalizedDistance(
        _ lhs: LandmarkName,
        _ rhs: LandmarkName,
        in hand: TrackedHandSnapshot
    ) -> Double? {
        guard let a = position(lhs, in: hand),
              let b = position(rhs, in: hand),
              hand.palmWidth > 0 else { return nil }
        let value = a.distance(to: b) / hand.palmWidth
        return value.isFinite ? value : nil
    }

    private func nonThumbTipRadii(
        in hand: TrackedHandSnapshot
    ) -> [Double]? {
        let anchors: [LandmarkName] = [
            .wrist, .indexMCP, .middleMCP, .ringMCP, .littleMCP
        ]
        let points = anchors.compactMap { position($0, in: hand) }
        guard points.count == anchors.count, hand.palmWidth > 0 else {
            return nil
        }
        let center = points.reduce(.zero, +) / Double(points.count)
        let tips: [LandmarkName] = [
            .indexTip, .middleTip, .ringTip, .littleTip
        ]
        let radii = tips.compactMap { name -> Double? in
            guard let tip = position(name, in: hand) else { return nil }
            return tip.distance(to: center) / hand.palmWidth
        }
        return radii.count == tips.count && radii.allSatisfy { $0.isFinite }
            ? radii
            : nil
    }

    private func extensionSupport(_ score: Double) -> Double {
        ramp(score, from: controlTuning.poseEnterScore, to: 1)
    }

    private func foldedSupport(_ score: Double) -> Double {
        let folded = min(0.30, controlTuning.foldedMaximumScore)
        guard score <= folded else { return 0 }
        return 1 - ramp(score, from: 0, to: max(folded, 0.000_1))
    }

    private func ramp(_ value: Double, from: Double, to: Double) -> Double {
        guard value.isFinite, from.isFinite, to.isFinite, to > from else {
            return 0
        }
        return ((value - from) / (to - from)).finiteClamped(to: 0 ... 1)
    }
}

private enum CommandFinger: CaseIterable {
    case thumb
    case index
    case middle
    case ring
    case little

    static let nonThumb: [Self] = [.index, .middle, .ring, .little]

    var proximalChain: Set<LandmarkName> {
        switch self {
        case .thumb:
            return [.thumbCMC, .thumbMP, .thumbIP]
        case .index:
            return [.indexMCP, .indexPIP, .indexDIP]
        case .middle:
            return [.middleMCP, .middlePIP, .middleDIP]
        case .ring:
            return [.ringMCP, .ringPIP, .ringDIP]
        case .little:
            return [.littleMCP, .littlePIP, .littleDIP]
        }
    }

    var fullChain: Set<LandmarkName> {
        var result = proximalChain
        switch self {
        case .thumb: result.insert(.thumbTip)
        case .index: result.insert(.indexTip)
        case .middle: result.insert(.middleTip)
        case .ring: result.insert(.ringTip)
        case .little: result.insert(.littleTip)
        }
        return result
    }
}

private enum ExtensionState {
    case extended
    case folded
    case ambiguous
}

private struct FingerState {
    var thumb: ExtensionState
    var index: ExtensionState
    var middle: ExtensionState
    var ring: ExtensionState
    var little: ExtensionState

    init(metrics: PoseMetrics, tuning: GestureTuning) {
        let extended = tuning.poseEnterScore
        let folded = min(0.30, tuning.foldedMaximumScore)
        func state(_ score: Double) -> ExtensionState {
            guard score.isFinite else { return .ambiguous }
            if score >= extended { return .extended }
            if score <= folded { return .folded }
            return .ambiguous
        }
        thumb = state(metrics.thumb.extensionScore)
        index = state(metrics.index.extensionScore)
        middle = state(metrics.middle.extensionScore)
        ring = state(metrics.ring.extensionScore)
        little = state(metrics.little.extensionScore)
    }
}

private extension PoseMetrics {
    subscript(_ finger: CommandFinger) -> FingerMetrics {
        switch finger {
        case .thumb: thumb
        case .index: index
        case .middle: middle
        case .ring: ring
        case .little: little
        }
    }
}

private extension Double {
    func finiteClamped(to range: ClosedRange<Double>) -> Double {
        isFinite ? min(max(self, range.lowerBound), range.upperBound) : range.lowerBound
    }
}
