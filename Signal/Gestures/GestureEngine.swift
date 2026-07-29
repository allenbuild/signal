import Foundation

/// Deterministic, framework-independent, mutually-exclusive gesture state machine.
///
/// Callers serialize access. Time comes only from tracking snapshots and
/// `advance(to:)`; the engine never schedules hidden work or reads wall time.
public final class GestureEngine: GestureResetting {
    private let classifier = HandPoseClassifier()
    private var tuning: GestureTuning

    private var lastProcessedTimestamp: MonotonicTimestamp?
    private var lastAcceptedFrameTimestamp: MonotonicTimestamp?
    private var hadReliableContext = false
    private var trackingLossEmitted = false
    private var trackingWasUnavailable = false

    private var interaction: InteractionState = .rest
    private var pinchTrackers: [HandTrackID: PinchTracker] = [:]

    public init(tuning: GestureTuning = .safeDefaults) {
        self.tuning = tuning.validated()
    }

    public var currentTuning: GestureTuning { tuning }

    public var debugStateDescription: String {
        "gesture=\(interaction.description) loss=\(trackingLossEmitted ? "emitted" : "clear")"
    }

    public func update(tuning: GestureTuning) {
        let validated = tuning.validated()
        guard validated != self.tuning else { return }
        self.tuning = validated
        clearRuntimeState(clearTimestamps: true)
    }

    public func process(_ snapshot: TrackingSnapshot) -> GestureFrameResult {
        let timestamp = snapshot.timestamp
        guard timestamp.rawValue.isFinite,
              lastProcessedTimestamp.map({ timestamp > $0 }) ?? true else {
            return GestureFrameResult(
                poses: [],
                events: [],
                stateDescription: "invalidTimestamp \(debugStateDescription)",
                zoomEpisode: interaction.zoomDiagnostic,
                diagnostics: GestureDiagnostics(
                    degradationReason: .invalidTimestamp,
                    pointerSuppressionReason: .trackingUnavailable
                )
            )
        }
        lastProcessedTimestamp = timestamp
        // Every valid processed snapshot proves producer liveness, even when
        // it contains no usable hand. `advance(to:)` must measure a genuine
        // no-frame gap from this timestamp, not from the last recognized hand.
        lastAcceptedFrameTimestamp = timestamp

        let analyzed = snapshot.hands
            .sorted { $0.id < $1.id }
            .map { hand in
                let activePinchEpisode = isPinchEpisodeActive(for: hand.id)
                return AnalyzedHand(
                    hand: hand,
                    metrics: classifier.classify(
                        hand,
                        tuning: tuning,
                        activePinchEpisode: activePinchEpisode
                    ),
                    activePinchEpisode: activePinchEpisode
                )
            }
        let poses = analyzed.map {
            HandPoseSnapshot(handID: $0.hand.id, timestamp: timestamp, metrics: $0.metrics)
        }
        let globallyReliable = analyzed.filter(\.isGloballyReliable)
        let currentObservedHandCount = analyzed.filter { $0.hand.missingDuration <= 0 }.count

        if snapshot.quality == .absent
            || snapshot.degradationReason?.isGlobalTrackingFailure == true
            || globallyReliable.isEmpty {
            let events = handleTrackingUnavailable(at: timestamp)
            let reason = snapshot.degradationReason ?? .noHandDetected
            return GestureFrameResult(
                poses: poses,
                events: events,
                stateDescription: "trackingUnavailable \(debugStateDescription)",
                zoomEpisode: interaction.zoomDiagnostic,
                diagnostics: GestureDiagnostics(
                    degradationReason: reason,
                    middleThumbNormalizedDistance: analyzed.first?.metrics.pinchRatio,
                    pointerSuppressionReason: .trackingUnavailable,
                    fistRejectionReason: analyzed.first.flatMap(fistRejectionReason)
                )
            )
        }

        hadReliableContext = true
        trackingLossEmitted = false
        if trackingWasUnavailable {
            interaction = .rest
            pinchTrackers.removeAll(keepingCapacity: true)
            trackingWasUnavailable = false
        }

        var output: GestureOutput
        if snapshot.degradationReason == .staleFrame
            || snapshot.degradationReason == .poseAmbiguity
            || (snapshot.quality == .degraded && snapshot.degradationReason == nil) {
            freezeForLocalDegradation(at: timestamp)
            output = GestureOutput(
                degradationReason: snapshot.degradationReason ?? .poseAmbiguity
            )
        } else if globallyReliable.count >= 2 {
            // Version 1.1 deliberately has no two-hand gesture. Never select a
            // primary hand implicitly: multiple current hands are a neutral
            // clutch until exactly one reliable hand remains.
            interaction = .rest
            pinchTrackers.removeAll(keepingCapacity: true)
            output = GestureOutput(degradationReason: .poseAmbiguity)
        } else if globallyReliable.count == 1, let hand = globallyReliable.first {
            output = handleOneHand(
                hand,
                observedHandCount: currentObservedHandCount,
                at: timestamp
            )
        } else {
            interaction = .rest
            pinchTrackers.removeAll(keepingCapacity: true)
            output = GestureOutput(degradationReason: .poseAmbiguity)
        }

        let recognizedPose: PoseKind? = globallyReliable.count == 1
            ? globallyReliable.first?.metrics.pose
            : (globallyReliable.allSatisfy { $0.metrics.pose == .pinch } ? .pinch : nil)
        output.pointerSuppressionReason = pointerSuppressionReason(
            for: globallyReliable,
            events: output.events
        )
        let middleThumbDistance = globallyReliable
            .compactMap(\.metrics.pinchRatio)
            .min()
        let fistReason = globallyReliable.count == 1
            ? globallyReliable.first.flatMap(fistRejectionReason)
            : nil
        let diagnostics = makeDiagnostics(
            recognizedPose: recognizedPose,
            middleThumbNormalizedDistance: middleThumbDistance,
            pointerSuppressionReason: output.pointerSuppressionReason,
            fistRejectionReason: fistReason,
            output: output,
            snapshotReason: snapshot.degradationReason,
            timestamp: timestamp
        )
        return GestureFrameResult(
            poses: poses,
            events: output.events,
            stateDescription: debugStateDescription,
            zoomEpisode: interaction.zoomDiagnostic,
            diagnostics: diagnostics
        )
    }

