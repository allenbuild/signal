import SwiftUI

public struct LandmarkSelection: Equatable, Sendable {
    public var handID: HandTrackID
    public var landmark: LandmarkName

    public init(handID: HandTrackID, landmark: LandmarkName) {
        self.handID = handID
        self.landmark = landmark
    }
}

public struct LandmarkOverlayView: View {
    public var snapshot: CalibrationOverlaySnapshot?
    @Binding public var selection: LandmarkSelection?

    private static let skeleton: [(LandmarkName, LandmarkName)] = [
        (.wrist, .thumbCMC), (.thumbCMC, .thumbMP), (.thumbMP, .thumbIP), (.thumbIP, .thumbTip),
        (.wrist, .indexMCP), (.indexMCP, .indexPIP), (.indexPIP, .indexDIP), (.indexDIP, .indexTip),
        (.wrist, .middleMCP), (.middleMCP, .middlePIP), (.middlePIP, .middleDIP), (.middleDIP, .middleTip),
        (.wrist, .ringMCP), (.ringMCP, .ringPIP), (.ringPIP, .ringDIP), (.ringDIP, .ringTip),
        (.wrist, .littleMCP), (.littleMCP, .littlePIP), (.littlePIP, .littleDIP), (.littleDIP, .littleTip),
        (.indexMCP, .middleMCP), (.middleMCP, .ringMCP), (.ringMCP, .littleMCP)
    ]

    public init(snapshot: CalibrationOverlaySnapshot?, selection: Binding<LandmarkSelection?>) {
        self.snapshot = snapshot
        _selection = selection
    }

    public var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                guard let snapshot else { return }
                for handOverlay in snapshot.hands {
                    let hand = handOverlay.hand
                    let color = handColor(hand.id)
                    drawSkeleton(
                        hand.rawLandmarks,
                        in: &context,
                        size: size,
                        color: .white.opacity(0.65),
                        lineWidth: 1,
                        dashed: true
                    )
                    drawSkeleton(
                        hand.filteredLandmarks,
                        in: &context,
                        size: size,
                        color: color,
                        lineWidth: 2,
                        dashed: false
                    )

                    for name in LandmarkName.allCases.sorted(by: { $0.rawValue < $1.rawValue }) {
                        if let raw = hand.rawLandmarks[name] {
                            let center = canvasPoint(raw.position, size: size)
                            let dot = Path(ellipseIn: CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6))
                            context.stroke(dot, with: .color(.white.opacity(0.9)), lineWidth: 1.5)
                        }
                        if let filtered = hand.filteredLandmarks[name] {
                            let center = canvasPoint(filtered.position, size: size)
                            let isSelected = selection == LandmarkSelection(handID: hand.id, landmark: name)
                            let radius: CGFloat = isSelected ? 6 : 4
                            let dot = Path(ellipseIn: CGRect(
                                x: center.x - radius,
                                y: center.y - radius,
                                width: radius * 2,
                                height: radius * 2
                            ))
                            context.fill(dot, with: .color(isSelected ? .yellow : color))
                            context.stroke(dot, with: .color(.black.opacity(0.7)), lineWidth: 1)
                        }
                    }

                    if let wrist = hand.filteredLandmarks[.wrist] {
                        let point = canvasPoint(wrist.position, size: size)
                        let label = Text("Hand \(hand.id.rawValue)  \(poseLabel(handOverlay.pose))")
                            .font(.caption.bold())
                            .foregroundColor(.white)
                        context.draw(label, at: CGPoint(x: point.x + 8, y: point.y - 12), anchor: .leading)
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in selectNearest(to: value.location, size: proxy.size) }
            )
            .accessibilityLabel("Hand landmark overlay")
        }
    }

    private func drawSkeleton(
        _ landmarks: HandLandmarks,
        in context: inout GraphicsContext,
        size: CGSize,
        color: Color,
        lineWidth: CGFloat,
        dashed: Bool
    ) {
        var path = Path()
        for (startName, endName) in Self.skeleton {
            guard let start = landmarks[startName], let end = landmarks[endName] else { continue }
            path.move(to: canvasPoint(start.position, size: size))
            path.addLine(to: canvasPoint(end.position, size: size))
        }
        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: dashed ? [4, 3] : [])
        )
    }

    private func canvasPoint(_ point: Point2D, size: CGSize) -> CGPoint {
        AspectFillProjection(sourceAspectRatio: 4.0 / 3.0).project(point, into: size)
    }

    private func handColor(_ id: HandTrackID) -> Color {
        id.rawValue.isMultiple(of: 2) ? .cyan : .mint
    }

    private func poseLabel(_ pose: HandPoseSnapshot?) -> String {
        pose?.metrics.pose.rawValue ?? "unknown"
    }

    private func selectNearest(to location: CGPoint, size: CGSize) {
        guard let snapshot else {
            selection = nil
            return
        }
        var nearest: (distance: CGFloat, selection: LandmarkSelection)?
        for handOverlay in snapshot.hands {
            for name in LandmarkName.allCases {
                guard let sample = handOverlay.hand.filteredLandmarks[name] else { continue }
                let point = canvasPoint(sample.position, size: size)
                let distance = hypot(point.x - location.x, point.y - location.y)
                if distance <= 16, nearest == nil || distance < nearest!.distance {
                    nearest = (distance, LandmarkSelection(handID: handOverlay.hand.id, landmark: name))
                }
            }
        }
        selection = nearest?.selection
    }
}

public struct AspectFillProjection: Equatable, Sendable {
    public var sourceAspectRatio: Double

    public init(sourceAspectRatio: Double) {
        self.sourceAspectRatio = sourceAspectRatio
    }

    public func project(_ point: Point2D, into size: CGSize) -> CGPoint {
        guard sourceAspectRatio.isFinite, sourceAspectRatio > 0,
              size.width > 0, size.height > 0 else { return .zero }
        let viewAspect = Double(size.width / size.height)
        let displayedWidth: CGFloat
        let displayedHeight: CGFloat
        if viewAspect > sourceAspectRatio {
            displayedWidth = size.width
            displayedHeight = size.width / CGFloat(sourceAspectRatio)
        } else {
            displayedHeight = size.height
            displayedWidth = size.height * CGFloat(sourceAspectRatio)
        }
        let originX = (size.width - displayedWidth) / 2
        let originY = (size.height - displayedHeight) / 2
        return CGPoint(
            x: originX + CGFloat(point.x) * displayedWidth,
            y: originY + CGFloat(point.y) * displayedHeight
        )
    }
}
