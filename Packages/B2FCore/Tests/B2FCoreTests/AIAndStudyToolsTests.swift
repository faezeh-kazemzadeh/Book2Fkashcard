import XCTest
@testable import B2FCore

final class AIServiceTests: XCTestCase {
    static let validPayload = """
    ```json
    {"vocabulary":[
      {"term":"resilient","translation":"مقاوم","definition":"able to recover quickly","ipa":"rɪˈzɪliənt",
       "pronunciation":"ri-ZIL-ee-uhnt","partOfSpeech":"adjective","example":"Children are often very resilient.",
       "exampleTranslation":"کودکان اغلب بسیار مقاوم هستند.","synonyms":["tough"],"antonyms":["fragile"],
       "priority":"essential","confidence":0.95},
      {"term":"the","translation":"-","definition":"article","ipa":"ðə","pronunciation":"thuh","partOfSpeech":"article",
       "example":"","exampleTranslation":"","synonyms":[],"antonyms":[],"priority":"low","confidence":0.9}
    ],
    "grammar":[{"rule":"Present perfect","explanation":"Past action with present relevance.","formula":"have/has + past participle",
       "examples":["I have finished."],"commonMistakes":["✗ I have finished yesterday → ✓ I finished yesterday"],
       "priority":"high","confidence":0.9}],
    "reading":[{"question":"Where does Tom live?","answer":"With his grandparents.","explanation":"Paragraph 1.",
       "passageExcerpt":"Tom lives with his grandparents","confidence":0.9}],
    "speaking":[{"prompt":"Describe your family.","sampleAnswer":"I live with my parents.","usefulPhrases":["I get on well with"],"confidence":0.9}]}
    ```
    """

    func lesson() -> LessonNode {
        let block = LayoutBlock(kind: .paragraph, pageIndex: 0, lines: ["Tom lives with his grandparents. He is resilient."],
                                boundingBox: .zero, confidence: 0.9)
        return LessonNode(title: "Lesson 1B", sections: [LessonSection(kind: .reading, title: "Reading", blocks: [block])],
                          pageRange: 0...0)
    }

    func testGeneratorDecodesFiltersAndTags() async throws {
        let provider = MockAIProvider(fixedResponse: Self.validPayload)
        let generator = FlashcardGenerator(provider: provider, options: GenerationOptions())
        let result = try await generator.generate(for: lesson(), bookTitle: "English File", unitTitle: "Unit 1")
        XCTAssertTrue(result.usedAI)
        XCTAssertEqual(Set(result.drafts.map(\.kind)), [.vocabulary, .grammar, .reading, .speaking])
        XCTAssertFalse(result.drafts.contains { $0.content.frontText == "the" }, "quality filter must drop articles")
        let vocab = try XCTUnwrap(result.drafts.first { $0.kind == .vocabulary })
        XCTAssertEqual(vocab.priority, .essential)
        XCTAssertTrue(vocab.tags.contains("B2F::English_File::Unit_1::Lesson_1B"))
        XCTAssertEqual(result.drafts.first?.priority, .essential, "sorted by priority")
    }

    func testGeneratorRespectsRequestedKinds() async throws {
        var options = GenerationOptions()
        options.kinds = [.vocabulary]
        let generator = FlashcardGenerator(provider: MockAIProvider(fixedResponse: Self.validPayload), options: options)
        let result = try await generator.generate(for: lesson(), bookTitle: "B", unitTitle: "U")
        XCTAssertEqual(Set(result.drafts.map(\.kind)), [.vocabulary])
    }

    func testFallsBackToOfflineGenerationOnBadResponse() async throws {
        let vocabBlock = LayoutBlock(kind: .vocabularyList, pageIndex: 0, lines: ["commute - رفت و آمد"],
                                     rows: [["commute", "رفت و آمد"]], boundingBox: .zero, confidence: 1)
        let grammarBlock = LayoutBlock(kind: .grammarBox, pageIndex: 0,
                                       lines: ["Grammar", "Present simple", "We use it for habits.", "• I walk to work."],
                                       boundingBox: .zero, confidence: 1)
        let lesson = LessonNode(title: "L", sections: [
            LessonSection(kind: .vocabulary, title: "Vocabulary", blocks: [vocabBlock]),
            LessonSection(kind: .grammar, title: "Grammar", blocks: [grammarBlock])
        ], pageRange: 0...0)
        let generator = FlashcardGenerator(provider: MockAIProvider(fixedResponse: "not json"), options: GenerationOptions())
        let result = try await generator.generate(for: lesson, bookTitle: "B", unitTitle: "U")
        XCTAssertFalse(result.usedAI)
        XCTAssertFalse(result.warnings.isEmpty)
        guard case .vocabulary(let v)? = result.drafts.first(where: { $0.kind == .vocabulary })?.content else {
            return XCTFail("expected offline vocabulary card")
        }
        XCTAssertEqual(v.term, "commute")
        XCTAssertEqual(v.translation, "رفت و آمد")
        guard case .grammar(let g)? = result.drafts.first(where: { $0.kind == .grammar })?.content else {
            return XCTFail("expected offline grammar card")
        }
        XCTAssertEqual(g.rule, "Present simple")
        XCTAssertEqual(g.examples, ["• I walk to work."])
    }