    public func advance(to timestamp: MonotonicTimestamp) -> [GestureEvent] {
        guard timestamp.rawValue.isFinite,
              lastProcessedTimestamp.map({ timestamp > $0 }) ?? true else { return [] }
        lastProcessedTimestamp = timestamp

        let needsFence = trackingWasUnavailable || !interaction.isRest
        if needsFence,
           let lastAcceptedFrameTimestamp,
           hasElapsed(
               timestamp,
               since: lastAcceptedFrameTimestamp,
               duration: tuning.trackingLossGraceDuration
           ) {
            return emitTrackingLostIfNeeded()
        }
        return []
    }

    @discardableResult
    public func reset(reason: GestureResetReason) -> [GestureEvent] {
        let events = reason == .trackingLost ? emitTrackingLostIfNeeded() : []
        clearRuntimeState(clearTimestamps: true)
        trackingLossEmitted = reason == .trackingLost
        return events
    }

    private func handleTrackingUnavailable(at timestamp: MonotonicTimestamp) -> [GestureEvent] {
        trackingWasUnavailable = true
        interaction = .rest
        pinchTrackers.removeAll(keepingCapacity: true)
        // A fresh frame with no usable hand proves the camera/recognition code
        // is still alive. It is a neutral clutch, never a terminal stop. Only
        // advance(to:) after a true no-frame gap emits trackingLost.
        return []
    }

    private func emitTrackingLostIfNeeded() -> [GestureEvent] {
        guard hadReliableContext, !trackingLossEmitted else { return [] }
        trackingLossEmitted = true
        hadReliableContext = false
        interaction = .rest
        pinchTrackers.removeAll(keepingCapacity: true)
        return [.trackingLost]
    }

    // MARK: - One-hand pinch and pointer

    private func handleOneHand(
        _ analyzed: AnalyzedHand,
        observedHandCount: Int,
        at timestamp: MonotonicTimestamp
    ) -> GestureOutput {
        let hand = analyzed.hand
        if observedHandCount >= 2 {
            interaction = .rest
            pinchTrackers.removeAll(keepingCapacity: true)
            return GestureOutput(degradationReason: .poseAmbiguity)
        }

        if let owner = interaction.pinchOwner, owner != hand.id {
            interaction = .rest
            pinchTrackers.removeAll(keepingCapacity: true)
        }

        let pinchConfidence = requiredConfidence(for: pinchRequiredJoints(in: hand), in: hand)
        let ownsPinch = interaction.pinchOwner == hand.id
        if ownsPinch,
           (pinchConfidence ?? -.infinity) < tuning.minimumLandmarkConfidence {
            suspendPinchInteraction()
            return GestureOutput(
                requiredJointConfidence: pinchConfidence,
                degradationReason: .lowRequiredJointConfidence
            )
        }

        if ownsPinch,
           (pinchConfidence ?? -.infinity) >= tuning.minimumLandmarkConfidence,
           let ratio = analyzed.metrics.pinchRatio,
           let anchor = filteredPosition(.wrist, in: hand) {
            // Once a close owns the interaction, process the open threshold
            // even if the release has already left the classifier's narrower
            // pinch-intent pose. A wide, fast release must still complete the
            // physical pinch and produce its one click outcome.
            return handlePinch(
                analyzed,
                ratio: ratio,
                anchor: anchor,
                confidence: pinchConfidence,
                at: timestamp
            )
        }

        if (pinchConfidence ?? -.infinity) >= tuning.minimumLandmarkConfidence,
           isPinchCapable(analyzed.metrics),
           let ratio = analyzed.metrics.pinchRatio,
           let anchor = filteredPosition(.wrist, in: hand) {
            return handlePinch(
                analyzed,
                ratio: ratio,
                anchor: anchor,
                confidence: pinchConfidence,
                at: timestamp
            )
        }

        if ownsPinch {
            interaction = .rest
            pinchTrackers[hand.id] = PinchTracker()
            return GestureOutput(
                requiredJointConfidence: pinchConfidence,
                degradationReason: .poseAmbiguity
            )
        }

        // Rearm the close/open hysteresis while the hand is visibly open.
        // This does not suppress pointer output: only ratios at or below the
        // pinch-intent boundary are routed through handlePinch. Preserving the
        // open phase is what lets the first direct pointer-to-pinch tap close.
        if (pinchConfidence ?? -.infinity) >= tuning.minimumLandmarkConfidence,
           let ratio = analyzed.metrics.pinchRatio {
            var tracker = pinchTrackers[hand.id] ?? PinchTracker()
            _ = tracker.update(ratio: ratio, timestamp: timestamp, tuning: tuning)
            pinchTrackers = [hand.id: tracker]
        } else {
            pinchTrackers[hand.id] = PinchTracker()
        }
        return handlePointer(analyzed, at: timestamp)
    }

