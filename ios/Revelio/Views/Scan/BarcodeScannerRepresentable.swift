import SwiftUI
import AVFoundation

struct BarcodeScannerRepresentable: UIViewRepresentable {
    let onBarcode: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onBarcode: onBarcode) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)
        let session = AVCaptureSession()
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return view }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        session.addOutput(output)
        output.setMetadataObjectsDelegate(context.coordinator, queue: .main)
        output.metadataObjectTypes = [.ean13, .ean8, .upce, .qr]
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.frame = view.bounds
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        context.coordinator.session = session
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let onBarcode: (String) -> Void
        var session: AVCaptureSession?
        private var lastCode = ""
        private var lastTime = Date.distantPast
        init(onBarcode: @escaping (String) -> Void) { self.onBarcode = onBarcode }
        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from: AVCaptureConnection) {
            guard let obj = objects.first as? AVMetadataMachineReadableCodeObject,
                  let code = obj.stringValue,
                  code != lastCode || Date().timeIntervalSince(lastTime) > 2 else { return }
            lastCode = code; lastTime = Date(); onBarcode(code)
        }
    }
}
