import Cocoa
import Combine
import UniformTypeIdentifiers
import Vision

@MainActor
class MacshotManager: NSObject, ObservableObject, OverlayWindowControllerDelegate {
    
    static let shared = MacshotManager()
    
    // MARK: - State Properties
    @Published var isCapturing = false
    
    // Shared capture sound
    static let captureSound: NSSound? = {
        let path = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif"
        return NSSound(contentsOfFile: path, byReference: true) ?? NSSound(named: "Tink")
    }()
    
    // Pools & Window Controllers
    private var overlayControllers: [OverlayWindowController] = []
    private var overlayControllerPool: [ObjectIdentifier: OverlayWindowController] = [:]
    private var pinControllers: [PinWindowController] = []
    private var thumbnailControllers: [FloatingThumbnailController] = []
    private var ocrController: OCRResultController?
    private var uploadToastController: UploadToastController?
    
    // Delay capture timers & window
    private var delayCountdownWindow: NSWindow?
    private var delayTimer: Timer?
    private var delayEscMonitor: Any?
    
    // Focus tracking
    private var previousApp: NSRunningApplication?
    private var capturedWindowTitle: String?
    
    // Pour renvoyer le résultat à un appelant (comme le Screen Assistant)
    private var pendingCompletion: ((URL) -> Void)?
    
    // Capture session tracking
    private var captureSessionID: UInt = 0

    /// One compositor beat to let the WindowServer recomposite the screen after
    /// our own windows (notably the notch panel, which lives in a max-level
    /// space) are stashed — otherwise the immediate framebuffer grab still
    /// contains the expanded notch.
    private static let recompositeDelay: TimeInterval = 0.06
    
    // MARK: - Flags for Capture Type
    private var pendingOCRMode = false
    private var pendingQuickCaptureMode = false
    private var pendingScrollCaptureMode = false
    
    private override init() {
        super.init()
        prewarmCapturePath()
        
        // Listen to screen changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }
    
    // MARK: - Public Entry Points
    
    func startCapture(type: ScreenshotSnippingTool.ScreenshotType = .area, completion: @escaping (URL) -> Void) {
        self.pendingCompletion = completion
        self.startCapture(type: type)
    }
    
    func startCapture(type: ScreenshotSnippingTool.ScreenshotType = .area) {
        guard !isCapturing else { return }

        // Screen Recording permission guard. Without it, CGWindowListCreateImage /
        // SCScreenshotManager silently return ONLY the desktop wallpaper (other apps'
        // windows are excluded), while window *geometry* (CGWindowListCopyWindowInfo)
        // still works — so the picker shows window outlines but the pixels are wallpaper.
        // Rather than capture a useless wallpaper-only shot, guide the user.
        guard CGPreflightScreenCaptureAccess() else {
            pendingCompletion = nil
            presentPermissionOnboarding()
            return
        }

        isCapturing = true
        captureSessionID &+= 1
        
        previousApp = NSWorkspace.shared.frontmostApplication
        capturedWindowTitle = nil
        
        // Raccorder les modes de capture optionnels
        pendingOCRMode = false
        pendingQuickCaptureMode = false
        pendingScrollCaptureMode = false
        
        dismissOverlays(refocusPreviousApp: false)
        isCapturing = true
        
        // Masquer l'island (ou les fenêtres AllNotch) pour ne pas être capturées
        stashBackgroundWindows()
        
        // Masquer les miniatures
        for tc in thumbnailControllers { tc.hideWindow() }
        
        let delay = UserDefaults.standard.integer(forKey: "captureDelaySeconds")
        if delay > 0 {
            showPreCaptureCountdown(seconds: delay, type: type)
            return
        }

        // Wait one compositor beat after stashing our windows so the WindowServer
        // has actually dropped the notch from the on-screen image before we grab
        // the framebuffer. Without this, an expanded notch still appears in the
        // capture even though `stashBackgroundWindows()` already hid it.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.recompositeDelay) { [weak self] in
            guard let self, self.isCapturing else { return }
            self.performCapture(type: type)
        }
    }
    
    func startOCR() {
        pendingOCRMode = true
        startCapture(type: .area)
    }
    
    func startQuickCapture() {
        pendingQuickCaptureMode = true
        startCapture(type: .area)
    }
    
    func startScrollCapture() {
        pendingScrollCaptureMode = true
        startCapture(type: .area)
    }
    
    // MARK: - Capture Core Execution
    