    private func handlePinch(
        _ analyzed: AnalyzedHand,
        ratio: Double,
        anchor: Point2D,
        confidence: Double?,
        at timestamp: MonotonicTimestamp
    ) -> GestureOutput {
        let hand = analyzed.hand
        var tracker = pinchTrackers[hand.id] ?? PinchTracker()
        let transition = tracker.update(ratio: ratio, timestamp: timestamp, tuning: tuning)
        pinchTrackers = [hand.id: tracker]

        switch transition {
        case .closed:
            interaction = .pinchCandidate(PinchCandidate(
                handID: hand.id,
                startTime: timestamp,
                startPoint: anchor,
                startScale: hand.palmWidth,
                lastPoint: anchor,
                lastScale: hand.palmWidth,
                maximumDisplacement: 0,
                verticalDisplacement: 0,
                horizontalDisplacement: 0,
                clickEligible: true,
                needsReanchor: false,
                stabilizationFramesRemaining: tuning.scrollStabilizationFrames
            ))
            return GestureOutput(requiredJointConfidence: confidence)

        case .opened:
            defer { interaction = .rest }
            guard case let .pinchCandidate(state) = interaction,
                  state.handID == hand.id else {
                return GestureOutput(requiredJointConfidence: confidence)
            }
            let duration = timestamp.duration(since: state.startTime)
            let releaseDistance = anchor.distance(to: state.startPoint) / max(state.startScale, 1e-12)
            let maximum = max(state.maximumDisplacement, releaseDistance)
            let quick = duration <= tuning.quickPinchMaximumDuration + timeEpsilon
            let still = maximum < tuning.pinchScrollActivationDisplacement
            let click = state.clickEligible && quick && still
            return GestureOutput(
                events: click ? [.leftClick] : [],
                requiredJointConfidence: confidence
            )

        case .none:
            guard tracker.isClosed else {
                interaction = .rest
                return GestureOutput(requiredJointConfidence: confidence)
            }
            switch interaction {
            case let .pinchCandidate(stored) where stored.handID == hand.id:
                return continuePinchCandidate(
                    stored,
                    anchor: anchor,
                    scale: hand.palmWidth,
                    confidence: confidence,
                    at: timestamp
                )
            case let .scroll(stored) where stored.handID == hand.id:
                return continuePinchScroll(
                    stored,
                    anchor: anchor,
                    scale: hand.palmWidth,
                    confidence: confidence
                )
            case let .horizontalZoom(stored) where stored.handID == hand.id:
                return continuePinchZoom(
                    stored,
                    anchor: anchor,
                    scale: hand.palmWidth,
                    confidence: confidence
                )
            default:
                return GestureOutput(requiredJointConfidence: confidence)
            }
        }
    }

