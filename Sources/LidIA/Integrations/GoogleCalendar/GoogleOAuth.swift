import AppKit
import Network
import Security

actor GoogleOAuth {
    private let clientID: String
    private let clientSecret: String
    private let authURL = "https://accounts.google.com/o/oauth2/v2/auth"
    private let tokenURL = "https://oauth2.googleapis.com/token"
    private let scope = "https://www.googleapis.com/auth/calendar.readonly"

    private(set) var accessToken: String?
    private(set) var refreshToken: String?
    private var tokenExpiry: Date?

    init(clientID: String, clientSecret: String) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.refreshToken = Self.loadFromKeychain(key: "lidia.google.refreshToken")
        self.accessToken = Self.loadFromKeychain(key: "lidia.google.accessToken")
        if let expiryInterval = UserDefaults.standard.object(forKey: "lidia.google.tokenExpiry") as? TimeInterval {
            self.tokenExpiry = Date(timeIntervalSince1970: expiryInterval)
        }
    }

    /// Start the OAuth2 authorization flow via loopback redirect.
    /// Opens the system browser, starts a temporary local HTTP server to capture the callback.
    @MainActor
    func authorize() async throws {
        // Capture actor-isolated lets before entering the closure.
        let capturedClientID = clientID
        let capturedAuthURL = authURL
        let capturedScope = scope

        let result: (code: String, redirectURI: String) = try await withCheckedThrowingContinuation { continuation in
            let listener: NWListener
            do {
                listener = try NWListener(using: .tcp, on: .any)
            } catch {
                continuation.resume(throwing: error)
                return
            }

            nonisolated(unsafe) var resumed = false
            let complete: @Sendable (Result<(code: String, redirectURI: String), Error>) -> Void = { result in
                guard !resumed else { return }
                resumed = true
                listener.cancel()
                continuation.resume(with: result)
            }

            // Timeout after 2 minutes so the listener doesn't hang forever
            DispatchQueue.main.asyncAfter(deadline: .now() + 120) {
                complete(.failure(OAuthError.timeout))
            }

            listener.newConnectionHandler = { connection in
                connection.start(queue: .main)
                connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                    defer { connection.cancel() }

                    guard let data,
                          let request = String(data: data, encoding: .utf8),
                          let firstLine = request.split(separator: "\r\n").first else {
                        complete(.failure(OAuthError.noCallback))
                        return
                    }

                    let parts = firstLine.split(separator: " ", maxSplits: 2)
                    guard parts.count >= 2,
                          let urlComponents = URLComponents(string: "http://localhost\(parts[1])"),
                          let code = urlComponents.queryItems?.first(where: { $0.name == "code" })?.value else {
                        let html = "<html><body style='font-family:system-ui;text-align:center;padding:40px'>"
                            + "<h2>Sign-in failed</h2><p>No authorization code received. You can close this tab.</p></body></html>"
                        let httpResponse = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\n\(html)"
                        connection.send(content: httpResponse.data(using: .utf8), completion: .contentProcessed { _ in })
                        complete(.failure(OAuthError.noAuthCode))
                        return
                    }

                    let html = "<html><body style='font-family:system-ui;text-align:center;padding:40px'>"
                        + "<h2>Signed in!</h2><p>You can close this tab and return to LidIA.</p></body></html>"
                    let httpResponse = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\n\(html)"
                    connection.send(content: httpResponse.data(using: .utf8), completion: .contentProcessed { _ in })

                    let redirectURI = "http://127.0.0.1:\(listener.port?.rawValue ?? 0)"
                    complete(.success((code: code, redirectURI: redirectURI)))
                }
            }

            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard let port = listener.port else {
                        complete(.failure(OAuthError.noCallback))
                        return
                    }
                    let redirectURI = "http://127.0.0.1:\(port.rawValue)"

                    var components = URLComponents(string: capturedAuthURL)!
                    components.queryItems = [
                        URLQueryItem(name: "client_id", value: capturedClientID),
                        URLQueryItem(name: "redirect_uri", value: redirectURI),
                        URLQueryItem(name: "response_type", value: "code"),
                        URLQueryItem(name: "scope", value: capturedScope),
                        URLQueryItem(name: "access_type", value: "offline"),
                        URLQueryItem(name: "prompt", value: "consent"),
                    ]

                    NSWorkspace.shared.open(components.url!)

                case .failed:
                    complete(.failure(OAuthError.noCallback))
                default:
                    break
                }
            }

            listener.start(queue: .main)
        }

        try await exchangeCodeForTokens(code: result.code, redirectURI: result.redirectURI)
    }

    /// Exchange authorization code for access + refresh tokens
    private func exchangeCodeForTokens(code: String, redirectURI: String) async throws {
        let body = [
            "code": code,
            "client_id": clientID,
            "client_secret": clientSecret,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code",
        ]
        let tokens = try await postTokenRequest(body: body)
        accessToken = tokens.accessToken
        Self.saveToKeychain(key: "lidia.google.accessToken", value: tokens.accessToken)

        let expiry = Date().addingTimeInterval(TimeInterval(tokens.expiresIn - 60))
        tokenExpiry = expiry
        UserDefaults.standard.set(expiry.timeIntervalSince1970, forKey: "lidia.google.tokenExpiry")

        if let refresh = tokens.refreshToken {
            refreshToken = refresh
            Self.saveToKeychain(key: "lidia.google.refreshToken", value: refresh)
        }
    }

    /// Refresh the access token using the stored refresh token
    func refreshAccessToken() async throws {
        guard let refreshToken else { throw OAuthError.noRefreshToken }
        let body = [
            "refresh_token": refreshToken,
            "client_id": clientID,
            "client_secret": clientSecret,
            "grant_type": "refresh_token",
        ]
        let tokens = try await postTokenRequest(body: body)
        accessToken = tokens.accessToken
        Self.saveToKeychain(key: "lidia.google.accessToken", value: tokens.accessToken)

        let expiry = Date().addingTimeInterval(TimeInterval(tokens.expiresIn - 60))
        tokenExpiry = expiry
        UserDefaults.standard.set(expiry.timeIntervalSince1970, forKey: "lidia.google.tokenExpiry")
    }

    /// Get a valid access token, refreshing if expired
    func validAccessToken() async throws -> String {
        if let token = accessToken, let expiry = tokenExpiry, Date() < expiry {
            return token
        }
        try await refreshAccessToken()
        guard let token = accessToken else { throw OAuthError.noAccessToken }
        return token
    }

    /// Sign out — clear all tokens
    func signOut() {
        accessToken = nil
        refreshToken = nil
        tokenExpiry = nil
        Self.saveToKeychain(key: "lidia.google.refreshToken", value: "")
        Self.saveToKeychain(key: "lidia.google.accessToken", value: "")
        UserDefaults.standard.removeObject(forKey: "lidia.google.tokenExpiry")
    }

    var isSignedIn: Bool {
        refreshToken != nil && !(refreshToken?.isEmpty ?? true)
    }

    // MARK: - Token Request

    private struct TokenResponse: Codable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Int
        let token_type: String

        var accessToken: String { access_token }
        var refreshToken: String? { refresh_token }
        var expiresIn: Int { expires_in }
    }

    private func postTokenRequest(body: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
            .map { key, value in
                let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
                return "\(encodedKey)=\(encodedValue)"
            }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OAuthError.tokenExchangeFailed(errorBody)
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    // MARK: - Keychain

    /// Stable service name so tokens survive code-signing changes across rebuilds.
    private static let keychainService = "io.lidia.app"

    nonisolated static func saveToKeychain(key: String, value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var addQuery = query
        addQuery[kSecValueData as String] = data
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    nonisolated static func loadFromKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        let value = String(data: data, encoding: .utf8)
        return (value?.isEmpty ?? true) ? nil : value
    }

    // MARK: - Errors

    enum OAuthError: Error, LocalizedError {
        case noCallback
        case noAuthCode
        case noRefreshToken
        case noAccessToken
        case timeout
        case tokenExchangeFailed(String)

        var errorDescription: String? {
            switch self {
            case .noCallback: "OAuth callback not received."
            case .noAuthCode: "No authorization code in callback."
            case .noRefreshToken: "No refresh token available. Please sign in again."
            case .noAccessToken: "No access token available."
            case .timeout: "Sign-in timed out. Please try again."
            case .tokenExchangeFailed(let msg): "Token exchange failed: \(msg)"
            }
        }
    }
}
