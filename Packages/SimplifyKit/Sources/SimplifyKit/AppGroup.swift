import Foundation

/// The App Group shared by the app and its widgets, so both open the same store.
///
/// Each target writes its group id into Info.plist under `SimplifyAppGroup`, because the id
/// differs per platform: macOS uses `<TEAMID>.dev.yoom.simplify`, iOS `group.dev.yoom.simplify`.
public enum AppGroup {
    public static let infoKey = "SimplifyAppGroup"

    /// The group identifier from `bundle`, or `nil` when the build carries none
    /// (unsigned builds, unit tests).
    public static func identifier(in bundle: Bundle = .main) -> String? {
        identifier(from: bundle.object(forInfoDictionaryKey: infoKey) as? String)
    }

    /// Accepts the raw Info.plist value. An unsigned macOS build leaves the team prefix empty,
    /// which yields a bare `dev.yoom.simplify` (the bundle id prefix); that is not a usable group.
    static func identifier(from raw: String?) -> String? {
        guard let raw, !raw.isEmpty, !raw.hasPrefix("dev.yoom.") else { return nil }
        return raw
    }

    /// The shared container, or `nil` when the build carries no group id.
    /// On macOS a URL comes back even without the entitlement, so a non-nil result is not proof of access.
    public static func containerURL(in bundle: Bundle = .main) -> URL? {
        guard let id = identifier(in: bundle) else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
    }
}