    private func continuePinchCandidate(
        _ stored: PinchCandidate,
        anchor: Point2D,
        scale: Double,
        confidence: Double?,
        at timestamp: MonotonicTimestamp
    ) -> GestureOutput {
        var state = stored
        guard anchor.isFinite, scale.isFinite, scale > 0 else {
            state.needsReanchor = true
            state.clickEligible = false
            interaction = .pinchCandidate(state)
            return GestureOutput(
                requiredJointConfidence: confidence,
                degradationReason: .invalidPalmScale
            )
        }
        if state.needsReanchor {
            state.startTime = timestamp
            state.startPoint = anchor
            state.startScale = scale
            state.lastPoint = anchor
            state.lastScale = scale
            state.maximumDisplacement = 0
            state.verticalDisplacement = 0
            state.horizontalDisplacement = 0
            state.needsReanchor = false
            state.clickEligible = false
            state.stabilizationFramesRemaining = tuning.scrollStabilizationFrames
            interaction = .pinchCandidate(state)
            return GestureOutput(requiredJointConfidence: confidence)
        }

        // Thumb/index closure can perturb distal joints for a few frames even
        // though the hand itself is still. Refresh the wrist origin for exactly
        // the configured number of reliable post-close frames. A release during
        // this phase remains a valid quick click.
        if state.stabilizationFramesRemaining > 0 {
            state.startPoint = anchor
            state.startScale = scale
            state.lastPoint = anchor
            state.lastScale = scale
            state.maximumDisplacement = 0
            state.verticalDisplacement = 0
            state.horizontalDisplacement = 0
            state.stabilizationFramesRemaining -= 1
            interaction = .pinchCandidate(state)
            return GestureOutput(requiredJointConfidence: confidence)
        }

        let denominator = sqrt(max(state.lastScale * scale, 1e-12))
        let frameStep = (anchor - state.lastPoint) / denominator
        let startDenominator = sqrt(max(state.startScale * scale, 1e-12))
        let fromStart = (anchor - state.startPoint) / startDenominator
        state.lastPoint = anchor
        state.lastScale = scale
        guard frameStep.isFinite, fromStart.isFinite,
              frameStep.magnitude <= tuning.normalizedDiscontinuityStep else {
            state.startTime = timestamp
            state.startPoint = anchor
            state.startScale = scale
            state.lastPoint = anchor
            state.lastScale = scale
            state.maximumDisplacement = 0
            state.verticalDisplacement = 0
            state.horizontalDisplacement = 0
            state.needsReanchor = false
            state.clickEligible = false
            state.stabilizationFramesRemaining = tuning.scrollStabilizationFrames
            interaction = .pinchCandidate(state)
            return GestureOutput(
                requiredJointConfidence: confidence,
                degradationReason: .poseAmbiguity
            )
        }

        state.maximumDisplacement = max(state.maximumDisplacement, fromStart.magnitude)
        state.verticalDisplacement = fromStart.y
        state.horizontalDisplacement = fromStart.x
        let duration = timestamp.duration(since: state.startTime)
        if duration > tuning.quickPinchMaximumDuration + timeEpsilon
            || state.maximumDisplacement >= tuning.pinchScrollActivationDisplacement {
            state.clickEligible = false
        }

        let threshold = tuning.pinchMotionActivationDisplacement
        let verticalActivation = abs(fromStart.y) + dimensionlessComparisonEpsilon >= threshold
            && abs(fromStart.y) + dimensionlessComparisonEpsilon
                >= tuning.scrollAxisLockRatio * abs(fromStart.x)
        let horizontalActivation = abs(fromStart.x) + dimensionlessComparisonEpsilon >= threshold
            && abs(fromStart.x) + dimensionlessComparisonEpsilon
                >= tuning.scrollAxisLockRatio * abs(fromStart.y)
        guard verticalActivation || horizontalActivation else {
            interaction = .pinchCandidate(state)
            return GestureOutput(requiredJointConfidence: confidence)
        }

        if verticalActivation {
            let sign = fromStart.y >= 0 ? 1.0 : -1.0
            let initial = fromStart.y - sign * threshold
            let scroll = VerticalScrollInteraction(
                handID: state.handID,
                startTime: state.startTime,
                tracker: RelativeTracker(point: anchor, scale: scale),
                currentAnchor: anchor,
                displacement: fromStart.y,
                needsReanchor: false
            )
            interaction = .scroll(scroll)
            let delta = shapeScroll(initial)
            return GestureOutput(
                events: delta.map { [.scroll(dx: 0, dy: $0)] } ?? [],
                scrollDelta: delta,
                rawScrollVerticalDelta: frameStep.y,
                requiredJointConfidence: confidence
            )
        }

        let sign = fromStart.x >= 0 ? 1.0 : -1.0
        let initial = fromStart.x - sign * threshold
        let zoom = HorizontalZoomInteraction(
            handID: state.handID,
            startTime: state.startTime,
            tracker: RelativeTracker(point: anchor, scale: scale),
            currentAnchor: anchor,
            displacement: fromStart.x,
            needsReanchor: false
        )
        interaction = .horizontalZoom(zoom)
        let delta = shapeHorizontalZoom(initial)
        return GestureOutput(
            events: delta.map { [.zoom(delta: $0)] } ?? [],
            requiredJointConfidence: confidence,
            zoomDistance: fromStart.x,
            zoomDelta: delta
        )
    }

    private func continuePinchScroll(
        _ stored: VerticalScrollInteraction,
        anchor: Point2D,
        scale: Double,
        confidence: Double?
    ) -> GestureOutput {
        var state = stored
        if state.needsReanchor {
            state.tracker = RelativeTracker(point: anchor, scale: scale)
            state.currentAnchor = anchor
            state.needsReanchor = false
            interaction = .scroll(state)
            return GestureOutput(requiredJointConfidence: confidence)
        }
        guard let step = state.tracker.step(
            point: anchor,
            scale: scale,
            discontinuityLimit: tuning.normalizedDiscontinuityStep
        ) else {
            state.currentAnchor = anchor
            interaction = .scroll(state)
            return GestureOutput(requiredJointConfidence: confidence)
        }
        state.currentAnchor = anchor
        state.displacement += step.y
        interaction = .scroll(state)
        let delta = shapeScroll(step.y)
        return GestureOutput(
            events: delta.map { [.scroll(dx: 0, dy: $0)] } ?? [],
            scrollDelta: delta,
            rawScrollVerticalDelta: step.y,
            requiredJointConfidence: confidence
        )
    }

    private func continuePinchZoom(
        _ stored: HorizontalZoomInteraction,
        anchor: Point2D,
        scale: Double,
        confidence: Double?
    ) -> GestureOutput {
        var state = stored
        if state.needsReanchor {
            state.tracker = RelativeTracker(point: anchor, scale: scale)
            state.currentAnchor = anchor
            state.needsReanchor = false
            interaction = .horizontalZoom(state)
            return GestureOutput(
                requiredJointConfidence: confidence,
                zoomDistance: state.displacement
            )
        }
        guard let step = state.tracker.step(
            point: anchor,
            scale: scale,
            discontinuityLimit: tuning.normalizedDiscontinuityStep
        ) else {
            state.currentAnchor = anchor
            interaction = .horizontalZoom(state)
            return GestureOutput(
                requiredJointConfidence: confidence,
                zoomDistance: state.displacement
            )
        }
        state.currentAnchor = anchor
        state.displacement += step.x
        interaction = .horizontalZoom(state)
        let delta = shapeHorizontalZoom(step.x)
        return GestureOutput(
            events: delta.map { [.zoom(delta: $0)] } ?? [],
            requiredJointConfidence: confidence,
            zoomDistance: state.displacement,
            zoomDelta: delta
        )
    }

