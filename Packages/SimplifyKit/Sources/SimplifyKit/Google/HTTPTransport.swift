import Foundation

/// Sends one HTTP request. URLSession in the app; a fake in tests.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

/// Why syncing a calendar account stopped.
public enum CalendarSyncError: Error, Equatable, Sendable {
    /// The refresh token was revoked or expired; the person has to sign in again.
    case needsReauth
    /// The provider no longer accepts the saved sync token; fetch everything again.
    case syncTokenExpired
    /// Signed in, but the calendar permission was left unchecked on Google's consent screen.
    case missingCalendarPermission
    /// The Google Calendar API is not enabled for the app's Cloud project.
    case apiDisabled
    /// Access to the Mac's reminders was turned off in System Settings.
    case remindersAccessDenied
    case offline
    /// `reason` is the provider's machine-readable error reason, when it sent one.
    case http(status: Int, reason: String? = nil)
    case invalidResponse

    /// What to tell the person, in the app's voice.
    public var message: String {
        switch self {
        case .needsReauth: "로그인이 만료됐어요. 다시 연결해 주세요."
        case .missingCalendarPermission: "캘린더 권한이 허용되지 않았어요. 다시 연결하면서 캘린더 항목에 체크해 주세요."
        case .apiDisabled: "Google Cloud 프로젝트에서 Google Calendar API가 꺼져 있어요."
        case .remindersAccessDenied: "미리알림 접근이 꺼져 있어요. 시스템 설정 › 개인정보 보호 및 보안 › 미리알림에서 Simplify를 켜 주세요."
        case .offline: "인터넷에 연결되어 있지 않아요."
        case .syncTokenExpired: "일정을 처음부터 다시 받는 중이에요."
        case .http(let status, let reason): "서버가 요청을 거절했어요 (\(status)\(reason.map { " · " + $0 } ?? ""))."
        case .invalidResponse: "서버 응답을 읽지 못했어요."
        }
    }

    /// Only connecting the account again fixes it; the account is marked and syncing it stops.
    public var needsReconnect: Bool {
        self == .needsReauth || self == .missingCalendarPermission || self == .remindersAccessDenied
    }
}

extension URLRequest {
    /// `application/x-www-form-urlencoded` POST body.
    static func form(_ url: URL, _ fields: [String: String]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        request.httpBody = fields.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed)!)" }
            .joined(separator: "&")
            .data(using: .utf8)
        return request
    }
}