    private func performCapture(type: ScreenshotSnippingTool.ScreenshotType) {
        let screens = NSScreen.screens
        let captureContext = ScreenCaptureManager.makeImmediateCaptureContext()
        
        var controllers: [OverlayWindowController] = []
        for screen in screens {
            let controller = pooledController(for: screen)
            controller.overlayDelegate = self
            controller.capturedWindowTitle = capturedWindowTitle
            
            if pendingOCRMode { controller.setAutoOCRMode() }
            if pendingQuickCaptureMode { controller.setAutoQuickSaveMode() }
            if pendingScrollCaptureMode { controller.setAutoScrollCaptureMode() }

            // When the capture toolbar is disabled, a plain capture skips the
            // annotation/action toolbar and finalises straight to the vignette
            // (deferred disposition) — reusing the existing quick-save path.
            let showToolbar = UserDefaults.standard.object(forKey: "showCaptureToolbar") as? Bool ?? true
            if !showToolbar && !pendingOCRMode && !pendingScrollCaptureMode {
                controller.setAutoQuickSaveMode()
            }

            controllers.append(controller)
        }
        overlayControllers.append(contentsOf: controllers)
        
        pendingOCRMode = false
        pendingQuickCaptureMode = false
        pendingScrollCaptureMode = false
        
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            let captures = ScreenCaptureManager.captureAllScreensImmediately(context: captureContext)
            
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                // Assigner l'image capturée à l'overlay de chaque écran correspondant
                for controller in self.overlayControllers {
                    if let capture = captures.first(where: { $0.screen == controller.screen }) {
                        controller.setScreenshot(capture.image)
                    }
                }
                
                // Afficher les overlays
                for controller in self.overlayControllers {
                    controller.showOverlay()
                }
                
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
    
    // MARK: - Permission Onboarding

    private var permissionOnboarding: PermissionOnboardingController?

    /// Presents the existing step-by-step onboarding window guiding the user to grant
    /// Screen Recording permission, instead of silently capturing the wallpaper.
    private func presentPermissionOnboarding() {
        let controller = permissionOnboarding ?? PermissionOnboardingController()
        permissionOnboarding = controller
        controller.onPermissionGranted = { [weak self] in
            self?.permissionOnboarding = nil
        }
        controller.show()
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Prewarm Pool

    func prewarmCapturePath() {
        ScreenCaptureManager.prewarm()
        rebuildOverlayPool()
    }
    
    private func rebuildOverlayPool() {
        for (_, controller) in overlayControllerPool {
            controller.tearDown()
        }
        overlayControllerPool.removeAll()
        for screen in NSScreen.screens {
            let controller = OverlayWindowController(screen: screen)
            overlayControllerPool[ObjectIdentifier(screen)] = controller
            controller.warmPanel()
        }
    }
    
    private func pooledController(for screen: NSScreen) -> OverlayWindowController {
        if let existing = overlayControllerPool[ObjectIdentifier(screen)] {
            return existing
        }
        let controller = OverlayWindowController(screen: screen)
        overlayControllerPool[ObjectIdentifier(screen)] = controller
        controller.warmPanel()
        return controller
    }
    
    @objc private func screenParametersDidChange() {
        guard !isCapturing else { return }
        prewarmCapturePath()
    }
    
    // MARK: - Pre-Capture Countdown
    
    private func showPreCaptureCountdown(seconds: Int, type: ScreenshotSnippingTool.ScreenshotType) {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let size = NSSize(width: 140, height: 140)
        let origin = NSPoint(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.midY - size.height / 2
        )
        
        let window = NSWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        let countdownView = CountdownView(frame: NSRect(origin: .zero, size: size))
        countdownView.remaining = seconds
        window.contentView = countdownView
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        delayCountdownWindow = window
        
        delayEscMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // ESC
                self?.cancelPreCaptureCountdown()
                return nil
            }
            return event
        }
        
        var remaining = seconds
        delayTimer?.invalidate()
        delayTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            remaining -= 1
            if remaining <= 0 {
                timer.invalidate()
                self?.delayTimer = nil
                self?.delayCountdownWindow?.orderOut(nil)
                self?.delayCountdownWindow = nil
                self?.removeDelayEscMonitors()
                self?.performCapture(type: type)
            } else {
                countdownView.remaining = remaining
                countdownView.needsDisplay = true
            }
        }
    }
    
    private func removeDelayEscMonitors() {
        if let m = delayEscMonitor { NSEvent.removeMonitor(m); delayEscMonitor = nil }
    }
    
    private func cancelPreCaptureCountdown() {
        delayTimer?.invalidate()
        delayTimer = nil
        delayCountdownWindow?.orderOut(nil)
        delayCountdownWindow = nil
        removeDelayEscMonitors()
        isCapturing = false
    }
    
    // MARK: - Dismiss & Focus Management
    
    func dismissOverlays(refocusPreviousApp: Bool = true) {
        let controllers = overlayControllers
        overlayControllers.removeAll()
        for controller in controllers {
            controller.dismiss()
        }
        
        // Restaurer les fenêtres AllNotch qui ont été masquées
        unstashBackgroundWindows()
        
        // Restaurer les vignettes
        for tc in thumbnailControllers { tc.showWindow() }
        
        isCapturing = false
        
        if refocusPreviousApp {
            returnFocusIfNeeded()
        }
    }
    
    func returnFocusIfNeeded() {
        guard let app = previousApp else {
            NSApp.hide(nil)
            return
        }
        previousApp = nil
        
        // Réactiver l'app précédente pour lui redonner le focus
        app.activate(options: .activateIgnoringOtherApps)
    }
    
    // MARK: - OverlayWindowControllerDelegate
    
    func overlayDidCancel(_ controller: OverlayWindowController) {
        dismissOverlays()
    }
    
    func overlayDidConfirm(_ controller: OverlayWindowController, capturedImage: NSImage?, annotationData: CaptureAnnotationData?, disposition: CaptureDisposition) {
        dismissOverlays()
        guard let image = capturedImage else { return }

        ScreenshotHistory.shared.add(
            image: image,
            rawImage: annotationData?.rawImage,
            annotations: annotationData?.annotations
        )

        // Gérer le callback temporaire pour l'intégration de l'assistant IA ou autre
        if let completion = self.pendingCompletion {
            self.pendingCompletion = nil
            let filename = "screenshot_\(Int(Date().timeIntervalSince1970)).png"
            let screenshotDir = ScreenAssistantManager.screenshotDataDirectory
            try? FileManager.default.createDirectory(at: screenshotDir, withIntermediateDirectories: true)
            let screenshotURL = screenshotDir.appendingPathComponent(filename)

            DispatchQueue.global(qos: .userInitiated).async {
                if let imageData = image.tiffRepresentation,
                   let bitmapRep = NSBitmapImageRep(data: imageData),
                   let pngData = bitmapRep.representation(using: .png, properties: [:]) {
                    try? pngData.write(to: screenshotURL)
                    DispatchQueue.main.async {
                        completion(screenshotURL)
                    }
                }
            }
        }

        let entryID = ScreenshotHistory.shared.entries.first?.id

        // "Open in Editor Immediately" preference takes precedence over the
        // vignette flow: open the editor directly and skip the floating vignette.
        if UserDefaults.standard.bool(forKey: "quickCaptureOpenEditor") {
            if let data = annotationData {
                DetachedEditorWindowController.open(image: data.rawImage, annotations: data.annotations, historyEntryID: entryID)
            } else {
                DetachedEditorWindowController.open(image: image, historyEntryID: entryID, disableBeautify: true)
            }
            return
        }

        // Otherwise show the floating vignette. For a *deferred* capture (no
        // explicit Copy/Save), arm the user's Default Action so that, if they
        // ignore the vignette and it auto-dismisses, the screenshot is still
        // saved/copied per their preference. Explicit dispositions arm nothing.
        let onTimeout: (() -> Void)?
        if disposition == .deferred {
            onTimeout = { [weak self] in self?.applyDefaultAction(to: image) }
        } else {
            onTimeout = nil
        }

        DispatchQueue.main.async { [weak self] in
            self?.showFloatingThumbnail(image: image, annotationData: annotationData, historyEntryID: entryID, onTimeout: onTimeout)
        }
    }

    /// Apply the user's configured Default Action (`quickCaptureMode`) to a
    /// capture whose vignette auto-dismissed without interaction.
    /// 0 = save to folder, 1 = copy to clipboard, 2 = both, 3 = do nothing.
    private func applyDefaultAction(to image: NSImage) {
        let mode = UserDefaults.standard.object(forKey: "quickCaptureMode") as? Int ?? 1
        if mode == 1 || mode == 2 {
            ImageEncoder.copyToClipboard(image)
        }
        if mode == 0 || mode == 2 {
            saveImageToFile(image)
        }
    }
    
    func overlayDidRequestPin(_ controller: OverlayWindowController, image: NSImage) {
        dismissOverlays(refocusPreviousApp: false)
        let savedApp = previousApp
        showPin(image: image)
        
        if let app = savedApp {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                app.activate(options: .activateIgnoringOtherApps)
            }
        }
    }
    
    func overlayDidRequestOCR(_ controller: OverlayWindowController, text: String, image: NSImage?) {
        dismissOverlays()
        
        let ocrAction = UserDefaults.standard.integer(forKey: "ocrAction")
        let shouldCopy = ocrAction == 0 || ocrAction == 2
        let shouldShowWindow = ocrAction == 0 || ocrAction == 1
        
        if shouldCopy && !text.isEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
        
        if shouldShowWindow, let img = image {
            ocrController?.close()
            let ocr = OCRResultController(text: text, image: img)
            ocrController = ocr
            ocr.show()
        }
    }
    
    func overlayDidRequestUpload(_ controller: OverlayWindowController, image: NSImage) {
        dismissOverlays(refocusPreviousApp: false)
        let savedApp = previousApp
        showUploadProgress(image: image)
        
        if let app = savedApp {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                app.activate(options: .activateIgnoringOtherApps)
            }
        }
    }
    
    func overlayDidRequestStartRecording(_ controller: OverlayWindowController, rect: NSRect, screen: NSScreen) {}
    func overlayDidRequestStopRecording(_ controller: OverlayWindowController) {}
    func overlayDidRequestScrollCapture(_ controller: OverlayWindowController, rect: NSRect, screen: NSScreen) {}
    func overlayDidRequestStopScrollCapture(_ controller: OverlayWindowController) {}
    func overlayDidRequestToggleAutoScroll(_ controller: OverlayWindowController) {}
    func overlayDidRequestAccessibilityPermission(_ controller: OverlayWindowController) {}
    func overlayDidRequestInputMonitoringPermission(_ controller: OverlayWindowController) {}
    func overlayDidBeginSelection(_ controller: OverlayWindowController) {}
    func overlayDidChangeSelection(_ controller: OverlayWindowController, globalRect: NSRect) {}
    func overlayDidRemoteResizeSelection(_ controller: OverlayWindowController, globalRect: NSRect) {}
    func overlayDidFinishRemoteResize(_ controller: OverlayWindowController, globalRect: NSRect) {}
    func overlayDidChangeWindowSnapState(_ controller: OverlayWindowController) {}
    
    func overlayCrossScreenImage(_ controller: OverlayWindowController) -> NSImage? {
        return nil
    }
    
    // MARK: - UI Utilities & Floating Windows
    
    func showPin(image: NSImage) {
        let pin = PinWindowController(image: image)
        pin.delegate = self
        pin.show()
        pinControllers.append(pin)
    }
    
    func showFloatingThumbnail(image: NSImage, annotationData: CaptureAnnotationData? = nil, historyEntryID: String? = nil, onTimeout: (() -> Void)? = nil) {
        let enabled = UserDefaults.standard.object(forKey: "showFloatingThumbnail") as? Bool ?? true
        guard enabled else { return }
        
        let stacking = UserDefaults.standard.object(forKey: "thumbnailStacking") as? Bool ?? true
        if !stacking {
            thumbnailControllers.forEach { $0.dismiss() }
            thumbnailControllers.removeAll()
        }
        
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let screenFrame = screen.visibleFrame
        let padding: CGFloat = 16
        let gap: CGFloat = 8
        let corner = thumbnailCorner()
        let thumbSize = FloatingThumbnailController.currentThumbnailSize()
        let xOrigin = thumbnailX(for: thumbSize.width, in: screenFrame, corner: corner, padding: padding)
        
        var yOrigin = corner.isTop ? screenFrame.maxY - thumbSize.height - padding : screenFrame.minY + padding
        if let topController = thumbnailControllers.last {
            let topFrame = topController.windowFrame
            yOrigin = corner.isTop ? topFrame.minY - thumbSize.height - gap : topFrame.maxY + gap
        }
        
        let controller = FloatingThumbnailController(image: image)
        controller.historyEntryID = historyEntryID
        controller.onTimeout = onTimeout
        controller.onDismiss = { [weak self] in
            self?.thumbnailControllers.removeAll { $0 === controller }
            self?.reflowThumbnails()
        }
        controller.onCopy = {
            ImageEncoder.copyToClipboard(image)
        }
        controller.onSave = { [weak self] in
            guard let self = self else { return }
            self.saveImageToFile(image)
        }
        controller.onPin = { [weak self] in
            guard let self = self else { return }
            ScreenshotHistory.shared.add(image: image)
            self.showPin(image: image)
            
            // Ajouter également au Shelf d'AllNotch
            self.addImageToShelf(image, historyEntryID: historyEntryID)
        }
        controller.onEdit = {
            if let data = annotationData {
                DetachedEditorWindowController.open(image: data.rawImage, annotations: data.annotations, historyEntryID: historyEntryID)
            } else {
                DetachedEditorWindowController.open(image: image, historyEntryID: historyEntryID, disableBeautify: true)
            }
        }
        controller.onUpload = { [weak self] in
            guard let self = self else { return }
            ScreenshotHistory.shared.add(image: image)
            self.showUploadProgress(image: image)
        }
        controller.onAddToShelf = { [weak self] in
            guard let self = self else { return }
            self.addImageToShelf(image, historyEntryID: historyEntryID)
        }
        controller.onDelete = {
            if let id = historyEntryID {
                ScreenshotHistory.shared.removeEntry(id: id)
            }
        }
        controller.onCloseAll = { [weak self] in
            guard let self = self else { return }
            let all = self.thumbnailControllers
            self.thumbnailControllers.removeAll()
            for c in all { c.dismiss() }
        }
        controller.onSaveAll = { [weak self] in
            guard let self = self else { return }
            for tc in self.thumbnailControllers {
                self.saveImageToFile(tc.image)
            }
        }
        
        controller.show(at: NSPoint(x: xOrigin, y: yOrigin), corner: corner)
        thumbnailControllers.append(controller)
    }
    
    func refreshThumbnail(for id: String, image: NSImage) {
        if let match = thumbnailControllers.first(where: { $0.historyEntryID == id }) {
            match.updateImage(image)
        }
    }
    
    private func reflowThumbnails() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let screenFrame = screen.visibleFrame
        let padding: CGFloat = 16
        let gap: CGFloat = 8
        let corner = thumbnailCorner()
        let thumbSize = FloatingThumbnailController.currentThumbnailSize()
        let xOrigin = thumbnailX(for: thumbSize.width, in: screenFrame, corner: corner, padding: padding)
        
        var currentY = corner.isTop ? screenFrame.maxY - thumbSize.height - padding : screenFrame.minY + padding
        
        for controller in thumbnailControllers {
            controller.moveTo(origin: NSPoint(x: xOrigin, y: currentY))
            let frame = controller.windowFrame
            currentY = corner.isTop ? frame.minY - thumbSize.height - gap : frame.maxY + gap
        }
    }
    
    private func thumbnailCorner() -> FloatingThumbnailCorner {
        let val = UserDefaults.standard.integer(forKey: "thumbnailPlacement")
        let all: [FloatingThumbnailCorner] = [.bottomRight, .bottomLeft, .topRight, .topLeft]
        return (val >= 0 && val < all.count) ? all[val] : .bottomRight
    }

    private func thumbnailX(for width: CGFloat, in frame: NSRect, corner: FloatingThumbnailCorner, padding: CGFloat) -> CGFloat {
        if corner == .topLeft || corner == .bottomLeft {
            return frame.minX + padding
        } else {
            return frame.maxX - width - padding
        }
    }
    
    /// Add a captured screenshot to AllNotch's notch Shelf.
    /// Reuses the on-disk history file when available, otherwise encodes the
    /// image to a scratch file so the Shelf has a real URL to reference.
    private func addImageToShelf(_ image: NSImage, historyEntryID: String?) {
        if let id = historyEntryID {
            let fileURL = ScreenshotHistory.shared.historyDir.appendingPathComponent("\(id).png")
            if FileManager.default.fileExists(atPath: fileURL.path) {
                addFileURLToShelf(fileURL)
                return
            }
        }

        // No history file yet — encode to a scratch file and add that.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let data = ImageEncoder.encode(image) else { return }
            let url = TmpScratchDirectory.makeURL(filename: FilenameFormatter.defaultImageFilename())
            do {
                try data.write(to: url)
                DispatchQueue.main.async {
                    self?.addFileURLToShelf(url)
                }
            } catch {
                print("❌ MacshotManager: Failed to write image for Shelf: \(error)")
            }
        }
    }

    /// Add a file URL to the notch Shelf that the UI actually renders
    /// (`ShelfStateViewModel`). The legacy `TrayDrop` store is not displayed by
    /// the current `ShelfView`, so screenshots routed there never appeared.
    private func addFileURLToShelf(_ url: URL) {
        Task { @MainActor in
            let items = await ShelfDropService.items(from: [url])
            ShelfStateViewModel.shared.add(items)
        }
    }

    private func saveImageToFile(_ image: NSImage) {
        let dirURL = SaveDirectoryAccess.resolve()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let filename = "Screenshot \(formatter.string(from: Date())).\(ImageEncoder.fileExtension)"
        let fileURL = dirURL.appendingPathComponent(filename)
        
        DispatchQueue.global(qos: .userInteractive).async {
            guard let imageData = ImageEncoder.encode(image) else { return }
            do {
                try imageData.write(to: fileURL)
                // Ajouter également au Shelf d'AllNotch après enregistrement
                DispatchQueue.main.async { [weak self] in
                    self?.addFileURLToShelf(fileURL)
                }
            } catch {
                print("❌ MacshotManager: Failed to save file: \(error)")
            }
            SaveDirectoryAccess.stopAccessing(url: dirURL)
        }
    }
    
    // MARK: - Stash & Unstash Windows (To hide AllNotch windows during capture)
    
    private var stashedWindows: [NSWindow] = []
    
    private func stashBackgroundWindows() {
        stashedWindows.removeAll()

        // Hide AllNotch's own windows (Notch window, settings window, etc.)
        for window in NSApplication.shared.windows {
            if window.isVisible && window.title != "OverlayWindow" && !(window is OverlayWindow) && window != delayCountdownWindow {
                stashedWindows.append(window)
                // The notch panel lives in a max-level CGSSpace, so `orderOut`
                // alone doesn't visually remove it — it keeps overlapping the
                // capture overlay. Zeroing the alpha first (mirroring the
                // screen-lock hide path) actually hides it.
                window.alphaValue = 0
                window.orderOut(nil)
            }
        }
    }

    private func unstashBackgroundWindows() {
        for window in stashedWindows {
            window.orderFront(nil)
            window.alphaValue = 1
        }
        stashedWindows.removeAll()
    }
    
    // MARK: - S3/Imgbb Cloud Upload Progress Dialogs
    
    func showUploadProgress(image: NSImage) {
        uploadToastController?.dismiss()
        let toast = UploadToastController()
        uploadToastController = toast
        toast.onDismiss = { [weak self] in
            self?.uploadToastController = nil
        }
        toast.show(status: "Uploading...")
        
        let provider = UserDefaults.standard.string(forKey: "uploadProvider") ?? "imgbb"
        
        if provider == "gdrive" && !GoogleDriveUploader.shared.isSignedIn {
            toast.showError(message: "Google Drive not signed in")
            return
        }
        
        if provider == "s3" && !S3Uploader.shared.isConfigured {
            toast.showError(message: "S3 not configured — check Settings")
            return
        }
        
        if provider == "gdrive" {
            GoogleDriveUploader.shared.uploadImage(image) { result in
                switch result {
                case .success(let link):
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(link, forType: .string)
                    toast.showSuccess(link: link, deleteURL: "")
                case .failure(let error):
                    toast.showError(message: error.localizedDescription)
                }
            }
        } else if provider == "s3" {
            S3Uploader.shared.onProgress = { fraction in
                toast.updateProgress(fraction)
            }
            S3Uploader.shared.uploadImage(image) { result in
                switch result {
                case .success(let link):
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(link, forType: .string)
                    toast.showSuccess(link: link, deleteURL: "")
                case .failure(let error):
                    toast.showError(message: error.localizedDescription)
                }
            }
        } else {
            // Imgbb upload
            ImageUploader.upload(image: image) { result in
                switch result {
                case .success(let payload):
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(payload.link, forType: .string)
                    toast.showSuccess(link: payload.link, deleteURL: payload.deleteURL)
                case .failure(let error):
                    toast.showError(message: error.localizedDescription)
                }
            }
        }
    }
    
    func confirmClearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear History"
        alert.informativeText = "Are you sure you want to clear all screenshot history?"
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            ScreenshotHistory.shared.clear()
        }
    }
}

// MARK: - Extension to implement PinWindowControllerDelegate
extension MacshotManager: PinWindowControllerDelegate {
    func pinWindowDidClose(_ controller: PinWindowController) {
        pinControllers.removeAll { $0 === controller }
    }
}
