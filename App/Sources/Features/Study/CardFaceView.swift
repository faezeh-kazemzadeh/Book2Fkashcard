import SwiftUI
import B2FCore

/// Renders the question/answer of any card type with Dynamic Type, RTL-aware
/// text and VoiceOver-friendly grouping.
struct CardFaceView: View {
    let card: FlashcardEntity
    let showAnswer: Bool
    var onSpeak: () -> Void = {}
    @Environment(AppSettings.self) private var settings
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                front
                if showAnswer {
                    Divider()
                    back.transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(24)
        }
        .frame(maxWidth: 700, maxHeight: .infinity)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(alignment: .topLeading) {
            Label(card.kind.displayName, systemImage: card.kind.systemImage)
                .font(.caption).foregroundStyle(.secondary).padding(12)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var front: some View {
        switch card.content {
        case .vocabulary(let v):
            VStack(spacing: 8) {
                AdaptiveText(v.term, font: .largeTitle.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: 12) {
                    if !v.ipa.isEmpty {
                        Text("/\(v.ipa.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/")
                            .font(.title3).foregroundStyle(.secondary)
                            .accessibilityLabel("Pronunciation \(v.pronunciation.isEmpty ? v.ipa : v.pronunciation)")
                    }
                    Button(action: onSpeak) {
                        Image(systemName: model.speech.isSpeaking ? "speaker.wave.3.fill" : "speaker.wave.2")
                    }
                    .accessibilityLabel("Play pronunciation")
                    .keyboardShortcut("p", modifiers: [])
                    Menu {
                        Picker("Speed", selection: Bindable(settings).playbackSpeed) {
                            ForEach(PlaybackSpeed.allCases) { Text($0.label).tag($0) }
                        }
                        Picker("Accent", selection: Bindable(settings).accent) {
                            ForEach(EnglishAccent.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }
                    } label: {
                        Text(settings.playbackSpeed.label).font(.caption.monospacedDigit())
                    }
                    .accessibilityLabel("Playback speed \(settings.playbackSpeed.label)")
                }
            }
        case .grammar(let g):
            AdaptiveText(g.rule, font: .title.weight(.semibold))
        case .reading(let r):
            VStack(spacing: 12) {
                if !r.passageExcerpt.isEmpty {
                    AdaptiveText("“\(r.passageExcerpt)”", font: .callout.italic()).foregroundStyle(.secondary)
                }
                AdaptiveText(r.question, font: .title2.weight(.semibold))
            }
        case .speaking(let s):
            VStack(spacing: 8) {
                Image(systemName: "mic.circle").font(.largeTitle).foregroundStyle(.tint).accessibilityHidden(true)
                AdaptiveText(s.prompt, font: .title2.weight(.semibold))
            }
        case .basic(let b):
            AdaptiveText(b.front, font: .title2.weight(.semibold))
        }
    }

    @ViewBuilder
    private var back: some View {
        switch card.content {
        case .vocabulary(let v):
            VStack(spacing: 10) {
                AdaptiveText(v.translation, font: .title2)
                if !v.partOfSpeech.isEmpty { Text(v.partOfSpeech).font(.subheadline).foregroundStyle(.secondary) }
                if !v.definition.isEmpty { AdaptiveText(v.definition, font: .body) }
                if !v.example.isEmpty {
                    VStack(spacing: 4) {
                        AdaptiveText(v.example, font: .body.italic())
                        if !v.exampleTranslation.isEmpty {
                            AdaptiveText(v.exampleTranslation, font: .callout).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 4)
                }
                if !v.synonyms.isEmpty { labeledList("Synonyms", v.synonyms) }
                if !v.antonyms.isEmpty { labeledList("Antonyms", v.antonyms) }
            }
        case .grammar(let g):
            VStack(alignment: .leading, spacing: 10) {
                AdaptiveText(g.explanation, alignment: .leading)
                if !g.formula.isEmpty {
                    Text(g.formula).font(.body.monospaced()).padding(8)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
                ForEach(g.examples, id: \.self) { AdaptiveText("• " + $0, alignment: .leading) }
                if !g.commonMistakes.isEmpty {
                    Text("Common mistakes").font(.headline).padding(.top, 4)
                    ForEach(g.commonMistakes, id: \.self) { AdaptiveText($0, font: .callout, alignment: .leading) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .reading(let r):
            VStack(spacing: 8) {
                AdaptiveText(r.answer, font: .title3)
                if !r.explanation.isEmpty { AdaptiveText(r.explanation, font: .callout).foregroundStyle(.secondary) }
            }
        case .speaking(let s):
            VStack(alignment: .leading, spacing: 8) {
                AdaptiveText(s.sampleAnswer, alignment: .leading)
                ForEach(s.usefulPhrases, id: \.self) { AdaptiveText("• " + $0, font: .callout, alignment: .leading) }
            }
        case .basic(let b):
            VStack(spacing: 8) {
                AdaptiveText(b.back, font: .title3)
                if !b.extra.isEmpty { AdaptiveText(b.extra, font: .callout).foregroundStyle(.secondary) }
            }
        }
    }

    private func labeledList(_ title: LocalizedStringKey, _ items: [String]) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(items.joined(separator: ", ")).font(.callout)
        }
        .accessibilityElement(children: .combine)
    }
}