    private func suspendPinchInteraction() {
        switch interaction {
        case let .pinchCandidate(stored):
            var state = stored
            state.needsReanchor = true
            state.clickEligible = false
            interaction = .pinchCandidate(state)
        case let .scroll(stored):
            var state = stored
            state.needsReanchor = true
            interaction = .scroll(state)
        case let .horizontalZoom(stored):
            var state = stored
            state.needsReanchor = true
            interaction = .horizontalZoom(state)
        default:
            interaction = .rest
        }
    }

    private func freezeForLocalDegradation(at timestamp: MonotonicTimestamp) {
        switch interaction {
        case let .pointer(state):
            interaction = .pointerSuspended(PointerSuspension(
                handID: state.handID,
                since: timestamp
            ))
        case .pinchCandidate, .scroll, .horizontalZoom:
            suspendPinchInteraction()
        case .pointerCandidate:
            // Entry stability must be continuous; degraded time cannot count
            // toward the pose hold interval.
            interaction = .rest
        case .rest, .pointerSuspended:
            break
        }
    }

    private func handlePointer(
        _ analyzed: AnalyzedHand,
        at timestamp: MonotonicTimestamp
    ) -> GestureOutput {
        let hand = analyzed.hand
        let confidence = requiredConfidence(for: pointerRequiredJoints, in: hand)
        let hasRequiredConfidence = (confidence ?? -.infinity) >= tuning.minimumLandmarkConfidence
        let supportsEntry = hasRequiredConfidence && supportsPointer(analyzed.metrics, entering: true)
        let supportsExit = hasRequiredConfidence && supportsPointer(analyzed.metrics, entering: false)

        switch interaction {
        case .rest:
            if supportsEntry {
                interaction = .pointerCandidate(PointerCandidate(handID: hand.id, since: timestamp))
            }

        case let .pointerCandidate(candidate):
            guard candidate.handID == hand.id, supportsEntry else {
                interaction = supportsEntry
                    ? .pointerCandidate(PointerCandidate(handID: hand.id, since: timestamp))
                    : .rest
                break
            }
            if hasElapsed(timestamp, since: candidate.since, duration: tuning.poseStabilityDuration),
               let point = filteredPosition(.indexTip, in: hand) {
                interaction = .pointer(PointerInteraction(
                    handID: hand.id,
                    tracker: RelativeTracker(point: point, scale: hand.palmWidth),
                    deadZone: VectorDeadZone()
                ))
            }

        case let .pointer(stored):
            guard stored.handID == hand.id, supportsExit,
                  let point = filteredPosition(.indexTip, in: hand) else {
                if !hasRequiredConfidence, stored.handID == hand.id {
                    interaction = .pointerSuspended(PointerSuspension(
                        handID: hand.id,
                        since: timestamp
                    ))
                } else {
                    interaction = supportsEntry
                        ? .pointerCandidate(PointerCandidate(handID: hand.id, since: timestamp))
                        : .rest
                }
                break
            }
            var state = stored
            guard let step = state.tracker.step(
                point: point,
                scale: hand.palmWidth,
                discontinuityLimit: tuning.normalizedDiscontinuityStep
            ) else {
                state.deadZone.reset()
                interaction = .pointer(state)
                break
            }
            guard let excess = state.deadZone.consume(step, threshold: tuning.pointerDeadZone),
                  let output = shapeVector(
                    excess,
                    sensitivity: tuning.pointerSensitivity,
                    acceleration: tuning.pointerAcceleration,
                    maximum: tuning.pointerMaximumDelta
                  ) else {
                interaction = .pointer(state)
                break
            }
            interaction = .pointer(state)
            return GestureOutput(
                events: [.pointerDelta(dx: output.x, dy: output.y)],
                requiredJointConfidence: confidence
            )

        case let .pointerSuspended(suspension):
            guard suspension.handID == hand.id else {
                interaction = supportsEntry
                    ? .pointerCandidate(PointerCandidate(handID: hand.id, since: timestamp))
                    : .rest
                break
            }
            if supportsExit,
               timestamp.duration(since: suspension.since)
                    <= tuning.poseExitGraceDuration + timeEpsilon,
               let point = filteredPosition(.indexTip, in: hand) {
                interaction = .pointer(PointerInteraction(
                    handID: hand.id,
                    tracker: RelativeTracker(point: point, scale: hand.palmWidth),
                    deadZone: VectorDeadZone()
                ))
            } else if hasElapsed(
                timestamp,
                since: suspension.since,
                duration: tuning.poseExitGraceDuration
            ) {
                interaction = supportsEntry
                    ? .pointerCandidate(PointerCandidate(handID: hand.id, since: timestamp))
                    : .rest
            }

        case .pinchCandidate, .scroll, .horizontalZoom:
            interaction = supportsEntry
                ? .pointerCandidate(PointerCandidate(handID: hand.id, since: timestamp))
                : .rest
        }

        return GestureOutput(
            requiredJointConfidence: confidence,
            degradationReason: hasRequiredConfidence ? nil : .lowRequiredJointConfidence
        )
    }

    // MARK: - Diagnostics and geometry

