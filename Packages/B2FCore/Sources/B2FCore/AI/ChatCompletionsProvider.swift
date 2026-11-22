import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Where and how to authenticate a Chat Completions call.
public enum ChatCompletionsEndpoint: Sendable, Hashable {
    /// api.openai.com (or a compatible base URL).
    case openAI(apiKey: String, model: String, baseURL: URL = URL(string: "https://api.openai.com/v1")!, organization: String? = nil)
    /// Azure OpenAI: `https://{resource}.openai.azure.com`, a deployment name and API version.
    case azure(endpoint: URL, deployment: String, apiVersion: String = "2024-10-21", apiKey: String)
    /// The app's own backend, which holds provider keys server-side and accepts
    /// a short-lived user token. Recommended for production (no keys on device).
    case proxy(baseURL: URL, model: String, token: String)

    var url: URL {
        switch self {
        case .openAI(_, _, let baseURL, _):
            return baseURL.appendingPathComponent("chat/completions")
        case .azure(let endpoint, let deployment, let apiVersion, _):
            var components = URLComponents(url: endpoint.appendingPathComponent("openai/deployments/\(deployment)/chat/completions"),
                                           resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "api-version", value: apiVersion)]
            return components.url!
        case .proxy(let baseURL, _, _):
            return baseURL.appendingPathComponent("v1/chat/completions")
        }
    }

    var model: String? {
        switch self {
        case .openAI(_, let model, _, _): return model
        case .azure: return nil // the deployment determines the model
        case .proxy(_, let model, _): return model
        }
    }

    func authorize(_ request: inout URLRequest) {
        switch self {
        case .openAI(let apiKey, _, _, let organization):
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            if let organization { request.setValue(organization, forHTTPHeaderField: "OpenAI-Organization") }
        case .azure(_, _, _, let apiKey):
            request.setValue(apiKey, forHTTPHeaderField: "api-key")
        case .proxy(_, _, let token):
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }
}

/// OpenAI-compatible Chat Completions provider used for OpenAI, Azure OpenAI
/// and the backend proxy. Supports strict JSON-schema structured outputs,
/// vision input and retry with exponential backoff.
public final class ChatCompletionsProvider: AIProvider, @unchecked Sendable {
    public let endpoint: ChatCompletionsEndpoint
    public let identifier: String
    public let capabilities: AICapabilities = [.structuredOutput, .vision, .largeContext]
    private let session: URLSession
    private let maxAttempts: Int
    private let baseDelay: TimeInterval

    public init(endpoint: ChatCompletionsEndpoint, session: URLSession = .shared,
                maxAttempts: Int = 3, baseDelay: TimeInterval = 1.5) {
        self.endpoint = endpoint
        self.session = session
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
        switch endpoint {
        case .openAI: identifier = "openai"
        case .azure: identifier = "azure-openai"
        case .proxy: identifier = "proxy"
        }
    }

    public func complete(_ request: AIRequest) async throws -> AIResponse {
        let urlRequest = try makeURLRequest(request)
        var attempt = 0
        while true {
            attempt += 1
            do {
                return try await send(urlRequest)
            } catch let error as AIError {
                let retryable: TimeInterval?
                switch error {
                case .rateLimited(let after): retryable = after ?? baseDelay * pow(2, Double(attempt - 1))
                case .server(let status, _) where status >= 500: retryable = baseDelay * pow(2, Double(attempt - 1))
                default: retryable = nil
                }
                guard let delay = retryable, attempt < maxAttempts else { throw error }
                try await Task.sleep(nanoseconds: UInt64(min(delay, 30) * 1_000_000_000))
            } catch let error as URLError where [URLError.Code.timedOut, .networkConnectionLost].contains(error.code) && attempt < maxAttempts {
                try await Task.sleep(nanoseconds: UInt64(baseDelay * 1_000_000_000))
            }
        }
    }

    // MARK: Request building

    func makeURLRequest(_ request: AIRequest) throws -> URLRequest {
        var body: [String: JSONValue] = [
            "messages": .array([
                .object(["role": .string("system"), "content": .string(request.system)]),
                .object(["role": .string("user"), "content": userContent(request)])
            ]),
            "max_completion_tokens": .integer(request.maxOutputTokens)
        ]
        if let model = endpoint.model { body["model"] = .string(model) }
        if let schema = request.schema {
            body["response_format"] = .object([
                "type": .string("json_schema"),
                "json_schema": .object([
                    "name": .string(schema.name),
                    "strict": .bool(true),
                    "schema": schema.schema
                ])
            ])
        }

        var urlRequest = URLRequest(url: endpoint.url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 120
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        endpoint.authorize(&urlRequest)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        urlRequest.httpBody = try encoder.encode(body)
        return urlRequest
    }

    private func userContent(_ request: AIRequest) -> JSONValue {
        guard !request.images.isEmpty else { return .string(request.user) }
        var parts: [JSONValue] = [.object(["type": .string("text"), "text": .string(request.user)])]
        for image in request.images {
            let mime = image.starts(with: [0x89, 0x50, 0x4E, 0x47]) ? "image/png" : "image/jpeg"
            parts.append(.object([
                "type": .string("image_url"),
                "image_url": .object(["url": .string("data:\(mime);base64,\(image.base64EncodedString())"),
                                      "detail": .string("high")])
            ]))
        }
        return .array(parts)
    }

    // MARK: Response handling

    private struct CompletionResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
                let refusal: String?
            }
            let message: Message
            let finish_reason: String?
        }
        struct Usage: Decodable {
            let prompt_tokens: Int
            let completion_tokens: Int
        }
        let choices: [Choice]
        let usage: Usage?
    }

    private struct ErrorEnvelope: Decodable {
        struct Body: Decodable { let message: String }
        let error: Body
    }

    private func send(_ request: URLRequest) async throws -> AIResponse {
        let (data, response) = try await session.b2fData(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse("no HTTP response") }

        switch http.statusCode {
        case 200..<300:
            break
        case 401, 403:
            throw AIError.unauthorized
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw AIError.rateLimited(retryAfter: retryAfter)
        default:
            let message = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data).error.message)
                ?? String(decoding: data.prefix(300), as: UTF8.self)
            throw AIError.server(status: http.statusCode, message: message)
        }

        let decoded: CompletionResponse
        do {
            decoded = try JSONDecoder().decode(CompletionResponse.self, from: data)
        } catch {
            throw AIError.invalidResponse("malformed completion")
        }
        guard let choice = decoded.choices.first else { throw AIError.invalidResponse("no choices") }
        if let refusal = choice.message.refusal, !refusal.isEmpty { throw AIError.refused(refusal) }
        if choice.finish_reason == "length" { throw AIError.truncated }
        guard let content = choice.message.content, !content.isEmpty else { throw AIError.invalidResponse("empty content") }
        return AIResponse(text: content, usage: decoded.usage.map {
            AIUsage(inputTokens: $0.prompt_tokens, outputTokens: $0.completion_tokens)
        })
    }
}
