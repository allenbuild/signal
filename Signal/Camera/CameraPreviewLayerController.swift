@preconcurrency import AVFoundation
import Foundation

/// Main-actor preview plumbing. The capture data output remains unmirrored;
/// only this display layer is mirrored for a natural front-camera experience.
@MainActor
public final class CameraPreviewLayerController {
    public let layer: AVCaptureVideoPreviewLayer

    init(session: AVCaptureSession) {
        layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        refreshConnectionConfiguration()
    }

    /// Call after capture configuration and from the preview view's update path
    /// because the layer connection may not exist when the layer is created.
    public func refreshConnectionConfiguration() {
        guard let connection = layer.connection else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        if connection.isVideoMirroringSupported {
            connection.isVideoMirrored = true
        }
    }
}
