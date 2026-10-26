import Foundation
import Security

/// Where each account's OAuth tokens live.
public protocol TokenStore: Sendable {
    func load(_ accountID: String) -> GoogleTokens?
    func save(_ tokens: GoogleTokens, for accountID: String) throws
    func delete(_ accountID: String)
}

/// The login keychain, one generic-password item per account. Tokens never touch the store files.
public struct KeychainTokenStore: TokenStore {
    let service: String

    public init(service: String = "dev.yoom.simplify.google") {
        self.service = service
    }

    public func load(_ accountID: String) -> GoogleTokens? {
        var query = baseQuery(accountID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(GoogleTokens.self, from: data)
    }

    public func save(_ tokens: GoogleTokens, for accountID: String) throws {
        let data = try JSONEncoder().encode(tokens)
        let status = SecItemUpdate(baseQuery(accountID) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery(accountID)
            add[kSecValueData as String] = data
            let added = SecItemAdd(add as CFDictionary, nil)
            guard added == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(added)) }
        } else if status != errSecSuccess {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    public func delete(_ accountID: String) {
        SecItemDelete(baseQuery(accountID) as CFDictionary)
    }

    private func baseQuery(_ accountID: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: accountID]
    }
}

/// Hands out a valid access token for one account, refreshing and saving it when it expires.
public actor GoogleSession {
    public let accountID: String
    let oauth: GoogleOAuth
    let store: TokenStore

    public init(accountID: String, oauth: GoogleOAuth, store: TokenStore) {
        self.accountID = accountID
        self.oauth = oauth
        self.store = store
    }

    public func accessToken(forceRefresh: Bool = false) async throws -> String {
        guard var tokens = store.load(accountID) else { throw CalendarSyncError.needsReauth }
        if forceRefresh || tokens.expiresAt <= .now {
            tokens = try await oauth.refresh(tokens)
            try store.save(tokens, for: accountID)
        }
        return tokens.accessToken
    }
}
