import Foundation
import SwiftData
import B2FCore

/// Sample content for SwiftUI previews, UI tests (`-UITestSeedData`) and App Store screenshots.
@MainActor
enum PreviewData {
    static func populate(_ context: ModelContext) {
        let book = BookEntity(title: "English File Intermediate", author: "Oxford", targetLanguage: .english,
                              nativeLanguage: .persian, source: .pdf)
        book.status = .ready
        book.progress = 1
        book.pageCount = 12
        context.insert(book)

        let unit = UnitEntity(title: "Unit 1", order: 0)
        unit.book = book
        context.insert(unit)

        let vocabularyBlock = LayoutBlock(kind: .vocabularyList, pageIndex: 0,
                                          lines: ["resilient – مقاوم", "commute – رفت و آمد"],
                                          rows: [["resilient", "مقاوم"], ["commute", "رفت و آمد"]],
                                          boundingBox: .zero, confidence: 0.94)
        let lessonNode = LessonNode(title: "Lesson 1A – Mood food",
                                    sections: [LessonSection(kind: .vocabulary, title: "Vocabulary", blocks: [vocabularyBlock])],
                                    pageRange: 0...3)
        let lesson = LessonEntity(node: lessonNode, order: 0)
        lesson.generationStatus = .ready
        lesson.unit = unit
        context.insert(lesson)

        let page = PageEntity(index: 0, ocrText: "Vocabulary\nresilient – مقاوم\ncommute – رفت و آمد",
                              analyzed: AnalyzedPage(pageIndex: 0, blocks: [vocabularyBlock], averageConfidence: 0.94,
                                                     lowConfidenceBlockIDs: []),
                              encryptedImage: nil)
        page.book = book
        context.insert(page)

        let drafts: [FlashcardDraft] = [
            FlashcardDraft(content: .vocabulary(VocabularyContent(
                term: "resilient", translation: "مقاوم، انعطاف‌پذیر", definition: "able to recover quickly from difficulties",
                ipa: "rɪˈzɪliənt", pronunciation: "ri-ZIL-ee-uhnt", partOfSpeech: "adjective",
                example: "Children are often remarkably resilient.", exampleTranslation: "کودکان اغلب به‌طور شگفت‌انگیزی مقاوم هستند.",
                synonyms: ["tough", "adaptable"], antonyms: ["fragile"])), tags: ["B2F"], priority: .essential),
            FlashcardDraft(content: .vocabulary(VocabularyContent(
                term: "commute", translation: "رفت و آمد روزانه", definition: "the journey to and from work",
                ipa: "kəˈmjuːt", pronunciation: "kuh-MYOOT", partOfSpeech: "noun / verb",
                example: "My commute takes about an hour.", exampleTranslation: "رفت و آمد من حدود یک ساعت طول می‌کشد.",
                synonyms: ["journey"], antonyms: [])), tags: ["B2F"], priority: .high),
            FlashcardDraft(content: .vocabulary(VocabularyContent(
                term: "nutritious", translation: "مغذی", definition: "containing many of the substances needed for health",
                ipa: "njuːˈtrɪʃəs", pronunciation: "noo-TRISH-uhs", partOfSpeech: "adjective",
                example: "Lentils are cheap and nutritious.", exampleTranslation: "عدس ارزان و مغذی است.",
                synonyms: ["nourishing"], antonyms: ["unhealthy"])), tags: ["B2F"], priority: .high),
            FlashcardDraft(content: .grammar(GrammarContent(
                rule: "Present simple vs. present continuous",
                explanation: "Use the present simple for habits and facts; the present continuous for actions happening now or temporary situations.",
                formula: "I work / I'm working",
                examples: ["I usually cook at home.", "I'm cooking pasta right now."],
                commonMistakes: ["✗ I am liking coffee → ✓ I like coffee"])), tags: ["B2F"], priority: .high),
            FlashcardDraft(content: .speaking(SpeakingContent(
                prompt: "Describe a typical meal in your country.",
                sampleAnswer: "In Iran, a typical lunch is rice with a stew such as ghormeh sabzi. We usually eat together as a family.",
                usefulPhrases: ["A typical … is …", "We usually …"])), tags: ["B2F"])
        ]
        for draft in drafts {
            let card = FlashcardEntity(draft: draft)
            card.lesson = lesson
            context.insert(card)
        }

        // A week of review history for the dashboard.
        let scheduler = FSRSScheduler()
        let calendar = Calendar.current
        for dayOffset in (0..<7).reversed() {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { continue }
            for (index, card) in (lesson.cards ?? []).enumerated() where (index + dayOffset) % 2 == 0 {
                let rating: Rating = index == 3 ? .hard : .good
                let before = card.scheduling
                let outcome = scheduler.review(before, rating: rating, at: day)
                card.scheduling = outcome.state
                let log = ReviewLogEntity(cardID: card.id, outcome: outcome, rating: rating, phaseBefore: before.phase,
                                          duration: 6, algorithm: .fsrs, at: day)
                log.card = card
                context.insert(log)
            }
        }
        try? context.save()
    }
}
