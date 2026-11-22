import CoreImage
import CoreImage.CIFilterBuiltins
import Vision
import UIKit

/// Scanner-grade clean-up applied before OCR:
/// page-border detection + perspective correction, deskew, shadow removal,
/// denoising, contrast enhancement and orientation correction.
struct ImagePreprocessor: Sendable {
    struct Options: OptionSet, Sendable {
        let rawValue: Int
        static let perspective = Options(rawValue: 1 << 0)
        static let deskew = Options(rawValue: 1 << 1)
        static let removeShadows = Options(rawValue: 1 << 2)
        static let denoise = Options(rawValue: 1 << 3)
        static let enhanceContrast = Options(rawValue: 1 << 4)
        static let orientation = Options(rawValue: 1 << 5)

        static let basic: Options = [.orientation, .enhanceContrast]
        static let advanced: Options = [.perspective, .deskew, .removeShadows, .denoise, .enhanceContrast, .orientation]
        /// Pages from VNDocumentCameraViewController are already cropped and flattened.
        static let alreadyScanned: Options = [.removeShadows, .enhanceContrast, .orientation]
    }

    struct Result {
        let image: CGImage
        let appliedSteps: [String]
    }

    private let context = CIContext(options: [.useSoftwareRenderer: false, .cacheIntermediates: false])
    /// Long edge in pixels; Vision accuracy plateaus around here while memory stays bounded.
    private let maxDimension: CGFloat = 3_000

    func process(_ input: CGImage, orientation: CGImagePropertyOrientation = .up, options: Options) -> Result {
        var image = CIImage(cgImage: input).oriented(orientation)
        var steps: [String] = []

        image = downscaleIfNeeded(image)

        if options.contains(.perspective), let corrected = correctPerspective(image) {
            image = corrected
            steps.append("perspective")
        }
        if options.contains(.deskew), let angle = skewAngle(of: image), abs(angle) > 0.003, abs(angle) < 0.35 {
            image = image.transformed(by: CGAffineTransform(rotationAngle: -angle))
            image = image.transformed(by: CGAffineTransform(translationX: -image.extent.origin.x, y: -image.extent.origin.y))
            steps.append("deskew")
        }
        if options.contains(.removeShadows) {
            image = removeShadows(image)
            steps.append("shadows")
        }
        if options.contains(.denoise) {
            let filter = CIFilter.noiseReduction()
            filter.inputImage = image
            filter.noiseLevel = 0.02
            filter.sharpness = 0.6
            image = filter.outputImage ?? image
            steps.append("denoise")
        }
        if options.contains(.enhanceContrast) {
            let filter = CIFilter.colorControls()
            filter.inputImage = image
            filter.saturation = 0
            filter.contrast = 1.25
            filter.brightness = 0.02
            image = filter.outputImage ?? image
            steps.append("contrast")
        }

        guard var output = context.createCGImage(image, from: image.extent) else {
            return Result(image: input, appliedSteps: [])
        }
        if options.contains(.orientation), let rotated = correctOrientation(output) {
            output = rotated
            steps.append("orientation")
        }
        return Result(image: output, appliedSteps: steps)
    }

    // MARK: Steps

    private func downscaleIfNeeded(_ image: CIImage) -> CIImage {
        let longest = max(image.extent.width, image.extent.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let filter = CIFilter.lanczosScaleTransform()
        filter.inputImage = image
        filter.scale = Float(scale)
        filter.aspectRatio = 1
        return filter.outputImage ?? image
    }

    /// Detects the page quadrilateral with Vision's document segmentation and flattens it.
    private func correctPerspective(_ image: CIImage) -> CIImage? {
        let request = VNDetectDocumentSegmentationRequest()
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        guard (try? handler.perform([request])) != nil,
              let page = request.results?.first, page.confidence > 0.6 else { return nil }
        let size = image.extent.size
        func point(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * size.width, y: p.y * size.height) }
        // Ignore detections that are essentially the whole frame (nothing to correct).
        let area = page.boundingBox.width * page.boundingBox.height
        guard area < 0.97 else { return nil }
        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = image
        filter.topLeft = point(page.topLeft)
        filter.topRight = point(page.topRight)
        filter.bottomLeft = point(page.bottomLeft)
        filter.bottomRight = point(page.bottomRight)
        return filter.outputImage
    }

    /// Median baseline angle of detected text lines.
    private func skewAngle(of image: CIImage) -> CGFloat? {
        let request = VNDetectTextRectanglesRequest()
        request.reportCharacterBoxes = false
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        guard (try? handler.perform([request])) != nil, let results = request.results, results.count >= 5 else { return nil }
        let size = image.extent.size
        let angles: [CGFloat] = results.compactMap { rect in
            let dx = (rect.bottomRight.x - rect.bottomLeft.x) * size.width
            let dy = (rect.bottomRight.y - rect.bottomLeft.y) * size.height
            guard dx > 20 else { return nil }
            return atan2(dy, dx)
        }.sorted()
        guard !angles.isEmpty else { return nil }
        return angles[angles.count / 2]
    }

    /// Divides the page by a heavily blurred copy of itself (background estimate),
    /// which flattens uneven lighting and phone shadows while keeping ink dark.
    private func removeShadows(_ image: CIImage) -> CIImage {
        let grayscale = CIFilter.colorControls()
        grayscale.inputImage = image
        grayscale.saturation = 0
        guard let gray = grayscale.outputImage else { return image }

        let closing = CIFilter.morphologyMaximum()
        closing.inputImage = gray
        closing.radius = 9
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = closing.outputImage?.clampedToExtent()
        blur.radius = 25
        guard let background = blur.outputImage?.cropped(to: gray.extent) else { return image }

        let divide = CIFilter.divideBlendMode()
        divide.inputImage = gray
        divide.backgroundImage = background
        return divide.outputImage?.cropped(to: gray.extent) ?? image
    }

    /// Picks the rotation (0/90/180/270) that yields the most confident text.
    /// Only runs the expensive check when the upright reading looks poor.
    private func correctOrientation(_ image: CGImage) -> CGImage? {
        func score(_ orientation: CGImagePropertyOrientation) -> Float {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])
            guard (try? handler.perform([request])) != nil, let results = request.results else { return 0 }
            return results.compactMap { $0.topCandidates(1).first?.confidence }.reduce(0, +)
        }
        let upright = score(.up)
        guard upright < 3 else { return nil }
        let candidates: [CGImagePropertyOrientation] = [.right, .down, .left]
        guard let best = candidates.map({ ($0, score($0)) }).max(by: { $0.1 < $1.1 }), best.1 > upright * 1.5 else { return nil }
        let rotated = CIImage(cgImage: image).oriented(best.0)
        return context.createCGImage(rotated, from: rotated.extent)
    }
}
