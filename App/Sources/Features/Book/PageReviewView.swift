import SwiftUI
import B2FCore

struct PageReviewListView: View {
    let book: BookEntity
    var showAll = false

    var body: some View {
        let pages = showAll ? book.sortedPages : book.lowConfidencePages
        List(pages) { page in
            NavigationLink {
                PageReviewView(page: page)
            } label: {
                HStack {
                    Text("Page \(page.index + 1)")
                    Spacer()
                    Text(page.averageConfidence.formatted(.percent.precision(.fractionLength(0))))
                        .foregroundStyle(page.isLowConfidence ? .orange : .secondary)
                        .accessibilityLabel("Confidence \(page.averageConfidence.formatted(.percent.precision(.fractionLength(0))))")
                    if page.isUserCorrected {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.green).accessibilityLabel("Corrected")
                    }
                }
            }
        }
        .navigationTitle(showAll ? "Pages" : "Pages to review")
        .overlay {
            if pages.isEmpty { ContentUnavailableView("All pages look good", systemImage: "checkmark.circle") }
        }
    }
}

/// Shows the scanned page (decrypted on demand, offline) next to its OCR text,
/// highlights low-confidence blocks, and lets the user correct the text.
struct PageReviewView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    let page: PageEntity
    @State private var text = ""
    @State private var image: UIImage?
    @State private var zoom: CGFloat = 1

    var body: some View {
        let layout = sizeClass == .regular ? AnyLayout(HStackLayout(spacing: 16)) : AnyLayout(VStackLayout(spacing: 16))
        layout {
            if let image {
                ScrollView([.horizontal, .vertical]) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 600 * zoom)
                        .overlay { lowConfidenceOverlay }
                }
                .gesture(MagnifyGesture().onChanged { zoom = min(max($0.magnification, 0.5), 4) })
                .accessibilityLabel("Scanned page image")
            }
            VStack(alignment: .leading) {
                if page.isLowConfidence && !page.isUserCorrected { ConfidenceWarning() }
                TextEditor(text: $text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
                    .environment(\.layoutDirection, StudyLanguage.detectScript(of: text)?.isRightToLeft == true ? .rightToLeft : .leftToRight)
                    .accessibilityLabel("Recognised text")
            }
        }
        .padding()
        .navigationTitle("Page \(page.index + 1)")
        .toolbar {
            Button("Save") {
                try? model.repository.updateOCRText(page, text: text)
                model.toast = String(localized: "Saved. Use “Rebuild lessons” in the book menu to regenerate cards from corrected pages.")
            }
            .disabled(text == page.ocrText)
        }
        .task {
            text = page.ocrText
            if let sealed = page.encryptedImage, let data = try? model.files.open(sealed) {
                image = UIImage(data: data)
            }
        }
    }

    @ViewBuilder
    private var lowConfidenceOverlay: some View {
        if let analyzed = page.analyzed {
            GeometryReader { geometry in
                ForEach(analyzed.blocks.filter { analyzed.lowConfidenceBlockIDs.contains($0.id) }) { block in
                    let box = block.boundingBox
                    Rectangle()
                        .stroke(Color.orange, lineWidth: 2)
                        .background(Color.orange.opacity(0.12))
                        .frame(width: box.width * geometry.size.width, height: box.height * geometry.size.height)
                        .position(x: (box.x + box.width / 2) * geometry.size.width,
                                  y: (box.y + box.height / 2) * geometry.size.height)
                        .accessibilityHidden(true)
                }
            }
        }
    }
}
