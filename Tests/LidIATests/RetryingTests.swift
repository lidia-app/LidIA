import Testing
import Foundation
@testable import LidIA

import os

/// Thread-safe attempt counter for use in @Sendable closures.
private final class AttemptCounter: Sendable {
    private let _value = OSAllocatedUnfairLock(initialState: 0)
    var value: Int { _value.withLock { $0 } }
    @discardableResult
    func increment() -> Int { _value.withLock { $0 += 1; return $0 } }
}

@Suite("Retrying")
struct RetryingTests {

    // MARK: - RetryClassifier

    @Test("URLError.timedOut is retryable")
    func urlErrorTimedOutRetryable() {
        #expect(RetryClassifier.isRetryable(URLError(.timedOut)))
    }

    @Test("URLError.cannotConnectToHost is retryable")
    func urlErrorCannotConnectRetryable() {
        #expect(RetryClassifier.isRetryable(URLError(.cannotConnectToHost)))
    }

    @Test("URLError.networkConnectionLost is retryable")
    func urlErrorConnectionLostRetryable() {
        #expect(RetryClassifier.isRetryable(URLError(.networkConnectionLost)))
    }

    @Test("URLError.notConnectedToInternet is retryable")
    func urlErrorNotConnectedRetryable() {
        #expect(RetryClassifier.isRetryable(URLError(.notConnectedToInternet)))
    }

    @Test("URLError.dnsLookupFailed is retryable")
    func urlErrorDnsRetryable() {
        #expect(RetryClassifier.isRetryable(URLError(.dnsLookupFailed)))
    }

    @Test("URLError.secureConnectionFailed is retryable")
    func urlErrorSecureConnectionRetryable() {
        #expect(RetryClassifier.isRetryable(URLError(.secureConnectionFailed)))
    }

    @Test("URLError.cancelled is NOT retryable")
    func urlErrorCancelledNotRetryable() {
        #expect(!RetryClassifier.isRetryable(URLError(.cancelled)))
    }

    @Test("URLError.badURL is NOT retryable")
    func urlErrorBadURLNotRetryable() {
        #expect(!RetryClassifier.isRetryable(URLError(.badURL)))
    }

    @Test("Unknown error types are NOT retryable")
    func unknownErrorNotRetryable() {
        struct CustomError: Error {}
        #expect(!RetryClassifier.isRetryable(CustomError()))
    }

    // MARK: - isRetryableHTTP

    @Test("HTTP 408 Request Timeout is retryable")
    func http408Retryable() {
        #expect(RetryClassifier.isRetryableHTTP(statusCode: 408))
    }

    @Test("HTTP 429 Too Many Requests is retryable")
    func http429Retryable() {
        #expect(RetryClassifier.isRetryableHTTP(statusCode: 429))
    }

    @Test("HTTP 500-599 range is retryable")
    func http5xxRetryable() {
        for code in [500, 502, 503, 504, 599] {
            #expect(RetryClassifier.isRetryableHTTP(statusCode: code), "Expected \(code) to be retryable")
        }
    }

    @Test("HTTP 200 is NOT retryable")
    func http200NotRetryable() {
        #expect(!RetryClassifier.isRetryableHTTP(statusCode: 200))
    }

    @Test("HTTP 400 is NOT retryable")
    func http400NotRetryable() {
        #expect(!RetryClassifier.isRetryableHTTP(statusCode: 400))
    }

    @Test("HTTP 401 is NOT retryable")
    func http401NotRetryable() {
        #expect(!RetryClassifier.isRetryableHTTP(statusCode: 401))
    }

    @Test("HTTP 403 is NOT retryable")
    func http403NotRetryable() {
        #expect(!RetryClassifier.isRetryableHTTP(statusCode: 403))
    }

    // MARK: - RetryPolicy defaults

    @Test("networkDefault policy has sensible values")
    func networkDefaultPolicy() {
        let policy = RetryPolicy.networkDefault
        #expect(policy.maxAttempts == 3)
        #expect(policy.jitterRatio == 0.2)
    }

    // MARK: - withRetry behavior

    @Test("withRetry succeeds on first attempt")
    func withRetrySucceedsImmediately() async throws {
        let counter = AttemptCounter()
        let result = try await withRetry(
            policy: RetryPolicy(
                maxAttempts: 3,
                initialDelay: .milliseconds(1),
                maxDelay: .milliseconds(10),
                jitterRatio: 0,
                shouldRetry: { _ in true }
            )
        ) {
            counter.increment()
            return "success"
        }
        #expect(result == "success")
        #expect(counter.value == 1)
    }

    @Test("withRetry retries on retryable error and eventually succeeds")
    func withRetryRetriesAndSucceeds() async throws {
        let counter = AttemptCounter()
        let result = try await withRetry(
            policy: RetryPolicy(
                maxAttempts: 3,
                initialDelay: .milliseconds(1),
                maxDelay: .milliseconds(10),
                jitterRatio: 0,
                shouldRetry: { _ in true }
            )
        ) {
            let current = counter.increment()
            if current < 3 {
                throw URLError(.timedOut)
            }
            return "recovered"
        }
        #expect(result == "recovered")
        #expect(counter.value == 3)
    }

    @Test("withRetry throws immediately on non-retryable error")
    func withRetryNonRetryable() async {
        let counter = AttemptCounter()
        do {
            _ = try await withRetry(
                policy: RetryPolicy(
                    maxAttempts: 5,
                    initialDelay: .milliseconds(1),
                    maxDelay: .milliseconds(10),
                    jitterRatio: 0,
                    shouldRetry: { _ in false }
                )
            ) {
                counter.increment()
                throw LLMError.authenticationError("bad key")
            }
            #expect(Bool(false), "Should have thrown")
        } catch {
            #expect(counter.value == 1)
        }
    }

    @Test("withRetry respects maxAttempts limit")
    func withRetryMaxAttempts() async {
        let counter = AttemptCounter()
        do {
            _ = try await withRetry(
                policy: RetryPolicy(
                    maxAttempts: 2,
                    initialDelay: .milliseconds(1),
                    maxDelay: .milliseconds(10),
                    jitterRatio: 0,
                    shouldRetry: { _ in true }
                )
            ) { () -> String in
                counter.increment()
                throw URLError(.timedOut)
            }
            #expect(Bool(false), "Should have thrown")
        } catch {
            #expect(counter.value == 2)
        }
    }
}
