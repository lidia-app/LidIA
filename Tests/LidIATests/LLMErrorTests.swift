import Testing
import Foundation
@testable import LidIA

@Suite("LLMError")
struct LLMErrorTests {

    // MARK: - Status Code Mapping

    @Test("httpError returns the provided status code")
    func httpErrorStatusCode() {
        let error = LLMError.httpError(statusCode: 503, message: "Service Unavailable")
        #expect(error.statusCode == 503)
    }

    @Test("authenticationError maps to 401")
    func authErrorStatusCode() {
        let error = LLMError.authenticationError("Invalid key")
        #expect(error.statusCode == 401)
    }

    @Test("rateLimited maps to 429")
    func rateLimitedStatusCode() {
        let error = LLMError.rateLimited(retryAfter: 30)
        #expect(error.statusCode == 429)
    }

    @Test("serverError maps to 500")
    func serverErrorStatusCode() {
        let error = LLMError.serverError("Internal error")
        #expect(error.statusCode == 500)
    }

    @Test("networkError returns -1 (no HTTP status)")
    func networkErrorStatusCode() {
        let error = LLMError.networkError(URLError(.timedOut))
        #expect(error.statusCode == -1)
    }

    @Test("decodingError returns -1")
    func decodingErrorStatusCode() {
        let error = LLMError.decodingError(URLError(.cannotDecodeContentData))
        #expect(error.statusCode == -1)
    }

    @Test("modelNotFound returns -1")
    func modelNotFoundStatusCode() {
        let error = LLMError.modelNotFound("gpt-99")
        #expect(error.statusCode == -1)
    }

    // MARK: - Error Descriptions

    @Test("httpError description includes status code and message")
    func httpErrorDescription() {
        let error = LLMError.httpError(statusCode: 404, message: "Not Found")
        let desc = error.errorDescription ?? ""
        #expect(desc.contains("404"))
        #expect(desc.contains("Not Found"))
    }

    @Test("httpError description without message shows just code")
    func httpErrorDescriptionNoMessage() {
        let error = LLMError.httpError(statusCode: 502, message: nil)
        let desc = error.errorDescription ?? ""
        #expect(desc == "HTTP 502")
    }

    @Test("rateLimited description includes retry interval when present")
    func rateLimitedDescriptionWithRetry() {
        let error = LLMError.rateLimited(retryAfter: 60)
        let desc = error.errorDescription ?? ""
        #expect(desc.contains("60"))
        #expect(desc.contains("Retry"))
    }

    @Test("rateLimited description without retry interval")
    func rateLimitedDescriptionNoRetry() {
        let error = LLMError.rateLimited(retryAfter: nil)
        let desc = error.errorDescription ?? ""
        #expect(desc == "Rate limited.")
    }

    @Test("modelNotFound description includes model name")
    func modelNotFoundDescription() {
        let error = LLMError.modelNotFound("llama-999b")
        let desc = error.errorDescription ?? ""
        #expect(desc.contains("llama-999b"))
    }

    @Test("contextLengthExceeded has meaningful description")
    func contextLengthDescription() {
        let error = LLMError.contextLengthExceeded
        let desc = error.errorDescription ?? ""
        #expect(desc.lowercased().contains("context length"))
    }

    @Test("providerUnavailable includes provider name")
    func providerUnavailableDescription() {
        let error = LLMError.providerUnavailable("Ollama")
        let desc = error.errorDescription ?? ""
        #expect(desc.contains("Ollama"))
    }

    @Test("streamingError includes message")
    func streamingErrorDescription() {
        let error = LLMError.streamingError("Connection reset")
        let desc = error.errorDescription ?? ""
        #expect(desc.contains("Connection reset"))
    }

    @Test("invalidResponse passes through message directly")
    func invalidResponseDescription() {
        let error = LLMError.invalidResponse("Empty body")
        #expect(error.errorDescription == "Empty body")
    }

    @Test("All error cases produce non-nil descriptions")
    func allCasesHaveDescriptions() {
        let errors: [LLMError] = [
            .networkError(URLError(.notConnectedToInternet)),
            .httpError(statusCode: 400, message: "Bad Request"),
            .decodingError(URLError(.cannotDecodeContentData)),
            .authenticationError("bad key"),
            .rateLimited(retryAfter: 10),
            .modelNotFound("test"),
            .contextLengthExceeded,
            .serverError("oops"),
            .providerUnavailable("test"),
            .streamingError("fail"),
            .invalidResponse("invalid"),
        ]

        for error in errors {
            #expect(error.errorDescription != nil, "Missing description for: \(error)")
            #expect(!error.errorDescription!.isEmpty, "Empty description for: \(error)")
        }
    }

    // MARK: - Retryable Error Detection (via RetryClassifier)

    @Test("rateLimited is retryable")
    func rateLimitedIsRetryable() {
        let error = LLMError.rateLimited(retryAfter: 5)
        #expect(RetryClassifier.isRetryable(error))
    }

    @Test("serverError is retryable")
    func serverErrorIsRetryable() {
        let error = LLMError.serverError("Internal")
        #expect(RetryClassifier.isRetryable(error))
    }

    @Test("providerUnavailable is retryable")
    func providerUnavailableIsRetryable() {
        let error = LLMError.providerUnavailable("Ollama")
        #expect(RetryClassifier.isRetryable(error))
    }

    @Test("httpError with 5xx is retryable")
    func httpError5xxIsRetryable() {
        let error = LLMError.httpError(statusCode: 502, message: "Bad Gateway")
        #expect(RetryClassifier.isRetryable(error))
    }

    @Test("httpError with 429 is retryable")
    func httpError429IsRetryable() {
        let error = LLMError.httpError(statusCode: 429, message: "Too Many Requests")
        #expect(RetryClassifier.isRetryable(error))
    }

    @Test("httpError with 408 is retryable")
    func httpError408IsRetryable() {
        let error = LLMError.httpError(statusCode: 408, message: "Timeout")
        #expect(RetryClassifier.isRetryable(error))
    }

    @Test("authenticationError is NOT retryable")
    func authErrorNotRetryable() {
        let error = LLMError.authenticationError("bad key")
        #expect(!RetryClassifier.isRetryable(error))
    }

    @Test("modelNotFound is NOT retryable")
    func modelNotFoundNotRetryable() {
        let error = LLMError.modelNotFound("gpt-99")
        #expect(!RetryClassifier.isRetryable(error))
    }

    @Test("decodingError is NOT retryable")
    func decodingErrorNotRetryable() {
        let error = LLMError.decodingError(URLError(.cannotDecodeContentData))
        #expect(!RetryClassifier.isRetryable(error))
    }

    @Test("httpError with 400 is NOT retryable")
    func httpError400NotRetryable() {
        let error = LLMError.httpError(statusCode: 400, message: "Bad Request")
        #expect(!RetryClassifier.isRetryable(error))
    }

    @Test("httpError with 404 is NOT retryable")
    func httpError404NotRetryable() {
        let error = LLMError.httpError(statusCode: 404, message: "Not Found")
        #expect(!RetryClassifier.isRetryable(error))
    }
}
