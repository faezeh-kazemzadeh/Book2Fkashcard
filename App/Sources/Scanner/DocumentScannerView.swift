import SwiftUI
import VisionKit
import PDFKit

/// Wraps VisionKit's document camera: live page detection, automatic capture,
/// auto-crop, perspective flattening and multi-page batch scanning.
struct DocumentScannerView: UIViewControllerRepresentable {
    var onComplete: ([UIImage]) -> Void
    var onCancel: () -> Void
    var onError: (Error) -> Void

    static var isSupported: Bool { VNDocumentCameraViewController.isSupported }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScannerView
        init(_ parent: DocumentScannerView) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let pages = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            parent.onComplete(pages)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            parent.onError(error)
        }
    }
}

/// Builds a PDF from scanned pages (users can share/keep the scan like in a scanner app).
enum ScanPDFBuilder {
    static func makePDF(from images: [UIImage], title: String) -> Data? {
        let document = PDFDocument()
        for (index, image) in images.enumerated() {
            guard let compressed = image.jpegData(compressionQuality: 0.75).flatMap(UIImage.init(data:)),
                  let page = PDFPage(image: compressed) else { continue }
            document.insert(page, at: index)
        }
        document.documentAttributes = [PDFDocumentAttribute.titleAttribute: title,
                                       PDFDocumentAttribute.creatorAttribute: "Book2Flashcards AI Pro"]
        return document.dataRepresentation()
    }
}
