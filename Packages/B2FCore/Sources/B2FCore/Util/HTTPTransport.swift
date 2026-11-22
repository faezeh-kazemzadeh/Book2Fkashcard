import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public extension URLSession {
    /// `data(for:)` that also works on Linux toolchains whose FoundationNetworking
    /// lacks the async overloads.
    func b2fData(for request: URLRequest) async throws -> (Data, URLResponse) {
        #if canImport(FoundationNetworking)
        return try await withCheckedThrowingContinuation { continuation in
            let task = dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, let response {
                    continuation.resume(returning: (data, response))
                } else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                }
            }
            task.resume()
        }
        #else
        return try await data(for: request)
        #endif
    }
}
