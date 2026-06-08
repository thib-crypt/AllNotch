import Cocoa
import CoreImage
import CoreImage.CIFilterBuiltins

/// Preset color "looks" offered in the effects popover. Raw values are stable
/// indices persisted in UserDefaults — append new cases, never reorder.
enum ImageEffectPreset: Int, CaseIterable, Equatable {
    case none = 0
    case vivid
    case mono
    case noir
    case warm
    case cool
    case fade
    case dramatic

    var displayName: String {
        switch self {
        case .none:     return L("None")
        case .vivid:    return L("Vivid")
        case .mono:     return L("Mono")
        case .noir:     return L("Noir")
        case .warm:     return L("Warm")
        case .cool:     return L("Cool")
        case .fade:     return L("Fade")
        case .dramatic: return L("Dramatic")
        }
    }
}

/// The full set of image adjustments applied to a screenshot before saving.
/// Slider-driven values (brightness/contrast/saturation/sharpness) compose on
/// top of the selected `preset` look.
struct ImageEffectsConfig: Equatable {
    var preset: ImageEffectPreset
    var brightness: Float   // -0.5 ... 0.5   (0 = neutral)
    var contrast: Float     //  0.5 ... 2.0   (1 = neutral)
    var saturation: Float   //  0.0 ... 2.0   (1 = neutral)
    var sharpness: Float    //  0.0 ... 2.0   (0 = neutral)

    init(preset: ImageEffectPreset = .none,
         brightness: Float = 0,
         contrast: Float = 1.0,
         saturation: Float = 1.0,
         sharpness: Float = 0) {
        self.preset = preset
        self.brightness = brightness
        self.contrast = contrast
        self.saturation = saturation
        self.sharpness = sharpness
    }

    /// True when the config produces no visible change (fast-path skip).
    var isIdentity: Bool {
        preset == .none
            && abs(brightness) < 0.0001
            && abs(contrast - 1.0) < 0.0001
            && abs(saturation - 1.0) < 0.0001
            && sharpness < 0.0001
    }
}

/// Applies `ImageEffectsConfig` to images using Core Image, and renders the
/// little preset swatches shown in the picker.
enum ImageEffects {

    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    // MARK: - Apply

    static func apply(to image: NSImage, config: ImageEffectsConfig) -> NSImage {
        guard !config.isIdentity else { return image }
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image
        }

        var ci = CIImage(cgImage: cg)
        ci = applyPreset(config.preset, to: ci)
        ci = applyManualAdjustments(config, to: ci)

        let outputExtent = CIImage(cgImage: cg).extent
        guard let rendered = context.createCGImage(ci, from: outputExtent) else {
            return image
        }
        return NSImage(cgImage: rendered, size: image.size)
    }

    // MARK: - Preset looks

    private static func applyPreset(_ preset: ImageEffectPreset, to input: CIImage) -> CIImage {
        switch preset {
        case .none:
            return input
        case .vivid:
            return colorControls(input, saturation: 1.4, contrast: 1.1, brightness: 0)
        case .mono:
            return colorControls(input, saturation: 0, contrast: 1.0, brightness: 0)
        case .noir:
            let f = CIFilter.photoEffectNoir()
            f.inputImage = input
            return f.outputImage ?? input
        case .warm:
            return temperature(input, neutralToTarget: 7500)
        case .cool:
            return temperature(input, neutralToTarget: 5000)
        case .fade:
            let faded = colorControls(input, saturation: 0.85, contrast: 0.9, brightness: 0.05)
            return faded
        case .dramatic:
            let f = CIFilter.photoEffectProcess()
            f.inputImage = input
            let processed = f.outputImage ?? input
            return colorControls(processed, saturation: 1.1, contrast: 1.25, brightness: -0.02)
        }
    }

    private static func temperature(_ input: CIImage, neutralToTarget target: CGFloat) -> CIImage {
        let f = CIFilter.temperatureAndTint()
        f.inputImage = input
        f.neutral = CIVector(x: 6500, y: 0)
        f.targetNeutral = CIVector(x: target, y: 0)
        return f.outputImage ?? input
    }

    // MARK: - Manual adjustments

    private static func applyManualAdjustments(_ config: ImageEffectsConfig, to input: CIImage) -> CIImage {
        var result = input

        let needsColorControls = abs(config.brightness) > 0.0001
            || abs(config.contrast - 1.0) > 0.0001
            || abs(config.saturation - 1.0) > 0.0001
        if needsColorControls {
            result = colorControls(result,
                                   saturation: config.saturation,
                                   contrast: config.contrast,
                                   brightness: config.brightness)
        }

        if config.sharpness > 0.0001 {
            let f = CIFilter.sharpenLuminance()
            f.inputImage = result
            f.sharpness = config.sharpness
            result = f.outputImage ?? result
        }

        return result
    }

    private static func colorControls(_ input: CIImage, saturation: Float, contrast: Float, brightness: Float) -> CIImage {
        let f = CIFilter.colorControls()
        f.inputImage = input
        f.saturation = saturation
        f.contrast = contrast
        f.brightness = brightness
        return f.outputImage ?? input
    }

    // MARK: - Swatches

    /// Representative adjustment values used to render each preset's swatch.
    private static func swatchConfig(for preset: ImageEffectPreset) -> ImageEffectsConfig {
        switch preset {
        case .vivid: return ImageEffectsConfig(preset: .vivid, contrast: 1.2, saturation: 1.5)
        default:     return ImageEffectsConfig(preset: preset)
        }
    }

    /// Render a small preview swatch for `preset` by applying it to a colourful
    /// sample gradient.
    static func presetSwatch(_ preset: ImageEffectPreset, size: CGFloat) -> NSImage {
        let pixelSize = NSSize(width: size, height: size)
        let sample = sampleImage(size: pixelSize)
        return apply(to: sample, config: swatchConfig(for: preset))
    }

    /// A static colourful sample used as the base for preset swatches.
    private static func sampleImage(size: NSSize) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            // Diagonal multi-hue gradient gives a clear sense of each look.
            let colors: [NSColor] = [
                NSColor(calibratedRed: 0.95, green: 0.45, blue: 0.35, alpha: 1),
                NSColor(calibratedRed: 0.98, green: 0.80, blue: 0.30, alpha: 1),
                NSColor(calibratedRed: 0.30, green: 0.70, blue: 0.55, alpha: 1),
                NSColor(calibratedRed: 0.30, green: 0.45, blue: 0.85, alpha: 1),
            ]
            let gradient = NSGradient(colors: colors)
            gradient?.draw(in: rect, angle: 45)

            // A neutral skin-tone disc so mono/noir/warm/cool read differently.
            let disc = NSRect(x: rect.width * 0.30, y: rect.height * 0.30,
                              width: rect.width * 0.40, height: rect.height * 0.40)
            NSColor(calibratedRed: 0.86, green: 0.66, blue: 0.55, alpha: 1).setFill()
            NSBezierPath(ovalIn: disc).fill()
            return true
        }
    }
}