    private func makeDiagnostics(
        recognizedPose: PoseKind?,
        middleThumbNormalizedDistance: Double?,
        pointerSuppressionReason: PointerSuppressionReason?,
        fistRejectionReason: FistRejectionReason?,
        output: GestureOutput,
        snapshotReason: TrackingDegradationReason?,
        timestamp: MonotonicTimestamp
    ) -> GestureDiagnostics {
        let pinchDuration: TimeInterval?
        let scrollDisplacement: Double?
        let scrollAnchor: Point2D?
        let scrollVerticalDelta: Double?
        switch interaction {
        case let .pinchCandidate(state):
            pinchDuration = max(0, timestamp.duration(since: state.startTime))
            scrollDisplacement = state.verticalDisplacement
            scrollAnchor = state.lastPoint
            scrollVerticalDelta = output.rawScrollVerticalDelta
        case let .scroll(state):
            pinchDuration = max(0, timestamp.duration(since: state.startTime))
            scrollDisplacement = state.displacement
            scrollAnchor = state.currentAnchor
            scrollVerticalDelta = output.rawScrollVerticalDelta
        case let .horizontalZoom(state):
            pinchDuration = max(0, timestamp.duration(since: state.startTime))
            scrollDisplacement = nil
            scrollAnchor = state.currentAnchor
            scrollVerticalDelta = nil
        default:
            pinchDuration = nil
            scrollDisplacement = nil
            scrollAnchor = nil
            scrollVerticalDelta = nil
        }
        return GestureDiagnostics(
            recognizedPose: recognizedPose,
            pendingClick: interaction.hasPendingClick,
            activeGesture: interaction.activeDiagnostic,
            pinchDuration: pinchDuration,
            scrollDisplacement: scrollDisplacement,
            scrollDelta: output.scrollDelta,
            requiredJointConfidence: output.requiredJointConfidence,
            degradationReason: output.degradationReason ?? snapshotReason,
            zoomDistance: output.zoomDistance,
            zoomDelta: output.zoomDelta,
            middleThumbNormalizedDistance: middleThumbNormalizedDistance,
            pointerSuppressionReason: pointerSuppressionReason,
            scrollAnchor: scrollAnchor,
            scrollVerticalDelta: scrollVerticalDelta,
            fistRejectionReason: fistRejectionReason
        )
    }

    private func supportsPointer(_ metrics: PoseMetrics, entering: Bool) -> Bool {
        let extended = entering ? tuning.poseEnterScore : tuning.poseExitScore
        let folded = entering ? tuning.foldedMaximumScore : tuning.poseExitScore
        return metrics.index.extensionScore >= extended
            && metrics.middle.extensionScore <= folded
            && metrics.ring.extensionScore <= folded
            && metrics.little.extensionScore <= folded
    }

    private func isPinchCapable(_ metrics: PoseMetrics) -> Bool {
        metrics.pose == .pinch
            && (metrics.pinchRatio.map { $0 <= pinchIntentMaximum } ?? false)
    }

    private func requiredConfidence(
        for names: [LandmarkName],
        in hand: TrackedHandSnapshot
    ) -> Double? {
        var minimum = Double.infinity
        for name in names {
            guard let raw = hand.rawLandmarks[name], raw.confidence.isFinite,
                  let filtered = hand.filteredLandmarks[name], filtered.position.isFinite else {
                return nil
            }
            minimum = min(minimum, raw.confidence)
        }
        return minimum.isFinite ? minimum : nil
    }

    private func filteredPosition(
        _ name: LandmarkName,
        in hand: TrackedHandSnapshot
    ) -> Point2D? {
        guard let raw = hand.rawLandmarks[name], raw.confidence.isFinite,
              raw.confidence >= tuning.minimumLandmarkConfidence,
              let point = hand.filteredLandmarks[name]?.position,
              point.isFinite else { return nil }
        return point
    }

    private func shapeScroll(_ value: Double) -> Double? {
        guard value.isFinite, value != 0 else { return nil }
        let shaped = value * tuning.scrollSensitivityY
            * (1 + tuning.scrollAcceleration * abs(value))
        let bounded = shaped.clamped(to: -tuning.scrollMaximumDelta ... tuning.scrollMaximumDelta)
        return bounded.isFinite && bounded != 0 ? bounded : nil
    }

    private func shapeHorizontalZoom(_ value: Double) -> Double? {
        guard value.isFinite, value != 0 else { return nil }
        // Keep rightward motion positive so the screen-zoom layer consistently
        // maps it to zoom-in. Bound a single frame to avoid shortcut bursts
        // after a noisy observation.
        let bounded = (value * tuning.zoomSensitivity).clamped(to: -0.25 ... 0.25)
        return bounded.isFinite && bounded != 0 ? bounded : nil
    }

    private func shapeVector(
        _ value: Point2D,
        sensitivity: Double,
        acceleration: Double,
        maximum: Double
    ) -> Point2D? {
        guard value.isFinite, sensitivity.isFinite, acceleration.isFinite,
              maximum.isFinite, maximum > 0 else { return nil }
        let magnitude = value.magnitude
        guard magnitude.isFinite, magnitude > 0 else { return nil }
        let gain = sensitivity * (1 + acceleration * magnitude)
        var result = value * gain
        if result.magnitude > maximum, let direction = result.normalized {
            result = direction * maximum
        }
        return result.isFinite ? result : nil
    }

    private func isPinchEpisodeActive(for handID: HandTrackID) -> Bool {
        pinchTrackers[handID]?.isClosed == true || interaction.pinchOwner == handID
    }

