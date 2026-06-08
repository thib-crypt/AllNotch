import Cocoa

/// Handles loupe (magnifying glass) tool interaction.
/// Click-to-place: creates a baked 2x magnification annotation immediately on mouseDown.
final class LoupeToolHandler: AnnotationToolHandler {

    let tool: AnnotationTool = .loupe

    func start(at point: NSPoint, canvas: AnnotationCanvas) -> Annotation? {
        let size = canvas.currentLoupeSize
        let annotation = Annotation(
            tool: .loupe,
            startPoint: NSPoint(x: point.x - size / 2, y: point.y - size / 2),
            endPoint: NSPoint(x: point.x + size / 2, y: point.y + size / 2),
            color: canvas.currentColor,
            strokeWidth: canvas.currentStrokeWidth
        )
        annotation.sourceImage = canvas.screenshotImage
        annotation.sourceImageBounds = canvas.captureDrawRect
        annotation.bakeLoupe()

        // Loupe is instant — commit immediately, don't set as active
        annotation.bakePixelate()
        canvas.annotations.append(annotation)
        canvas.undoStack.append(.added(annotation))
        canvas.redoStack.removeAll()
        canvas.setNeedsDisplay()
        return nil  // nil = don't set as activeAnnotation (already committed)
    }

    func update(to point: NSPoint, shiftHeld: Bool, canvas: AnnotationCanvas) {
        // No drag behavior — loupe is click-to-place
    }

    func finish(canvas: AnnotationCanvas) {
        // No finish behavior — loupe committed in start()
    }
}
