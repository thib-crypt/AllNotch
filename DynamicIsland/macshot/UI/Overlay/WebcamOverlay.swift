import Cocoa
import AVFoundation

/// Corner of the recording rect the webcam bubble snaps to.
enum WebcamPosition: String {
    case bottomRight, bottomLeft, topRight, topLeft
}

/// Diameter of the webcam bubble as a fraction of the recording rect.
enum WebcamSize: String {
    case small, medium, large

    /// Target side length in points for the bubble.
    var side: CGFloat {
        switch self {
        case .small:  return 120
        case .medium: return 180
        case .large:  return 260
        }
    }
}

/// Outline shape of the webcam bubble.
enum WebcamShape: String {
    case circle, square, rectangle
}

/// A floating, optionally draggable panel showing a live camera preview.
/// Used as the webcam overlay while setting up / recording a capture.
@MainActor
final class WebcamOverlay: NSPanel {

    // MARK: - Camera discovery

    static var availableCameras: [AVCaptureDevice] {
        var types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
        if #available(macOS 14.0, *) {
            types.append(.external)
        }
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: types, mediaType: .video, position: .unspecified)
        return session.devices
    }

    // MARK: - State

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var input: AVCaptureDeviceInput?
    private let containerView = NSView()

    private var shape: WebcamShape = .circle

    init(screen: NSScreen) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 180, height: 180),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        containerView.wantsLayer = true
        containerView.layer?.masksToBounds = true
        contentView = containerView

        if let scr = NSScreen.screens.first(where: { $0 == screen }) {
            setFrameOrigin(NSPoint(x: scr.frame.midX - 90, y: scr.frame.midY - 90))
        }
    }

    // MARK: - Configuration

    func configure(position: WebcamPosition, size: WebcamSize, shape: WebcamShape, recordingRect: NSRect) {
        self.shape = shape

        let side = size.side
        let bubbleSize: NSSize
        switch shape {
        case .circle, .square:
            bubbleSize = NSSize(width: side, height: side)
        case .rectangle:
            bubbleSize = NSSize(width: side, height: round(side * 9.0 / 16.0))
        }

        let inset: CGFloat = 16
        let origin: NSPoint
        switch position {
        case .bottomRight:
            origin = NSPoint(x: recordingRect.maxX - bubbleSize.width - inset,
                             y: recordingRect.minY + inset)
        case .bottomLeft:
            origin = NSPoint(x: recordingRect.minX + inset,
                             y: recordingRect.minY + inset)
        case .topRight:
            origin = NSPoint(x: recordingRect.maxX - bubbleSize.width - inset,
                             y: recordingRect.maxY - bubbleSize.height - inset)
        case .topLeft:
            origin = NSPoint(x: recordingRect.minX + inset,
                             y: recordingRect.maxY - bubbleSize.height - inset)
        }

        setFrame(NSRect(origin: origin, size: bubbleSize), display: true)
        applyShapeMask(for: bubbleSize)
    }

    private func applyShapeMask(for size: NSSize) {
        guard let layer = containerView.layer else { return }
        switch shape {
        case .circle:
            layer.cornerRadius = min(size.width, size.height) / 2
        case .square:
            layer.cornerRadius = 12
        case .rectangle:
            layer.cornerRadius = 12
        }
        layer.borderWidth = 2
        layer.borderColor = NSColor.white.withAlphaComponent(0.85).cgColor
        previewLayer?.frame = containerView.bounds
        previewLayer?.cornerRadius = layer.cornerRadius
    }

    // MARK: - Preview lifecycle

    func startPreview(deviceUID: String?) {
        let device: AVCaptureDevice?
        if let uid = deviceUID {
            device = AVCaptureDevice(uniqueID: uid) ?? AVCaptureDevice.default(for: .video)
        } else {
            device = AVCaptureDevice.default(for: .video)
        }
        guard let camera = device else { return }

        session.beginConfiguration()
        if let existing = input {
            session.removeInput(existing)
            input = nil
        }
        if let newInput = try? AVCaptureDeviceInput(device: camera), session.canAddInput(newInput) {
            session.addInput(newInput)
            input = newInput
        }
        session.commitConfiguration()

        if previewLayer == nil {
            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = containerView.bounds
            containerView.layer?.addSublayer(layer)
            previewLayer = layer
        }
        previewLayer?.frame = containerView.bounds
        applyShapeMask(for: containerView.bounds.size)

        if !session.isRunning {
            Task.detached { [session] in
                session.startRunning()
            }
        }
    }

    func stopPreview() {
        if session.isRunning {
            session.stopRunning()
        }
        if let existing = input {
            session.removeInput(existing)
            input = nil
        }
    }

    // MARK: - Dragging

    private var draggable = false

    func setDraggable(_ enabled: Bool) {
        draggable = enabled
        isMovableByWindowBackground = enabled
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