    func testUnauthorizedIsSurfaced() async {
        let provider = MockAIProvider { _ in throw AIError.unauthorized }
        let generator = FlashcardGenerator(provider: provider, options: GenerationOptions())
        do {
            _ = try await generator.generate(for: lesson(), bookTitle: "B", unitTitle: "U")
            XCTFail("expected unauthorized")
        } catch {
            XCTAssertEqual(error as? AIError, .unauthorized)
        }
    }

    func testOpenAIRequestShape() throws {
        let provider = ChatCompletionsProvider(endpoint: .openAI(apiKey: "sk-test", model: "gpt-test"))
        let request = try provider.makeURLRequest(AIRequest(system: "sys", user: "hi", images: [Data([0x89, 0x50, 0x4E, 0x47])],
                                                            schema: PromptLibrary.cardGenerationSchema))
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "gpt-test")
        let format = try XCTUnwrap(body["response_format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let parts = try XCTUnwrap(messages[1]["content"] as? [[String: Any]])
        XCTAssertEqual(parts.count, 2)
        let imageURL = (parts[1]["image_url"] as? [String: Any])?["url"] as? String
        XCTAssertTrue(imageURL?.hasPrefix("data:image/png;base64,") ?? false)
    }

    func testAzureRequestShape() throws {
        let provider = ChatCompletionsProvider(endpoint: .azure(endpoint: URL(string: "https://res.openai.azure.com")!,
                                                                deployment: "cards", apiKey: "azure-key"))
        let request = try provider.makeURLRequest(AIRequest(system: "s", user: "u"))
        XCTAssertEqual(request.url?.absoluteString,
                       "https://res.openai.azure.com/openai/deployments/cards/chat/completions?api-version=2024-10-21")
        XCTAssertEqual(request.value(forHTTPHeaderField: "api-key"), "azure-key")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        XCTAssertNil(body["model"])
    }

    func testStrictSchemaRequiresEveryProperty() {
        guard case .object(let root) = PromptLibrary.cardGenerationSchema.schema,
              case .object(let properties)? = root["properties"],
              case .array(let required)? = root["required"] else { return XCTFail() }
        XCTAssertEqual(Set(properties.keys), Set(required.compactMap { if case .string(let s) = $0 { return s } else { return nil } }))
        XCTAssertEqual(root["additionalProperties"], .bool(false))
    }

    func testLessonRefinerAppliesTitlesAndKinds() async throws {
        let outline = BookOutline(units: [UnitNode(title: "Unit 1", lessons: [
            LessonNode(title: "Lesson 1", sections: [LessonSection(kind: .general, title: "Words", blocks: [])], pageRange: 0...1)
        ])])
        let provider = MockAIProvider(fixedResponse: #"{"lessons":[{"index":0,"title":"1A Mood food","sectionKinds":["vocabulary"]}]}"#)
        let refined = try await AILessonRefiner(provider: provider).refine(outline)
        XCTAssertEqual(refined.units[0].lessons[0].title, "1A Mood food")
        XCTAssertEqual(refined.units[0].lessons[0].sections[0].kind, .vocabulary)
    }
}

final class QuizEngineTests: XCTestCase {
    struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    let cards: [QuizCardInput] = [
        ("abandon", "رها کردن", "They had to abandon the car."),
        ("commute", "رفت و آمد", "My commute takes an hour."),
        ("resilient", "مقاوم", "She is resilient."),
        ("budget", "بودجه", "We need a budget.")
    ].map { QuizCardInput(id: UUID(), content: .vocabulary(VocabularyContent(term: $0.0, translation: $0.1, example: $0.2,
                                                                              exampleTranslation: "ترجمه"))) }

    func testMultipleChoiceHasOneCorrectOptionAndDistinctDistractors() {
        var engine = QuizEngine(generator: SeededGenerator(state: 42))
        let questions = engine.makeQuiz(type: .multipleChoice, cards: cards)
        XCTAssertEqual(questions.count, 4)
        for question in questions {
            guard case .choice(let options, let index) = question.format else { return XCTFail() }
            XCTAssertEqual(options.count, 4)
            XCTAssertEqual(Set(options).count, 4)
            XCTAssertEqual(QuizEngine.grade(choice: index, question: question), .correct)
        }
    }

    func testFillInTheBlank() {
        XCTAssertEqual(QuizEngine.blank(term: "abandon", in: "They abandoned the car."), "They _____ the car.")
        var engine = QuizEngine(generator: SeededGenerator(state: 1))
        let questions = engine.makeQuiz(type: .fillInTheBlank, cards: cards)
        XCTAssertTrue(questions.allSatisfy { $0.prompt.contains("_____") })
    }

    func testTypedGradingTolerance() {
        XCTAssertEqual(QuizEngine.grade("resilient", accepted: ["resilient"]), .correct)
        XCTAssertEqual(QuizEngine.grade("Resilient!", accepted: ["resilient"]), .correct)
        XCTAssertEqual(QuizEngine.grade("resilent", accepted: ["resilient"]), .almostCorrect(expected: "resilient"))
        XCTAssertEqual(QuizEngine.grade("cafe", accepted: ["café"]), .almostCorrect(expected: "café"))
        XCTAssertEqual(QuizEngine.grade("cat", accepted: ["car"]), .incorrect(expected: "car"))
        XCTAssertEqual(QuizEngine.grade("", accepted: ["car"]), .incorrect(expected: "car"))
    }

    func testSpokenGradingUsesContentOverlap() {
        let expected = "I usually commute to work by train every morning"
        XCTAssertEqual(QuizEngine.gradeSpoken(transcript: "I usually commute to work by train every morning", expected: expected), .correct)
        XCTAssertFalse(QuizEngine.gradeSpoken(transcript: "hello there", expected: expected).isAcceptable)
    }

    func testGrammarChallengeFromCommonMistakes() {
        let grammar = QuizCardInput(id: UUID(), content: .grammar(GrammarContent(
            rule: "Past simple", commonMistakes: ["✗ I have seen him yesterday → ✓ I saw him yesterday"])))
        var engine = QuizEngine(generator: SeededGenerator(state: 7))
        let questions = engine.makeQuiz(type: .grammarChallenge, cards: [grammar])
        XCTAssertEqual(questions.count, 1)
        guard case .choice(let options, let index) = questions[0].format else { return XCTFail() }
        XCTAssertEqual(options[index], "I saw him yesterday")
    }
}

final class SearchIndexTests: XCTestCase {
    func testPrefixDiacriticAndPersianSearch() {
        let index = SearchIndex()
        let bookID = UUID()
        index.upsert(SearchDocument(id: UUID(), scope: .vocabulary, title: "résilient", body: "able to recover", bookID: bookID))
        index.upsert(SearchDocument(id: UUID(), scope: .ocrText, title: "Page 3", body: "کتاب‌ها را بخوانید و resilience", bookID: bookID))
        index.upsert(SearchDocument(id: UUID(), scope: .grammar, title: "Present perfect", body: "have + past participle"))

        XCTAssertEqual(index.search("resil").count, 2)
        XCTAssertEqual(index.search("resil", scopes: [.vocabulary]).count, 1)
        XCTAssertEqual(index.search("كتابها").first?.document.scope, .ocrText)
        XCTAssertEqual(index.search("present partic").first?.document.scope, .grammar)
        XCTAssertTrue(index.search("zzz").isEmpty)
    }

    func testUpsertReplacesAndRemoveDeletes() {
        let index = SearchIndex()
        let id = UUID()
        index.upsert(SearchDocument(id: id, scope: .vocabulary, title: "old", body: ""))
        index.upsert(SearchDocument(id: id, scope: .vocabulary, title: "new", body: ""))
        XCTAssertTrue(index.search("old").isEmpty)
        XCTAssertEqual(index.search("new").count, 1)
        index.remove(id: id, scope: .vocabulary)
        XCTAssertTrue(index.search("new").isEmpty)
        XCTAssertEqual(index.count, 0)
    }
}
