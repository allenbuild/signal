import AppKit
import QuartzCore
import SwiftUI

/// Hosts a camera-owned preview layer. The camera layer owns mirroring; this host
/// deliberately applies no second transform so overlays use the frozen mirrored
/// top-left coordinate contract.
@MainActor
public struct MirroredPreviewHost: NSViewRepresentable {
    public var previewLayer: CALayer?

    public init(previewLayer: CALayer?) {
        self.previewLayer = previewLayer
    }

    public func makeNSView(context: Context) -> PreviewContainerView {
        let view = PreviewContainerView()
        view.setPreviewLayer(previewLayer)
        return view
    }

    public func updateNSView(_ nsView: PreviewContainerView, context: Context) {
        nsView.setPreviewLayer(previewLayer)
    }
}

@MainActor
public final class PreviewContainerView: NSView {
    private weak var hostedLayer: CALayer?

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    public func setPreviewLayer(_ previewLayer: CALayer?) {
        guard hostedLayer !== previewLayer else { return }
        hostedLayer?.removeFromSuperlayer()
        hostedLayer = previewLayer
        if let previewLayer {
            layer?.addSublayer(previewLayer)
            previewLayer.frame = bounds
        }
    }

    public override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hostedLayer?.frame = bounds
        CATransaction.commit()
    }
}
