import Foundation

/// Generic async retry policy with exponential backoff + jitter.
struct RetryPolicy: Sendable {
    let maxAttempts: Int
    let initialDelay: Duration
    let maxDelay: Duration
    let jitterRatio: Double
    let shouldRetry: @Sendable (Error) -> Bool

    static let networkDefault = RetryPolicy(
        maxAttempts: 3,
        initialDelay: .milliseconds(300),
        maxDelay: .seconds(4),
        jitterRatio: 0.2,
        shouldRetry: { error in
            RetryClassifier.isRetryable(error)
        }
    )
}

enum RetryClassifier {
    static func isRetryable(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut,
                 .cannotFindHost,
                 .cannotConnectToHost,
                 .networkConnectionLost,
                 .dnsLookupFailed,
                 .notConnectedToInternet,
                 .internationalRoamingOff,
                 .callIsActive,
                 .dataNotAllowed,
                 .secureConnectionFailed:
                return true
            default:
                return false
            }
        }

        if let llmError = error as? LLMError {
            switch llmError {
            case .httpError(let statusCode, _):
                return isRetryableHTTP(statusCode: statusCode)
            case .rateLimited:
                return true
            case .serverError:
                return true
            case .providerUnavailable:
                return true
            default:
                return false
            }
        }

        if let calendarError = error as? GoogleCalendarClient.CalendarError {
            switch calendarError {
            case .httpError(let statusCode, _):
                return isRetryableHTTP(statusCode: statusCode)
            default:
                return false
            }
        }

        return false
    }

    static func isRetryableHTTP(statusCode: Int) -> Bool {
        statusCode == 408 || statusCode == 429 || (500...599).contains(statusCode)
    }
}

@discardableResult
func withRetry<T>(
    policy: RetryPolicy = .networkDefault,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    precondition(policy.maxAttempts > 0, "RetryPolicy.maxAttempts must be > 0")

    var attempt = 0
    var nextDelay = policy.initialDelay
    var lastError: Error?

    while attempt < policy.maxAttempts {
        attempt += 1
        do {
            return try await operation()
        } catch {
            lastError = error
            let shouldRetry = attempt < policy.maxAttempts && policy.shouldRetry(error)
            guard shouldRetry else {
                throw error
            }

            let delay = addJitter(to: nextDelay, ratio: policy.jitterRatio)
            try await Task.sleep(for: delay)

            // Exponential backoff capped at maxDelay.
            nextDelay = minDuration(doubleDuration(nextDelay), policy.maxDelay)
        }
    }

    throw lastError ?? URLError(.unknown)
}

private func minDuration(_ lhs: Duration, _ rhs: Duration) -> Duration {
    lhs < rhs ? lhs : rhs
}

private func addJitter(to delay: Duration, ratio: Double) -> Duration {
    guard ratio > 0 else { return delay }

    let components = delay.components
    let totalNanos = max(0, components.seconds * 1_000_000_000 + Int64(components.attoseconds / 1_000_000_000))
    guard totalNanos > 0 else { return delay }

    let maxJitter = Double(totalNanos) * ratio
    let random = Double.random(in: -maxJitter...maxJitter)
    let jittered = max(0, Int64(Double(totalNanos) + random))
    return .nanoseconds(jittered)
}

private func doubleDuration(_ duration: Duration) -> Duration {
    let c = duration.components
    let nanos = max(0, c.seconds * 1_000_000_000 + Int64(c.attoseconds / 1_000_000_000))
    let doubled = min(Int64.max / 2, nanos * 2)
    return .nanoseconds(doubled)
}