    private func pointerSuppressionReason(
        for hands: [AnalyzedHand],
        events: [GestureEvent]
    ) -> PointerSuppressionReason? {
        if events.contains(where: {
            if case .pointerDelta = $0 { return true }
            return false
        }) {
            return nil
        }
        if hands.count >= 2 { return .multipleHands }
        switch interaction {
        case let .pinchCandidate(state):
            return state.clickEligible ? .pendingClick : .middleThumbPinchCandidate
        case .scroll:
            return .scrolling
        case .horizontalZoom:
            return .horizontalPinchZoom
        case .pointer:
            return nil
        case .rest, .pointerCandidate, .pointerSuspended:
            return hands.first?.metrics.pose == .pinch
                ? .middleThumbPinchCandidate
                : .poseMismatch
        }
    }

    private func fistRejectionReason(_ analyzed: AnalyzedHand) -> FistRejectionReason? {
        if analyzed.activePinchEpisode
            || interaction.pinchOwner == analyzed.hand.id
            || pinchTrackers[analyzed.hand.id]?.isClosed == true {
            return .activePinchEpisode
        }
        if analyzed.metrics.pinchRatio.map({ $0 <= pinchIntentMaximum }) == true {
            return .middleThumbContactLikely
        }
        let confidence = requiredConfidence(for: fistRequiredJoints, in: analyzed.hand)
        guard (confidence ?? -.infinity) >= tuning.minimumLandmarkConfidence else {
            return .insufficientConfidence
        }
        let threshold = min(0.30, tuning.foldedMaximumScore)
        let scores = [
            analyzed.metrics.index.extensionScore,
            analyzed.metrics.middle.extensionScore,
            analyzed.metrics.ring.extensionScore,
            analyzed.metrics.little.extensionScore
        ]
        return scores.allSatisfy { $0 <= threshold }
            ? nil
            : .nonThumbNotCurled
    }

    private func clearRuntimeState(clearTimestamps: Bool) {
        interaction = .rest
        pinchTrackers.removeAll(keepingCapacity: true)
        trackingWasUnavailable = false
        lastAcceptedFrameTimestamp = nil
        hadReliableContext = false
        trackingLossEmitted = false
        if clearTimestamps { lastProcessedTimestamp = nil }
    }

    private var pinchIntentMaximum: Double {
        tuning.pinchIntentRatio
    }

    private var pointerRequiredJoints: [LandmarkName] {
        [.wrist,
         .indexMCP, .indexPIP, .indexDIP, .indexTip,
         .middleMCP, .middlePIP, .middleDIP,
         .ringMCP, .ringPIP, .ringDIP,
         .littleMCP, .littlePIP, .littleDIP]
    }

    private var fistRequiredJoints: [LandmarkName] {
        [.wrist,
         .indexMCP, .indexPIP, .indexDIP, .indexTip,
         .middleMCP, .middlePIP, .middleDIP, .middleTip,
         .ringMCP, .ringPIP, .ringDIP, .ringTip,
         .littleMCP, .littlePIP, .littleDIP, .littleTip]
    }

    private func pinchRequiredJoints(in hand: TrackedHandSnapshot) -> [LandmarkName] {
        var required: [LandmarkName] = [
            .wrist,
            .thumbMP, .thumbIP, .thumbTip,
            .indexMCP, .indexPIP, .indexDIP, .indexTip
        ]
        // The tracker already selected a reliable scale source. Include only
        // that source's remaining palm anchor; unrelated folded-finger tips
        // and thumb CMC are never part of pinch confidence.
        switch hand.palmScaleSource {
        case .indexToLittleMCP:
            required.append(.littleMCP)
        case .wristToMiddleMCP:
            required.append(.middleMCP)
        case .unavailable:
            break
        }
        return required
    }

    private var timeEpsilon: TimeInterval { 1e-9 }
    private var dimensionlessComparisonEpsilon: Double { 1e-9 }

    private func hasElapsed(
        _ current: MonotonicTimestamp,
        since earlier: MonotonicTimestamp,
        duration: TimeInterval
    ) -> Bool {
        current.duration(since: earlier) + timeEpsilon >= duration
    }
}

private struct AnalyzedHand {
    var hand: TrackedHandSnapshot
    var metrics: PoseMetrics
    var activePinchEpisode: Bool

    var isGloballyReliable: Bool {
        hand.associationCertain
            && hand.missingDuration <= 0
            && hand.palmScaleSource != .unavailable
            && hand.palmWidth.isFinite
            && hand.palmWidth >= 0.02
            && hand.palmWidth <= 0.80
    }
}

private struct GestureOutput {
    var events: [GestureEvent] = []
    var scrollDelta: Double?
    var rawScrollVerticalDelta: Double?
    var requiredJointConfidence: Double?
    var degradationReason: TrackingDegradationReason?
    var zoomDistance: Double?
    var zoomDelta: Double?
    var pointerSuppressionReason: PointerSuppressionReason?
}

private enum InteractionState {
    case rest
    case pointerCandidate(PointerCandidate)
    case pointer(PointerInteraction)
    case pointerSuspended(PointerSuspension)
    case pinchCandidate(PinchCandidate)
    case scroll(VerticalScrollInteraction)
    case horizontalZoom(HorizontalZoomInteraction)

    var isRest: Bool {
        if case .rest = self { return true }
        return false
    }

    var pinchOwner: HandTrackID? {
        switch self {
        case let .pinchCandidate(state): state.handID
        case let .scroll(state): state.handID
        case let .horizontalZoom(state): state.handID
        default: nil
        }
    }

    var hasPendingClick: Bool {
        if case let .pinchCandidate(state) = self { return state.clickEligible }
        return false
    }

