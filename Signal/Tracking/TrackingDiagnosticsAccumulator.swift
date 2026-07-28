import Foundation

struct TrackingDiagnosticsAccumulator: Sendable {
    private var completionTimes: [Double] = []
    private let maximumCompletionSamples = 120
    private var cameraDroppedFrames: UInt64 = 0
    private var trackingDroppedFrames: UInt64 = 0
    private(set) var captureFPS: Double = 0
    private(set) var visionLatencyMilliseconds: Double = 0
    private(set) var endToEndLatencyMilliseconds: Double = 0

    init() {
        completionTimes.reserveCapacity(120)
    }

    mutating func updateCamera(captureFPS: Double, droppedFrames: UInt64) {
        self.captureFPS = captureFPS.isFinite ? max(0, captureFPS) : 0
        cameraDroppedFrames = droppedFrames
    }

    mutating func recordDrop() {
        trackingDroppedFrames &+= 1
    }

    mutating func recordProcessed(
        completionUptime: Double,
        sourceTimestamp: MonotonicTimestamp,
        visionLatencyMilliseconds: Double
    ) {
        if completionTimes.count == maximumCompletionSamples {
            completionTimes.removeFirst()
        }
        completionTimes.append(completionUptime)
        self.visionLatencyMilliseconds = visionLatencyMilliseconds.isFinite
            ? max(0, visionLatencyMilliseconds)
            : 0

        let latency = (completionUptime - sourceTimestamp.rawValue) * 1_000
        if latency.isFinite, latency >= 0, latency <= 10_000 {
            endToEndLatencyMilliseconds = latency
        } else {
            endToEndLatencyMilliseconds = 0
        }
    }

    mutating func resetProcessing() {
        completionTimes.removeAll(keepingCapacity: true)
        trackingDroppedFrames = 0
        visionLatencyMilliseconds = 0
        endToEndLatencyMilliseconds = 0
    }

    func snapshot(at uptime: Double) -> TrackingDiagnostics {
        let recentCount = completionTimes.reduce(into: 0) { count, sample in
            if uptime - sample <= 1.0 {
                count += 1
            }
        }
        let (combinedDrops, overflow) = cameraDroppedFrames.addingReportingOverflow(trackingDroppedFrames)
        return TrackingDiagnostics(
            captureFPS: captureFPS,
            processedFPS: Double(recentCount),
            droppedFrames: overflow ? .max : combinedDrops,
            visionLatencyMilliseconds: visionLatencyMilliseconds,
            endToEndLatencyMilliseconds: endToEndLatencyMilliseconds
        )
    }
}
