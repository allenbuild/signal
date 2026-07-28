import CoreGraphics
import Foundation

public enum InputControllerFault: Equatable, Sendable {
    case accessibilityUnavailable
    case backendUnavailable
    case cursorUnavailable
    case displayUnavailable
    case eventConstructionFailed
}

public struct InputControllerSnapshot: Equatable, Sendable {
    public var outputEnabled: Bool
    public var generation: UInt64
    public var heldButtons: Set<InputMouseButton>
    public var possiblyHeldButtons: Set<InputMouseButton>
}

public final class MacOSInputController: InputControlling, CaptureGenerationInputSink,
    TransientOutputClutching, TrackingOutputSuspending,
    @unchecked Sendable {
    public typealias FaultHandler = @Sendable (InputControllerFault) -> Void

    private let backend: InputEventBackend
    private let trustProvider: InputTrustProviding
    private let queue = DispatchQueue(label: "com.allenxu.Signal.input")
    private let queueKey = DispatchSpecificKey<UInt8>()
    private let gate = OutputGate()
    private let callbackLock = NSLock()
    private var _onFault: FaultHandler?
    private var _captureGenerationValidator: (@Sendable (UInt64) -> Bool)?

    // input queue only
    private var heldButtons: Set<InputMouseButton> = []
    private var possiblyHeldButtons: Set<InputMouseButton> = []
    private var scrollRemainderX = 0.0
    private var scrollRemainderY = 0.0
    private var tuning: GestureTuning
    private var screenZoomShortcutsEnabled: Bool
    private let zoomController: ZoomController
    private var processingCaptureGeneration: UInt64?
    private var isReportingFault = false

    public convenience init(
        tuning: GestureTuning = .safeDefaults,
        userZoomProfiles: [String: ZoomApplicationProfile] = [:],
        screenZoomShortcutsEnabled: Bool = false
    ) {
        self.init(
            backend: CGInputEventBackend(),
            trustProvider: SystemInputTrustProvider(),
            applicationProvider: SystemFrontmostApplicationProvider(),
            clock: SystemInputMonotonicClock(),
            tuning: tuning,
            userZoomProfiles: userZoomProfiles,
            screenZoomShortcutsEnabled: screenZoomShortcutsEnabled
        )
    }

    public init(
        backend: InputEventBackend,
        trustProvider: InputTrustProviding,
        applicationProvider: FrontmostApplicationProviding,
        clock: InputMonotonicClock,
        tuning: GestureTuning = .safeDefaults,
        userZoomProfiles: [String: ZoomApplicationProfile] = [:],
        screenZoomShortcutsEnabled: Bool = false
    ) {
        self.backend = backend
        self.trustProvider = trustProvider
        self.tuning = tuning.validated()
        self.screenZoomShortcutsEnabled = screenZoomShortcutsEnabled
        zoomController = ZoomController(
            applicationProvider: applicationProvider,
            clock: clock,
            userProfiles: userZoomProfiles
        )
        queue.setSpecific(key: queueKey, value: 1)
    }

    deinit {
        gate.disable()
        performOnQueueSync {
            clearTransientState()
            releaseOwnedButtonsOnQueue(reportFailure: false)
        }
    }

    public var onFault: FaultHandler? {
        get {
            callbackLock.lock()
            defer { callbackLock.unlock() }
            return _onFault
        }
        set {
            callbackLock.lock()
            _onFault = newValue
            callbackLock.unlock()
        }
    }

    public var captureGenerationValidator: (@Sendable (UInt64) -> Bool)? {
        get {
            callbackLock.lock()
            defer { callbackLock.unlock() }
            return _captureGenerationValidator
        }
        set {
            callbackLock.lock()
            _captureGenerationValidator = newValue
            callbackLock.unlock()
        }
    }

    public var generatedEventMarker: Int64 {
        backend.marker
    }

    public var isOutputEnabled: Bool {
        gate.snapshot().accepting
    }

    public var currentGeneration: UInt64 {
        gate.snapshot().generation
    }

    public func snapshot() -> InputControllerSnapshot {
        let gateSnapshot = gate.snapshot()
        return performOnQueueSync {
            InputControllerSnapshot(
                outputEnabled: gateSnapshot.accepting,
                generation: gateSnapshot.generation,
                heldButtons: heldButtons,
                possiblyHeldButtons: possiblyHeldButtons
            )
        }
    }

    public func isGeneratedEvent(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == backend.marker
    }

    public func setOutputGate(enabled: Bool) {
        if enabled {
            let generation = gate.beginEnable()
            queue.async { [weak self] in
                self?.finishEnable(generation: generation)
            }
        } else {
            gate.disable()
            queue.async { [weak self] in
                self?.clearTransientState()
            }
        }
    }

    public func handle(_ event: GestureEvent) {
        handle(event, captureGeneration: nil)
    }

    public func handle(_ event: GestureEvent, captureGeneration: UInt64) {
        handle(event, captureGeneration: Optional(captureGeneration))
    }

    private func handle(_ event: GestureEvent, captureGeneration: UInt64?) {
        switch event {
        case .trackingLost:
            releaseAllInputs()
        case .dragEnd:
            performOnQueueSync { endDragOnCleanupLane() }
        default:
            let operation = gate.snapshot()
            guard operation.accepting else { return }
            queue.async { [weak self] in
                guard let self else { return }
                self.processingCaptureGeneration = captureGeneration
                defer { self.processingCaptureGeneration = nil }
                self.process(event, generation: operation.generation)
            }
        }
    }

    public func releaseAllInputs() {
        gate.disable()
        performOnQueueSync {
            clearTransientState()
            releaseOwnedButtonsOnQueue(reportFailure: true)
        }
    }

    public func clutchPendingNormalOutput() {
        // A clutch is not an enable operation. In particular, do not invalidate
        // the generation of an enable that is still pending its trust checks.
        guard gate.advanceAcceptingGeneration() != nil else { return }
        performOnQueueSync {
            clearTransientState()
        }
    }

    public func suspendForTrackingUnavailable() {
        // A recognition gap is not a user disable. Preserve the explicit gate
        // while invalidating queued normal work and synchronously releasing
        // anything Signal owns so a held button cannot outlive visibility.
        _ = gate.advanceAcceptingGeneration()
        performOnQueueSync {
            clearTransientState()
            releaseOwnedButtonsOnQueue(reportFailure: true)
        }
    }

    public func emergencyStop() {
        releaseAllInputs()
    }

    public func displayConfigurationDidChange() {
        releaseAllInputs()
    }

    public func updateTuning(_ newValue: GestureTuning) {
        let generation = gate.advanceGeneration()
        queue.async { [weak self] in
            guard let self, self.gate.snapshot().generation == generation else { return }
            self.tuning = newValue.validated()
            self.clearTransientState()
        }
    }

    public func updateZoomProfiles(_ profiles: [String: ZoomApplicationProfile]) {
        let generation = gate.advanceGeneration()
        queue.async { [weak self] in
            guard let self, self.gate.snapshot().generation == generation else { return }
            self.zoomController.updateUserProfiles(profiles)
        }
    }

    /// Applies the complete gesture/input configuration as one serialized
    /// revision. Callers quiesce first, so no mixed tuning/zoom-policy frame
    /// can become observable.
    public func updateConfiguration(
        tuning: GestureTuning,
        zoomProfiles: [String: ZoomApplicationProfile],
        screenZoomShortcutsEnabled: Bool = false
    ) {
        gate.disable()
        performOnQueueSync {
            self.tuning = tuning.validated()
            self.screenZoomShortcutsEnabled = screenZoomShortcutsEnabled
            zoomController.updateUserProfiles(zoomProfiles)
            clearTransientState()
        }
    }

    public func resetZoomForFrontmostApplication() {
        let operation = gate.snapshot()
        guard operation.accepting else { return }
        queue.async { [weak self] in
            guard let self, self.normalBatchIsReady(generation: operation.generation) else { return }
            let events = self.zoomController.resetShortcutEvents(
                physicalModifiers: self.backend.physicalModifierFlags()
            )
            if !events.isEmpty {
                _ = self.postNormal(events, generation: operation.generation)
            }
        }
    }

    private func finishEnable(generation: UInt64) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard gate.isPendingEnable(generation: generation) else { return }
        clearTransientState()

        guard backend.isHealthy else {
            closeForFault(.backendUnavailable)
            return
        }
        guard trustProvider.isAccessibilityTrusted, trustProvider.canPostEvents else {
            closeForFault(.accessibilityUnavailable)
            return
        }
        guard flushPossiblyHeldButtons() else { return }
        _ = gate.activate(generation: generation)
    }

    private func process(_ event: GestureEvent, generation: UInt64) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard normalBatchIsReady(generation: generation) else { return }

        switch event {
        case let .pointerDelta(dx, dy):
            movePointer(dx: dx, dy: dy, generation: generation, dragging: false)
        case .leftClick:
            postLeftClick(generation: generation)
        case .doubleClick:
            postDoubleClick(generation: generation)
        case .dragStart:
            startDrag(generation: generation)
        case let .dragDelta(dx, dy):
            movePointer(dx: dx, dy: dy, generation: generation, dragging: true)
        case .dragEnd:
            endDragOnCleanupLane()
        case .rightClick:
            postRightClick(generation: generation)
        case let .scroll(dx, dy):
            postScroll(dx: dx, dy: dy, generation: generation)
        case let .zoom(delta):
            postZoom(delta: delta, generation: generation)
        case .trackingLost:
            closeAndReleaseOnQueue()
        }
    }

    private func movePointer(
        dx: Double,
        dy: Double,
        generation: UInt64,
        dragging: Bool
    ) {
        guard dx.isFinite, dy.isFinite else { return }
        guard !dragging || heldButtons.contains(.left) else { return }
        guard let current = backend.currentCursorLocation() else {
            closeForFault(.cursorUnavailable)
            return
        }

        let maximum = tuning.pointerMaximumDelta
        let boundedX = min(max(dx, -maximum), maximum)
        let boundedY = min(max(dy, -maximum), maximum)
        let desired = Point2D(x: current.x + boundedX, y: current.y + boundedY)
        guard let destination = projectToActiveDisplay(desired) else {
            closeForFault(.displayUnavailable)
            return
        }

        let event: LowLevelInputEvent = .mouse(
            kind: dragging ? .leftDragged : .moved,
            position: destination,
            button: .left,
            clickState: dragging ? 1 : 0
        )
        _ = postNormal([event], generation: generation)
    }

    private func postLeftClick(generation: UInt64) {
        guard clickLikeEventIsAllowed(), let position = currentProjectedCursor() else { return }
        _ = postNormal([
            mouse(.leftDown, at: position, button: .left, clickState: 1),
            mouse(.leftUp, at: position, button: .left, clickState: 1)
        ], generation: generation)
    }

    private func postDoubleClick(generation: UInt64) {
        guard clickLikeEventIsAllowed(), let position = currentProjectedCursor() else { return }
        _ = postNormal([
            mouse(.leftDown, at: position, button: .left, clickState: 1),
            mouse(.leftUp, at: position, button: .left, clickState: 1),
            mouse(.leftDown, at: position, button: .left, clickState: 2),
            mouse(.leftUp, at: position, button: .left, clickState: 2)
        ], generation: generation)
    }

    private func postRightClick(generation: UInt64) {
        guard clickLikeEventIsAllowed(), let position = currentProjectedCursor() else { return }
        _ = postNormal([
            mouse(.rightDown, at: position, button: .right, clickState: 1),
            mouse(.rightUp, at: position, button: .right, clickState: 1)
        ], generation: generation)
    }

    private func startDrag(generation: UInt64) {
        guard !heldButtons.contains(.left), clickLikeEventIsAllowed(),
              let position = currentProjectedCursor() else { return }
        if postNormal([
            mouse(.leftDown, at: position, button: .left, clickState: 1)
        ], generation: generation) {
            heldButtons.insert(.left)
        }
    }

    private func endDragOnCleanupLane() {
        dispatchPrecondition(condition: .onQueue(queue))
        releaseButtonOnCleanupLane(.left, reportFailure: true)
    }

    private func postScroll(dx: Double, dy: Double, generation: UInt64) {
        guard dx.isFinite, dy.isFinite else { return }
        let maximum = tuning.scrollMaximumDelta
        let sign = tuning.naturalScrolling ? -1.0 : 1.0
        scrollRemainderX += min(max(dx * sign, -maximum), maximum)
        scrollRemainderY += min(max(dy * sign, -maximum), maximum)

        let integralX = integralScrollValue(scrollRemainderX)
        let integralY = integralScrollValue(scrollRemainderY)
        scrollRemainderX -= Double(integralX)
        scrollRemainderY -= Double(integralY)
        guard integralX != 0 || integralY != 0 else { return }
        _ = postNormal([.scroll(dx: integralX, dy: integralY)], generation: generation)
    }

    private func postZoom(delta: Double, generation: UInt64) {
        // Accessibility trust does not prove that macOS screen-zoom shortcuts
        // are enabled. Fail closed until the user explicitly confirms the
        // separate System Settings toggle, otherwise this chord could fall
        // through to the frontmost application.
        guard screenZoomShortcutsEnabled else {
            zoomController.reset()
            return
        }
        let events = zoomController.events(
            for: delta,
            tuning: tuning,
            physicalModifiers: backend.physicalModifierFlags()
        )
        guard !events.isEmpty else { return }
        _ = postNormal(events, generation: generation)
    }

    @discardableResult
    private func postNormal(_ events: [LowLevelInputEvent], generation: UInt64) -> Bool {
        guard !events.isEmpty, normalBatchIsReady(generation: generation) else { return false }
        guard backend.post(events) else {
            closeForFault(.eventConstructionFailed)
            return false
        }
        return true
    }

    private func normalBatchIsReady(generation: UInt64) -> Bool {
        guard gate.isAccepting(generation: generation) else { return false }
        if let captureGeneration = processingCaptureGeneration {
            callbackLock.lock()
            let validator = _captureGenerationValidator
            callbackLock.unlock()
            guard validator?(captureGeneration) ?? false else { return false }
        }
        guard backend.isHealthy else {
            closeForFault(.backendUnavailable)
            return false
        }
        guard trustProvider.isAccessibilityTrusted, trustProvider.canPostEvents else {
            closeForFault(.accessibilityUnavailable)
            return false
        }
        return true
    }

    private func clickLikeEventIsAllowed() -> Bool {
        heldButtons.isEmpty
            && !InputMouseButton.allCases.contains(where: backend.isPhysicalButtonPressed)
            && backend.physicalModifierFlags().isEmpty
    }

    private func currentProjectedCursor() -> Point2D? {
        guard let cursor = backend.currentCursorLocation() else {
            closeForFault(.cursorUnavailable)
            return nil
        }
        guard let projected = projectToActiveDisplay(cursor) else {
            closeForFault(.displayUnavailable)
            return nil
        }
        return projected
    }

    private func projectToActiveDisplay(_ point: Point2D) -> Point2D? {
        let displays = backend.activeDisplays().filter(\.isDrawable)
        guard !displays.isEmpty else { return nil }

        if displays.contains(where: { display in
            point.x >= display.minX && point.x < display.maxX
                && point.y >= display.minY && point.y < display.maxY
        }) {
            return point
        }

        var bestCandidate: DisplayProjectionCandidate?
        for display in displays {
            let maximumX = display.maxX.nextDown
            let maximumY = display.maxY.nextDown
            let pointOnDisplay = Point2D(
                x: min(max(point.x, display.minX), maximumX),
                y: min(max(point.y, display.minY), maximumY)
            )
            let deltaX = point.x - pointOnDisplay.x
            let deltaY = point.y - pointOnDisplay.y
            let squaredX = deltaX * deltaX
            let squaredY = deltaY * deltaY
            let candidate = DisplayProjectionCandidate(
                point: pointOnDisplay,
                distanceSquared: squaredX + squaredY,
                displayID: display.id
            )
            if candidate.isPreferred(over: bestCandidate) {
                bestCandidate = candidate
            }
        }
        return bestCandidate?.point
    }

    private func flushPossiblyHeldButtons() -> Bool {
        let buttons = heldButtons.union(possiblyHeldButtons)
        guard !buttons.isEmpty else { return true }
        guard trustProvider.isAccessibilityTrusted, trustProvider.canPostEvents,
              let position = currentProjectedCursor() else { return false }

        let events = buttons.sorted(by: { $0.rawValue < $1.rawValue }).map {
            mouseUp(for: $0, at: position)
        }
        guard backend.post(events) else {
            closeForFault(.eventConstructionFailed)
            return false
        }
        heldButtons.removeAll()
        possiblyHeldButtons.removeAll()
        return true
    }

    private func releaseOwnedButtonsOnQueue(reportFailure: Bool) {
        dispatchPrecondition(condition: .onQueue(queue))
        let buttons = heldButtons.union(possiblyHeldButtons)
        heldButtons.removeAll()
        possiblyHeldButtons = buttons
        guard !buttons.isEmpty else { return }

        guard trustProvider.isAccessibilityTrusted, trustProvider.canPostEvents,
              let position = currentProjectedCursorWithoutFault() else { return }
        let events = buttons.sorted(by: { $0.rawValue < $1.rawValue }).map {
            mouseUp(for: $0, at: position)
        }
        if backend.post(events) {
            possiblyHeldButtons.removeAll()
        } else if reportFailure {
            reportFaultOnQueue(.eventConstructionFailed)
        }
    }

    private func releaseButtonOnCleanupLane(_ button: InputMouseButton, reportFailure: Bool) {
        let owned = heldButtons.contains(button) || possiblyHeldButtons.contains(button)
        guard owned else { return }
        heldButtons.remove(button)
        possiblyHeldButtons.insert(button)

        guard trustProvider.isAccessibilityTrusted, trustProvider.canPostEvents,
              let position = currentProjectedCursorWithoutFault() else { return }
        if backend.post([mouseUp(for: button, at: position)]) {
            possiblyHeldButtons.remove(button)
        } else if reportFailure {
            reportFaultOnQueue(.eventConstructionFailed)
        }
    }

    private func closeForFault(_ fault: InputControllerFault) {
        gate.disable()
        clearTransientState()
        releaseOwnedButtonsOnQueue(reportFailure: false)
        reportFaultOnQueue(fault)
    }

    private func closeAndReleaseOnQueue() {
        gate.disable()
        clearTransientState()
        releaseOwnedButtonsOnQueue(reportFailure: true)
    }

    private func clearTransientState() {
        scrollRemainderX = 0
        scrollRemainderY = 0
        zoomController.reset()
    }

    private func currentProjectedCursorWithoutFault() -> Point2D? {
        guard let cursor = backend.currentCursorLocation() else { return nil }
        return projectToActiveDisplay(cursor)
    }

    private func notifyFault(_ fault: InputControllerFault) {
        callbackLock.lock()
        let callback = _onFault
        callbackLock.unlock()
        callback?(fault)
    }

    /// Fault callbacks may synchronously invoke the producer safety fence,
    /// which calls `releaseAllInputs()` back on this same queue. Keep the gate
    /// closure synchronous while suppressing nested callbacks so a failed
    /// mouse-up cannot recurse indefinitely. Possibly-held bookkeeping remains
    /// intact for a later trusted recovery flush.
    private func reportFaultOnQueue(_ fault: InputControllerFault) {
        dispatchPrecondition(condition: .onQueue(queue))
        gate.disable()
        guard !isReportingFault else { return }
        isReportingFault = true
        defer { isReportingFault = false }
        notifyFault(fault)
    }

    private func mouse(
        _ kind: InputMouseEventKind,
        at position: Point2D,
        button: InputMouseButton,
        clickState: Int64
    ) -> LowLevelInputEvent {
        .mouse(kind: kind, position: position, button: button, clickState: clickState)
    }

    private func mouseUp(
        for button: InputMouseButton,
        at position: Point2D
    ) -> LowLevelInputEvent {
        let kind: InputMouseEventKind
        switch button {
        case .left: kind = .leftUp
        case .right: kind = .rightUp
        case .other: kind = .otherUp
        }
        return mouse(kind, at: position, button: button, clickState: 1)
    }

    private func integralScrollValue(_ value: Double) -> Int32 {
        guard value.isFinite else { return 0 }
        let truncated = value.rounded(.towardZero)
        let lower = Double(Int32.min)
        let upper = Double(Int32.max)
        return Int32(min(max(truncated, lower), upper))
    }

    @discardableResult
    private func performOnQueueSync<T>(_ body: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return try body()
        }
        return try queue.sync(execute: body)
    }
}

