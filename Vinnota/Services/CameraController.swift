// AVCaptureSession is not yet Sendable-annotated. Driving it from one serial
// queue is Apple's documented pattern and is what this file does, so the
// Sendable warnings from the unannotated module are suppressed rather than
// worked around.
@preconcurrency import AVFoundation
import Observation
import UIKit

/// The live capture session behind the scan frame.
///
/// The iOS Simulator has no camera, so `isAvailable` is false there and the
/// scan screen offers the photo library instead — the OCR path is identical
/// either way, which is what makes the feature testable without a device.
@Observable
@MainActor
final class CameraController: NSObject {
    enum Status: Equatable { case idle, running, unavailable(String) }

    private(set) var status: Status = .idle
    private(set) var isAvailable: Bool = false

    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "com.vinnota.camera")
    private var continuation: CheckedContinuation<UIImage, Error>?

    enum CaptureError: Error { case noImage, notRunning }

    override init() {
        super.init()
        isAvailable = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }

    func start() async {
        guard isAvailable else {
            status = .unavailable("No camera on this device — pick a label photo instead.")
            return
        }
        guard await requestAccess() else {
            status = .unavailable("Camera access is off for Vinnota. Enable it in Settings, or pick a photo instead.")
            return
        }
        guard configure() else { return }

        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            queue.async { [session] in
                if !session.isRunning { session.startRunning() }
                c.resume()
            }
        }
        status = .running
    }

    func stop() {
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
        status = .idle
    }

    private func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    private var configured = false

    private func configure() -> Bool {
        guard !configured else { return true }
        session.beginConfiguration()
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input), session.canAddOutput(output) else {
            session.commitConfiguration()
            status = .unavailable("Could not open the camera.")
            return false
        }
        session.addInput(input)
        session.addOutput(output)
        // Labels are close work; continuous autofocus keeps the text sharp.
        if let _ = try? device.lockForConfiguration() {
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            if device.isSmoothAutoFocusSupported { device.isSmoothAutoFocusEnabled = true }
            device.unlockForConfiguration()
        }
        session.commitConfiguration()
        configured = true
        return true
    }

    /// Captures a single frame for the OCR pass.
    func capture() async throws -> UIImage {
        guard case .running = status else { throw CaptureError.notRunning }
        return try await withCheckedThrowingContinuation { c in
            self.continuation = c
            let settings = AVCapturePhotoSettings()
            settings.flashMode = .off
            output.capturePhoto(with: settings, delegate: self)
        }
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        Task { @MainActor in
            defer { continuation = nil }
            if let error { continuation?.resume(throwing: error); return }
            guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
                continuation?.resume(throwing: CaptureError.noImage); return
            }
            continuation?.resume(returning: image)
        }
    }
}
