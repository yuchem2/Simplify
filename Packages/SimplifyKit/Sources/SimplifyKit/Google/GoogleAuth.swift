import CryptoKit
import Foundation

/// OAuth 2.0 for Google with an iOS-type client: authorization code + PKCE, no client secret.
public struct GoogleOAuth: Sendable {
    public let clientID: String
    let http: HTTPTransport

    /// Calendar read/write (writing arrives in stage 4) plus the account's email for display.
    public static let scopes = ["openid", "email", "https://www.googleapis.com/auth/calendar"]

    public init(clientID: String, http: HTTPTransport = URLSessionTransport()) {
        self.clientID = clientID
        self.http = http
    }

    /// `com.googleusercontent.apps.<id>`: the reversed client id Google redirects back to.
    public var callbackScheme: String {
        "com.googleusercontent.apps." + clientID.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
    }

    public var redirectURI: String { callbackScheme + ":/oauthredirect" }

    public struct PKCE: Sendable {
        public let verifier: String
        public let challenge: String

        public init() {
            var bytes = [UInt8](repeating: 0, count: 32)
            _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            verifier = Data(bytes).base64URL
            challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        }
    }

    /// The sign-in page. `loginHint` pre-fills the email when reconnecting an account.
    public func authorizationURL(pkce: PKCE, state: String, loginHint: String? = nil) -> URL {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Self.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            // Always offer account choice, so "계정 추가" can pick a second account.
            URLQueryItem(name: "prompt", value: "select_account consent"),
        ] + (loginHint.map { [URLQueryItem(name: "login_hint", value: $0)] } ?? [])
        return components.url!
    }

    /// Reads `code` from the redirect, checking `state`.
    public func code(fromCallback url: URL, state: String) -> String? {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state else { return nil }
        return items.first(where: { $0.name == "code" })?.value
    }

    public func exchange(code: String, pkce: PKCE) async throws -> GoogleTokens {
        try await tokenRequest([
            "client_id": clientID, "code": code, "code_verifier": pkce.verifier,
            "grant_type": "authorization_code", "redirect_uri": redirectURI,
        ], keeping: nil)
    }

    /// A new access token. Google keeps the same refresh token, so it is carried over.
    public func refresh(_ tokens: GoogleTokens) async throws -> GoogleTokens {
        try await tokenRequest([
            "client_id": clientID, "refresh_token": tokens.refreshToken, "grant_type": "refresh_token",
        ], keeping: tokens)
    }

    /// Best effort: the account is removed locally whether or not Google answers.
    public func revoke(_ tokens: GoogleTokens) async {
        _ = try? await http.send(.form(URL(string: "https://oauth2.googleapis.com/revoke")!, ["token": tokens.refreshToken]))
    }

    private func tokenRequest(_ fields: [String: String], keeping old: GoogleTokens?) async throws -> GoogleTokens {
        let (data, response): (Data, HTTPURLResponse)
        do {
            (data, response) = try await http.send(.form(URL(string: "https://oauth2.googleapis.com/token")!, fields))
        } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .timedOut,
                                             .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed].contains(error.code) {
            // Waking from sleep with an expired token, before the network is back.
            throw CalendarSyncError.offline
        }
        if response.statusCode == 400 || response.statusCode == 401,
           (try? JSONDecoder().decode(TokenError.self, from: data))?.error == "invalid_grant" {
            throw CalendarSyncError.needsReauth
        }
        guard response.statusCode == 200 else { throw CalendarSyncError.http(status: response.statusCode) }
        let body = try JSONDecoder().decode(TokenResponse.self, from: data)
        // Google's consent screen lets people untick single permissions; without the calendar
        // one, sign-in succeeds but every calendar request fails.
        if let granted = body.scope?.split(separator: " "), !granted.contains("https://www.googleapis.com/auth/calendar") {
            throw CalendarSyncError.missingCalendarPermission
        }
        guard let refresh = body.refresh_token ?? old?.refreshToken else { throw CalendarSyncError.invalidResponse }
        return GoogleTokens(accessToken: body.access_token, refreshToken: refresh,
                            expiresAt: Date.now.addingTimeInterval(TimeInterval(body.expires_in ?? 3600) - 60),
                            idToken: body.id_token ?? old?.idToken)
    }

    private struct TokenResponse: Decodable {
        var access_token: String
        var refresh_token: String?
        var expires_in: Int?
        var id_token: String?
        /// Space-separated scopes actually granted.
        var scope: String?
    }

    private struct TokenError: Decodable { var error: String }
}

public struct GoogleTokens: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    public var idToken: String?

    public init(accessToken: String, refreshToken: String, expiresAt: Date, idToken: String? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.idToken = idToken
    }

    /// The account's stable id (`sub`) and email from the ID token. The token came straight from
    /// Google's token endpoint over TLS, so its signature is not checked again here.
    public var identity: (id: String, email: String)? {
        guard let payload = idToken?.split(separator: ".").dropFirst().first,
              let data = Data(base64URL: String(payload)),
              let claims = try? JSONDecoder().decode(Claims.self, from: data) else { return nil }
        return (claims.sub, claims.email ?? claims.sub)
    }

    private struct Claims: Decodable {
        var sub: String
        var email: String?
    }
}

extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    init?(base64URL: String) {
        var text = base64URL.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        text += String(repeating: "=", count: (4 - text.count % 4) % 4)
        self.init(base64Encoded: text)
    }
}
