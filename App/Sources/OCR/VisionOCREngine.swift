import Foundation
import Vision
import UIKit
import B2FCore

/// Output of OCR for one page image.
struct OCRPageResult: Sendable {
    let pageIndex: Int
    let analyzed: AnalyzedPage
    let observations: [OCRTextObservation]
    let preprocessedJPEG: Data?
    let appliedSteps: [String]
    var plainText: String { analyzed.plainText }
}

/// Pluggable OCR backends: Vision today, cloud or bundled models later.
protocol OCRBackend: Sendable {
    func recognize(_ image: CGImage, plan: OCRLanguagePlan) async throws -> [OCRTextObservation]
}

/// Apple Vision text recognition (`VNRecognizeTextRequest`, accurate level).
struct VisionTextBackend: OCRBackend {
    func recognize(_ image: CGImage, plan: OCRLanguagePlan) async throws -> [OCRTextObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = plan.recognitionLanguages
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0.008
        request.automaticallyDetectsLanguage = plan.recognitionLanguages.count > 1
        // `perform` is synchronous; callers run this off the main actor.
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        try Task.checkCancellation()
        return (request.results ?? []).compactMap { observation -> OCRTextObservation? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let box = observation.boundingBox
            // Vision: normalised, bottom-left origin → core: top-left origin.
            let rect = B2FCore.NormalizedRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
            let text = plan.postProcess(candidate.string)
            return OCRTextObservation(text: text, boundingBox: rect,
                                      confidence: plan.adjustedConfidence(Double(candidate.confidence), text: text))
        }
    }

    static func supportedLanguages() -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        return (try? request.supportedRecognitionLanguages()) ?? ["en-US"]
    }
}

/// Orchestrates preprocessing → recognition → layout analysis, plus optional
/// AI-assisted correction for low-confidence pages (advanced OCR).
struct OCREngine: Sendable {
    var backend: any OCRBackend = VisionTextBackend()
    var preprocessor = ImagePreprocessor()
    var analyzer = LayoutAnalyzer()
    var aiCorrector: (any AIProvider)?

    func recognize(image: CGImage, orientation: CGImagePropertyOrientation = .up, pageIndex: Int,
                   languages: [StudyLanguage], mode: OCRMode, alreadyScanned: Bool = false) async throws -> OCRPageResult {
        let plan = OCRLanguagePlan(languages: languages, supportedByDevice: VisionTextBackend.supportedLanguages())
        let options: ImagePreprocessor.Options = alreadyScanned ? .alreadyScanned : (mode == .advanced ? .advanced : .basic)
        let prepared = preprocessor.process(image, orientation: orientation, options: options)

        var observations = try await backend.recognize(prepared.image, plan: plan)
        let boxes = mode == .advanced ? detectFramedBoxes(prepared.image) : []
        var analyzed = analyzer.analyze(pageIndex: pageIndex, observations: observations, boxes: boxes)

        // Advanced mode: let a vision-capable model re-transcribe weak pages.
        if mode == .advanced, let aiCorrector, aiCorrector.capabilities.contains(.vision),
           analyzed.averageConfidence < 0.6 || !plan.unsupported.isEmpty || plan.confidenceCeiling < 1,
           let jpeg = UIImage(cgImage: prepared.image).jpegData(compressionQuality: 0.7) {
            if let corrected = try? await aiCorrector.complete(AIRequest(
                system: PromptLibrary.ocrCorrectionSystemPrompt(languages: languages),
                user: "Transcribe this page.", images: [jpeg], maxOutputTokens: 4_000)) {
                var reanalysed = analyzer.analyze(pageIndex: pageIndex, plainText: plan.postProcess(corrected.text))
                // AI text has no per-line confidence; keep it below verified text.
                reanalysed.averageConfidence = 0.85
                for index in reanalysed.blocks.indices { reanalysed.blocks[index].confidence = 0.85 }
                reanalysed.lowConfidenceBlockIDs = []
                analyzed = reanalysed
                observations = []
            }
        }

        let jpeg = UIImage(cgImage: prepared.image).jpegData(compressionQuality: 0.6)
        return OCRPageResult(pageIndex: pageIndex, analyzed: analyzed, observations: observations,
                             preprocessedJPEG: jpeg, appliedSteps: prepared.appliedSteps)
    }

    /// Framed regions (grammar boxes, tip boxes) via rectangle detection.
    private func detectFramedBoxes(_ image: CGImage) -> [B2FCore.NormalizedRect] {
        let request = VNDetectRectanglesRequest()
        request.minimumSize = 0.15
        request.maximumObservations = 6
        request.minimumConfidence = 0.7
        request.minimumAspectRatio = 0.1
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil else { return [] }
        return (request.results ?? []).compactMap { rect in
            let box = rect.boundingBox
            // Skip the page border itself.
            guard box.width < 0.95 || box.height < 0.95 else { return nil }
            return B2FCore.NormalizedRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
        }
    }
}