    var activeDiagnostic: ActiveGestureDiagnostic {
        switch self {
        case .rest, .pointerCandidate, .pointerSuspended: .rest
        case .pointer: .pointer
        case let .pinchCandidate(state): state.clickEligible ? .pendingClick : .rest
        case .scroll: .scroll
        case .horizontalZoom: .zoom
        }
    }

    var zoomDiagnostic: ZoomEpisodeDiagnostic {
        switch self {
        case let .horizontalZoom(state):
            ZoomEpisodeDiagnostic(phase: .active, handIDs: [state.handID])
        default: .inactive
        }
    }

    var description: String {
        switch self {
        case .rest: "rest"
        case let .pointerCandidate(value): "pointerCandidate(\(value.handID.rawValue))"
        case let .pointer(value): "pointer(\(value.handID.rawValue))"
        case let .pointerSuspended(value): "pointerSuspended(\(value.handID.rawValue))"
        case let .pinchCandidate(value): "pendingClick(\(value.handID.rawValue))"
        case let .scroll(value): "scroll(\(value.handID.rawValue))"
        case let .horizontalZoom(value): "horizontalZoom(\(value.handID.rawValue))"
        }
    }
}

private struct PointerCandidate {
    var handID: HandTrackID
    var since: MonotonicTimestamp
}

private struct PointerSuspension {
    var handID: HandTrackID
    var since: MonotonicTimestamp
}

private struct PointerInteraction {
    var handID: HandTrackID
    var tracker: RelativeTracker
    var deadZone: VectorDeadZone
}

private struct PinchCandidate {
    var handID: HandTrackID
    var startTime: MonotonicTimestamp
    var startPoint: Point2D
    var startScale: Double
    var lastPoint: Point2D
    var lastScale: Double
    var maximumDisplacement: Double
    var verticalDisplacement: Double
    var horizontalDisplacement: Double
    var clickEligible: Bool
    var needsReanchor: Bool
    var stabilizationFramesRemaining: Int
}

private struct VerticalScrollInteraction {
    var handID: HandTrackID
    var startTime: MonotonicTimestamp
    var tracker: RelativeTracker
    var currentAnchor: Point2D
    var displacement: Double
    var needsReanchor: Bool
}

private struct HorizontalZoomInteraction {
    var handID: HandTrackID
    var startTime: MonotonicTimestamp
    var tracker: RelativeTracker
    var currentAnchor: Point2D
    var displacement: Double
    var needsReanchor: Bool
}

private struct RelativeTracker {
    private var previousPoint: Point2D
    private var previousScale: Double

    init(point: Point2D, scale: Double) {
        previousPoint = point
        previousScale = scale
    }

    mutating func step(
        point: Point2D,
        scale: Double,
        discontinuityLimit: Double
    ) -> Point2D? {
        guard point.isFinite, scale.isFinite, scale > 0,
              previousPoint.isFinite, previousScale.isFinite, previousScale > 0 else {
            previousPoint = point
            previousScale = scale
            return nil
        }
        let denominator = sqrt(previousScale * scale)
        let value = (point - previousPoint) / denominator
        previousPoint = point
        previousScale = scale
        guard value.isFinite, value.magnitude <= discontinuityLimit else { return nil }
        return value
    }
}

private struct VectorDeadZone {
    private var accumulator = Point2D.zero

    mutating func reset() { accumulator = .zero }

    mutating func consume(_ value: Point2D, threshold: Double) -> Point2D? {
        guard value.isFinite, threshold.isFinite, threshold >= 0 else {
            reset()
            return nil
        }
        accumulator = accumulator + value
        let magnitude = accumulator.magnitude
        guard magnitude - threshold > 1e-12, let direction = accumulator.normalized else {
            return nil
        }
        let output = accumulator - direction * threshold
        accumulator = direction * threshold
        return output.magnitude > 0 ? output : nil
    }
}

private enum PinchTransition {
    case none, closed, opened
}

private struct PinchTracker {
    private enum Phase {
        case blocked(openSince: MonotonicTimestamp?)
        case armedOpen
        case closed
    }

    private var phase: Phase = .blocked(openSince: nil)

    var isClosed: Bool {
        if case .closed = phase { return true }
        return false
    }

    mutating func update(
        ratio: Double,
        timestamp: MonotonicTimestamp,
        tuning: GestureTuning
    ) -> PinchTransition {
        guard ratio.isFinite else {
            phase = .blocked(openSince: nil)
            return .none
        }
        if ratio >= tuning.pinchOpenRatio {
            switch phase {
            case let .blocked(openSince):
                if let openSince,
                   timestamp.duration(since: openSince) + 1e-9 >= tuning.pinchOpenRearmDuration {
                    phase = .armedOpen
                } else if openSince == nil {
                    phase = .blocked(openSince: timestamp)
                }
                return .none
            case .armedOpen:
                return .none
            case .closed:
                phase = .blocked(openSince: timestamp)
                return .opened
            }
        }
        if ratio <= tuning.pinchCloseRatio {
            switch phase {
            case .armedOpen:
                phase = .closed
                return .closed
            case .blocked, .closed:
                return .none
            }
        }
        return .none
    }
}

private extension TrackingDegradationReason {
    var isGlobalTrackingFailure: Bool {
        switch self {
        case .noHandDetected, .palmAnchorsMissing, .invalidPalmScale,
             .associationAmbiguous, .handIdentityLost, .visionFailure:
            true
        case .staleFrame, .lowRequiredJointConfidence,
             .poseAmbiguity, .invalidTimestamp:
            false
        }
    }
}
