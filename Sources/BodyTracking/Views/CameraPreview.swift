import AVFoundation
import SwiftUI

/// Live camera preview, aspect-fit, optionally mirrored.
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    let mirrored: Bool

    func makeNSView(context: Context) -> PreviewView {
        PreviewView(session: session)
    }

    func updateNSView(_ view: PreviewView, context: Context) {
        view.mirrored = mirrored
    }

    final class PreviewView: NSView {
        private let previewLayer: AVCaptureVideoPreviewLayer
        var mirrored = false {
            didSet { needsLayout = true }
        }

        init(session: AVCaptureSession) {
            previewLayer = AVCaptureVideoPreviewLayer(session: session)
            super.init(frame: .zero)
            previewLayer.videoGravity = .resizeAspect
            let root = CALayer()
            root.backgroundColor = NSColor.black.cgColor
            root.addSublayer(previewLayer)
            layer = root
            wantsLayer = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        override func layout() {
            super.layout()
            // Mirroring is done with a layer transform so it never depends on the capture connection.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            previewLayer.bounds = CGRect(origin: .zero, size: bounds.size)
            previewLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
            previewLayer.setAffineTransform(mirrored ? CGAffineTransform(scaleX: -1, y: 1) : .identity)
            if let connection = previewLayer.connection, connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
            CATransaction.commit()
        }
    }
}
