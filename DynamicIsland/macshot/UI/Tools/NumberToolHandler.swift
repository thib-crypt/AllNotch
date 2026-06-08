import Cocoa

/// Handles number (auto-incrementing circle) tool interaction.
/// Click-to-place with drag support. Always commits (even zero-size).
final class NumberToolHandler: AnnotationToolHandler {

    let tool: AnnotationTool = .number

    func start(at point: NSPoint, canvas: AnnotationCanvas) -> Annotation? {
        canvas.numberCounter += 1
        let annotation = Annotation(
            tool: .number,
            startPoint: point,
            endPoint: point,
            color: canvas.opacityAppliedColor(for: .number),
            strokeWidth: canvas.currentNumberSize
        )
        annotation.number = canvas.numberCounter + (canvas.numberStartAt - 1)
        annotation.numberFormat = canvas.currentNumberFormat
        return annotation
    }

    func update(to point: NSPoint, shiftHeld: Bool, canvas: AnnotationCanvas) {
        guard let annotation = canvas.activeAnnotation else { return }
        var clampedPoint = point

        if shiftHeld {
            canvas.snapGuideX = nil
            canvas.snapGuideY = nil
        } else {
            clampedPoint = canvas.snapPoint(point, excluding: annotation)
        }

        annotation.endPoint = clampedPoint
    }

    func finish(canvas: AnnotationCanvas) {
        guard let annotation = canvas.activeAnnotation else { return }
        // Number always commits (even on click without drag)
        commitAnnotation(annotation, canvas: canvas)
    }
}