private struct DisplayProjectionCandidate {
    var point: Point2D
    var distanceSquared: Double
    var displayID: UInt32

    func isPreferred(over other: Self?) -> Bool {
        guard let other else { return true }
        if distanceSquared == other.distanceSquared {
            return displayID < other.displayID
        }
        return distanceSquared < other.distanceSquared
    }
}

private final class OutputGate: @unchecked Sendable {
    struct Snapshot: Equatable, Sendable {
        var explicitRequested: Bool
        var accepting: Bool
        var generation: UInt64
    }

    private let lock = NSLock()
    private var explicitRequested = false
    private var accepting = false
    private var generation: UInt64 = 0

    func beginEnable() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        generation &+= 1
        explicitRequested = true
        accepting = false
        return generation
    }

    @discardableResult
    func activate(generation candidate: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard generation == candidate, explicitRequested else { return false }
        accepting = true
        return true
    }

    @discardableResult
    func disable() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        generation &+= 1
        explicitRequested = false
        accepting = false
        return generation
    }

    func advanceGeneration() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        generation &+= 1
        return generation
    }

    func advanceAcceptingGeneration() -> UInt64? {
        lock.lock()
        defer { lock.unlock() }
        guard explicitRequested, accepting else { return nil }
        generation &+= 1
        return generation
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(
            explicitRequested: explicitRequested,
            accepting: accepting,
            generation: generation
        )
    }

    func isPendingEnable(generation candidate: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generation == candidate && explicitRequested && !accepting
    }

    func isAccepting(generation candidate: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generation == candidate && explicitRequested && accepting
    }
}
