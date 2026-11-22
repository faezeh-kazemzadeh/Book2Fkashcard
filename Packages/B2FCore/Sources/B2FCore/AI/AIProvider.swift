import Foundation

/// JSON value used for schemas and loosely-typed payloads while staying `Sendable`.
public indirect enum JSONValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case integer(Int)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let v = try? container.decode(Bool.self) { self = .bool(v) }
        else if let v = try? container.decode(Int.self) { self = .integer(v) }
        else if let v = try? container.decode(Double.self) { self = .number(v) }
        else if let v = try? container.decode(String.self) { self = .string(v) }
        else if let v = try? container.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .number(let v): try container.encode(v)
        case .integer(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }
}

/// A named JSON Schema for structured output.
public struct StructuredOutputSchema: Sendable, Hashable {
    public var name: String
    public var schema: JSONValue
    public init(name: String, schema: JSONValue) {
        self.name = name
        self.schema = schema
    }
}

public struct AIRequest: Sendable {
    public var system: String
    public var user: String
    /// JPEG/PNG images for vision-capable models (AI-assisted OCR).
    public var images: [Data]
    public var schema: StructuredOutputSchema?
    public var maxOutputTokens: Int

    public init(system: String, user: String, images: [Data] = [], schema: StructuredOutputSchema? = nil,
                maxOutputTokens: Int = 4_000) {
        self.system = system
        self.user = user
        self.images = images
        self.schema = schema
        self.maxOutputTokens = maxOutputTokens
    }
}

public struct AIUsage: Sendable, Hashable {
    public var inputTokens: Int
    public var outputTokens: Int
}

public struct AIResponse: Sendable {
    public var text: String
    public var usage: AIUsage?

    public init(text: String, usage: AIUsage? = nil) {
        self.text = text
        self.usage = usage
    }

    /// Decodes structured output, tolerating Markdown code fences some models add.
    public func decode<T: Decodable>(_ type: T.Type) throws -> T {
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.hasPrefix("```") {
            body = body.replacingOccurrences(of: "^```[a-zA-Z]*\\n?", with: "", options: .regularExpression)
            body = body.replacingOccurrences(of: "\\n?```$", with: "", options: .regularExpression)
        }
        if let start = body.firstIndex(of: "{"), let end = body.lastIndex(of: "}"), start < end {
            body = String(body[start...end])
        }
        do {
            return try JSONDecoder().decode(T.self, from: Data(body.utf8))
        } catch {
            throw AIError.invalidResponse("could not decode \(T.self): \(error.localizedDescription)")
        }
    }
}

public struct AICapabilities: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let structuredOutput = AICapabilities(rawValue: 1 << 0)
    public static let vision = AICapabilities(rawValue: 1 << 1)
    public static let onDevice = AICapabilities(rawValue: 1 << 2)
    public static let largeContext = AICapabilities(rawValue: 1 << 3)
}

public enum AIError: Error, LocalizedError, Equatable {
    case notConfigured
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case server(status: Int, message: String)
    case refused(String)
    case truncated
    case invalidResponse(String)
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured: return "No AI provider is configured. Add one in Settings › AI."
        case .unauthorized: return "The AI provider rejected the API key."
        case .rateLimited: return "The AI provider is busy. Please try again in a moment."
        case .server(let status, let message): return "AI provider error \(status): \(message)"
        case .refused(let reason): return "The model declined the request: \(reason)"
        case .truncated: return "The AI response was cut off. Try a smaller lesson."
        case .invalidResponse(let reason): return "Unexpected AI response (\(reason))."
        case .unavailable(let reason): return reason
        }
    }
}

/// Every AI backend implements this. UI and generators depend only on the
/// protocol, so providers can be swapped (OpenAI, Azure OpenAI, a backend
/// proxy, Apple's on-device model, a future local model) without UI changes.
public protocol AIProvider: Sendable {
    var identifier: String { get }
    var capabilities: AICapabilities { get }
    func complete(_ request: AIRequest) async throws -> AIResponse
}

public enum AIProviderKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case openAI
    case azureOpenAI
    case proxy
    case appleOnDevice
    case localModel

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .openAI: return "OpenAI"
        case .azureOpenAI: return "Azure OpenAI"
        case .proxy: return "Book2Flashcards Cloud"
        case .appleOnDevice: return "Apple Intelligence (on-device)"
        case .localModel: return "Local model (coming soon)"
        }
    }
}

/// Placeholder for a future bundled/local model (e.g. a quantised LLM via MLX
/// or llama.cpp). Exists so configuration and routing are already wired.
public struct LocalModelProvider: AIProvider {
    public let identifier = "local"
    public let capabilities: AICapabilities = [.onDevice]
    public init() {}
    public func complete(_ request: AIRequest) async throws -> AIResponse {
        throw AIError.unavailable("Local models are not available in this version.")
    }
}

/// Deterministic provider for tests, previews and UI tests.
public struct MockAIProvider: AIProvider {
    public let identifier = "mock"
    public let capabilities: AICapabilities = [.structuredOutput, .vision]
    private let responder: @Sendable (AIRequest) throws -> String

    public init(responder: @escaping @Sendable (AIRequest) throws -> String) {
        self.responder = responder
    }

    public init(fixedResponse: String) {
        self.responder = { _ in fixedResponse }
    }

    public func complete(_ request: AIRequest) async throws -> AIResponse {
        AIResponse(text: try responder(request), usage: AIUsage(inputTokens: request.user.count / 4, outputTokens: 0))
    }
}
