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
    let items: KeychainItems

    public init(service: String = "dev.yoom.simplify.google") {
        items = KeychainItems(service: service)
    }

    public func load(_ accountID: String) -> GoogleTokens? {
        items.load(accountID).flatMap { try? JSONDecoder().decode(GoogleTokens.self, from: $0) }
    }

    public func save(_ tokens: GoogleTokens, for accountID: String) throws {
        try items.save(JSONEncoder().encode(tokens), for: accountID)
    }

    public func delete(_ accountID: String) {
        items.delete(accountID)
    }
}

/// Where each CalDAV account's app-specific password lives.
public protocol CalDAVCredentialStore: Sendable {
    /// Nil when there is no saved password; throws when the keychain cannot be read just now (locked).
    func load(_ accountID: String) throws -> CalDAVCredentials?
    func save(_ credentials: CalDAVCredentials, for accountID: String) throws
    func delete(_ accountID: String)
}

/// The login keychain, as for Google tokens, under its own service name.
public struct KeychainCredentialStore: CalDAVCredentialStore {
    let items: KeychainItems

    public init(service: String = "dev.yoom.simplify.icloud") {
        items = KeychainItems(service: service)
    }

    public func load(_ accountID: String) throws -> CalDAVCredentials? {
        try items.read(accountID).flatMap { try? JSONDecoder().decode(CalDAVCredentials.self, from: $0) }
    }

    public func save(_ credentials: CalDAVCredentials, for accountID: String) throws {
        try items.save(JSONEncoder().encode(credentials), for: accountID)
    }

    public func delete(_ accountID: String) {
        items.delete(accountID)
    }
}

/// Generic-password items of one service, keyed by account id.
struct KeychainItems: Sendable {
    let service: String

    func load(_ accountID: String) -> Data? {
        try? read(accountID)
    }

    /// Nil when there is no item; throws on any other failure (a locked keychain, a refused prompt).
    func read(_ accountID: String) throws -> Data? {
        var query = baseQuery(accountID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        return item as? Data
    }

    func save(_ data: Data, for accountID: String) throws {
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

    func delete(_ accountID: String) {
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
