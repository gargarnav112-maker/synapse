import AVFoundation
import SwiftUI
import UIKit

/// Shows the capture session's live video, filling the view, in portrait.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ view: PreviewUIView, context: Context) {
        view.applyPortraitRotation()
    }
}

final class PreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        // layerClass guarantees the type.
        layer as! AVCaptureVideoPreviewLayer // swiftlint:disable:this force_cast
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyPortraitRotation()
    }

    /// The connection appears only once the session has an input.
    func applyPortraitRotation() {
        if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(90),
           connection.videoRotationAngle != 90 {
            connection.videoRotationAngle = 90
        }
    }
}
