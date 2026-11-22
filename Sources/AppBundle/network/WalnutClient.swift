import Common
import Foundation
import os

/// Read-only client for the public walnut portal APIs used by AirSpace.
///
/// The portal treats `air-space` as a tenant identified by `X-App-Code`. All endpoints used
/// here are public: they do not require a user session or an `Authorization` header.
public struct WalnutClient: Sendable {
    public static let shared = WalnutClient()

    public static let appCode = "air-space"
    public static let platform = "macos"

    /// Architecture names in release manifests that can run on this process's slice.
    public static var hostArchitectureAliases: Set<String> {
        #if arch(arm64)
            ["arm64", "aarch64"]
        #elseif arch(x86_64)
            ["x86_64", "x64", "amd64", "intel"]
        #else
            []
        #endif
    }

    /// Default production gateway. `WALNUT_BASE_URL` can point a build at another environment.
    public static let defaultBaseURL = URL(string: "https://walnut.ichaseu.com")!

    private let baseURL: URL
    private let session: URLSession
    private let logger = Logger(subsystem: aeroSpaceAppId, category: "WalnutClient")

    public init(baseURL: URL = WalnutClient.defaultBaseURL) {
        let environmentOverride = ProcessInfo.processInfo.environment["WALNUT_BASE_URL"]
            .flatMap { URL(string: $0) }
        self.baseURL = environmentOverride ?? baseURL

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 24
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration)
    }

    // MARK: - Endpoints

    public func checkForUpdate(versionCode: Int64, locale: String) async throws -> ReleaseCheckResponse {
        var query = [
            URLQueryItem(name: "platform", value: Self.platform),
            URLQueryItem(name: "locale", value: locale),
        ]
        if versionCode > 0 {
            query.append(URLQueryItem(name: "version_code", value: String(versionCode)))
        }
        return try await get("/portal/releases/check", query: query, locale: locale)
    }

    public func docs(locale: String, page: Int = 1, pageSize: Int = 100) async throws -> DocsResponse {
        let query = [
            URLQueryItem(name: "locale", value: locale),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "pageSize", value: String(pageSize)),
        ]
        return try await get("/portal/docs", query: query, locale: locale)
    }

    public func doc(identifier: String, locale: String) async throws -> DocDetail {
        let path = "/portal/doc/\(percentEncodedPathComponent(identifier))"
        return try await get(path, query: [URLQueryItem(name: "locale", value: locale)], locale: locale)
    }

    public func agreements(locale: String) async throws -> [AgreementItem] {
        try await get("/portal/agreements", query: [URLQueryItem(name: "locale", value: locale)], locale: locale)
    }

    // periphery:ignore - API endpoint kept for the planned detail view
    public func agreement(slug: String, locale: String) async throws -> AgreementItem {
        let path = "/portal/agreement/\(percentEncodedPathComponent(slug))"
        return try await get(path, query: [URLQueryItem(name: "locale", value: locale)], locale: locale)
    }

    public func activities(locale: String, page: Int = 1, pageSize: Int = 100) async throws -> ActivitiesResponse {
        let query = [
            URLQueryItem(name: "locale", value: locale),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "pageSize", value: String(pageSize)),
        ]
        return try await get("/portal/activities", query: query, locale: locale)
    }

    // periphery:ignore - API endpoint kept for the planned detail view
    public func activity(identifier: String, locale: String) async throws -> ActivityItem {
        let path = "/portal/activity/\(percentEncodedPathComponent(identifier))"
        return try await get(path, query: [URLQueryItem(name: "locale", value: locale)], locale: locale)
    }

    public func contacts(locale: String, scene: String? = nil) async throws -> ContactsResponse {
        var query = [URLQueryItem(name: "locale", value: locale)]
        if let scene = scene?.nilIfBlank {
            query.append(URLQueryItem(name: "scene", value: scene))
        }
        return try await get("/portal/contacts", query: query, locale: locale)
    }

    // MARK: - Transport

    private func get<T: Decodable & Sendable>(
        _ path: String,
        query: [URLQueryItem],
        locale: String,
    ) async throws -> T {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw WalnutError.invalidURL
        }
        components.percentEncodedPath = path
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw WalnutError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.appCode, forHTTPHeaderField: "X-App-Code")
        request.setValue(Self.platform, forHTTPHeaderField: "X-Platform")
        request.setValue(locale, forHTTPHeaderField: "X-Locale")
        request.setValue(locale, forHTTPHeaderField: "Accept-Language")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw WalnutError.invalidResponse
            }
            guard (200 ..< 300).contains(httpResponse.statusCode) else {
                throw WalnutError.http(statusCode: httpResponse.statusCode, payload: Self.decodeErrorPayload(data))
            }
            do {
                return try Self.makeDecoder().decode(T.self, from: data)
            } catch {
                logger.error("Failed to decode \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                throw WalnutError.decoding(error.localizedDescription)
            }
        } catch let error as WalnutError {
            throw error
        } catch {
            logger.error("Request to \(path, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            throw WalnutError.transport(error.localizedDescription)
        }
    }

    private func percentEncodedPathComponent(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        // The gateway serialises portal payloads in snake_case.
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    private static func decodeErrorPayload(_ data: Data) -> WalnutErrorPayload? {
        try? makeDecoder().decode(WalnutErrorPayload.self, from: data)
    }
}

// MARK: - Errors

public struct WalnutErrorPayload: Decodable, Sendable {
    public let message: String?
    // periphery:ignore - response schema field kept for API compatibility
    public let code: String?
    public let errorType: String?
    // periphery:ignore - response schema field kept for API compatibility
    public let detail: String?
    public let sourceService: String?
    // periphery:ignore - response schema field kept for API compatibility
    public let sourceComponent: String?
}

public enum WalnutError: Error, LocalizedError, Sendable {
    case invalidURL
    case invalidResponse
    case transport(String)
    case decoding(String)
    case http(statusCode: Int, payload: WalnutErrorPayload?)

    public var errorDescription: String? {
        switch self {
            case .invalidURL:
                "The support service address is invalid."
            case .invalidResponse:
                "The support service returned an invalid response."
            case .transport(let message):
                message
            case .decoding:
                "The support service returned data that AirSpace could not read."
            case .http(let statusCode, let payload):
                payload?.message?.nilIfBlank ?? "The support service returned HTTP \(statusCode)."
        }
    }
}

// MARK: - Version

public enum WalnutVersion {
    /// The portal compares `version_code` values, not version strings.
    ///
    /// This must match the `version_code` written into the signed release manifest:
    /// `major * 1_000_000 + minor * 1_000 + patch`, with minor and patch capped at 999.
    public static var currentCode: Int64 {
        code(from: aeroSpaceAppVersion)
    }

    public static func code(from version: String) -> Int64 {
        let numeric = version.split(separator: "-", maxSplits: 1).first.map(String.init) ?? version
        let parts = numeric.split(separator: ".").map { Int64($0) ?? 0 }
        let major = max(parts.getOrNil(atIndex: 0) ?? 0, 0)
        let minor = min(max(parts.getOrNil(atIndex: 1) ?? 0, 0), 999)
        let patch = min(max(parts.getOrNil(atIndex: 2) ?? 0, 0), 999)
        return major * 1_000_000 + minor * 1000 + patch
    }
}

// MARK: - Response models

extension WalnutClient {
    public struct ReleaseCheckResponse: Decodable, Sendable {
        public let available: Bool?
        // periphery:ignore - response schema field kept for API compatibility
        public let title: String?
        public let version: String?
        public let versionCode: Int64?
        public let releaseChannel: String?
        public let releaseNote: String?
        public let forceUpdate: Bool?
        public let artifacts: [ReleaseArtifact]?

        public var isAvailable: Bool { available ?? false }

        public var downloadURL: URL? {
            let usable = (artifacts ?? []).filter { $0.githubUrl?.nilIfBlank != nil }
            let preferred = usable.first { $0.isMacOS && $0.archMatchesHost }
                ?? usable.first { $0.isMacOS && $0.isUniversal }
                ?? usable.first { $0.isMacOS && $0.hasUnspecifiedArch }
                ?? usable.first { $0.hasUnspecifiedPlatform && $0.archMatchesHost }
                ?? usable.first { $0.hasUnspecifiedPlatform && $0.isUniversal }
                ?? usable.first { $0.isUniversal }
                ?? usable.first
            return preferred?.githubUrl?.nilIfBlank.flatMap { URL(string: $0) }
        }
    }

    public struct ReleaseArtifact: Decodable, Sendable {
        public let platform: String?
        public let arch: String?
        public let packageType: String?
        // periphery:ignore - response schema field kept for API compatibility
        public let filename: String?
        public let githubUrl: String?

        private static let macPlatformAliases: Set<String> = ["macos", "mac", "osx", "darwin"]
        private static let universalArchAliases: Set<String> = ["universal", "universal2", "any"]

        var isMacOS: Bool {
            guard let platform = platform?.nilIfBlank else { return false }
            return Self.macPlatformAliases.contains(platform.lowercased())
        }

        var hasUnspecifiedPlatform: Bool { platform?.nilIfBlank == nil }
        var hasUnspecifiedArch: Bool { arch?.nilIfBlank == nil }

        var isUniversal: Bool {
            guard let arch = arch?.nilIfBlank else { return false }
            return Self.universalArchAliases.contains(arch.lowercased())
        }

        var archMatchesHost: Bool {
            guard let arch = arch?.nilIfBlank else { return false }
            return WalnutClient.hostArchitectureAliases.contains(arch.lowercased())
        }
    }

    public struct DocsResponse: Decodable, Sendable {
        public let list: [DocListItem]?
        // periphery:ignore - response schema field kept for API compatibility
        public let total: Int64?

        public var items: [DocListItem] { list ?? [] }
    }

    public struct DocListItem: Decodable, Sendable {
        public let id: String?
        public let slug: String?
        // periphery:ignore - response schema field kept for API compatibility
        public let typeId: String?
        public let name: String?
        public let description: String?
        // periphery:ignore - response schema field kept for API compatibility
        public let coverImage: String?
        public let parentId: String?
        public let order: Int64?

        public var key: String { slug?.nilIfBlank ?? id?.nilIfBlank ?? name?.nilIfBlank ?? "" }
    }

    public struct DocDetail: Decodable, Sendable {
        // periphery:ignore - response schema field kept for API compatibility
        public let id: String?
        public let slug: String?
        // periphery:ignore - response schema field kept for API compatibility
        public let typeId: String?
        public let name: String?
        public let description: String?
        public let content: String?
        // periphery:ignore - response schema field kept for API compatibility
        public let coverImage: String?
    }

    public struct AgreementItem: Decodable, Sendable {
        public let id: String?
        public let name: String?
        public let slug: String?
        // periphery:ignore - response schema field kept for API compatibility
        public let typeId: String?
        public let typeName: String?
        public let description: String?
        public let content: String?
        public let externalUrl: String?

        public var key: String { slug?.nilIfBlank ?? id?.nilIfBlank ?? name?.nilIfBlank ?? "" }
    }

    public struct ActivitiesResponse: Decodable, Sendable {
        public let list: [ActivityItem]?
        // periphery:ignore - response schema field kept for API compatibility
        public let total: Int64?

        public var items: [ActivityItem] { list ?? [] }
    }

    public struct ActivityItem: Decodable, Sendable {
        public let id: String?
        public let slug: String?
        public let name: String?
        public let subName: String?
        public let description: String?
        public let content: String?
        // periphery:ignore - response schema field kept for API compatibility
        public let coverImage: String?
        public let externalUrl: String?
        // periphery:ignore - response schema field kept for API compatibility
        public let datetimeStart: Int64?
        // periphery:ignore - response schema field kept for API compatibility
        public let datetimeEnd: Int64?

        public var key: String { id?.nilIfBlank ?? slug?.nilIfBlank ?? name?.nilIfBlank ?? "" }
    }

    public struct ContactsResponse: Decodable, Sendable {
        public let list: [ContactChannel]?

        public var items: [ContactChannel] { list ?? [] }
    }

    public struct ContactChannel: Decodable, Sendable {
        public let id: String?
        public let code: String?
        // periphery:ignore - response schema field kept for API compatibility
        public let scene: String?
        public let sceneName: String?
        // periphery:ignore - response schema field kept for API compatibility
        public let sceneIcon: String?
        // periphery:ignore - response schema field kept for API compatibility
        public let sceneColor: String?
        public let channelType: String?
        // periphery:ignore - response schema field kept for API compatibility
        public let channelTypeName: String?
        public let name: String?
        public let description: String?
        public let value: String?
        public let linkUrl: String?
        public let imageUrl: String?
        public let icon: String?
        public let actions: [String]?
        // periphery:ignore - response schema field kept for API compatibility
        public let expireAt: Int64?
        // periphery:ignore - response schema field kept for API compatibility
        public let updatedAt: Int64?

        public var key: String { code?.nilIfBlank ?? id?.nilIfBlank ?? name?.nilIfBlank ?? "" }

        public var effectiveActions: [String] {
            let serverActions = (actions ?? []).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if !serverActions.isEmpty { return serverActions }
            switch channelType?.lowercased() {
                case "phone": return value?.nilIfBlank == nil ? [] : ["call"]
                case "email": return value?.nilIfBlank == nil ? [] : ["email"]
                case "url": return linkUrl?.nilIfBlank == nil ? [] : ["open"]
                default:
                    if linkUrl?.nilIfBlank != nil { return ["open"] }
                    if value?.nilIfBlank != nil { return ["copy_value"] }
                    return []
            }
        }

        public var callURL: URL? {
            guard let value = value?.nilIfBlank else { return nil }
            let number = value.filter { !$0.isWhitespace }
            return URL(string: "tel:\(number)")
        }

        public var emailURL: URL? {
            guard let value = value?.nilIfBlank else { return nil }
            return URL(string: "mailto:\(value)")
        }

        public var openURL: URL? {
            if let link = linkUrl?.nilIfBlank, let url = URL(string: link) { return url }
            if let value = value?.nilIfBlank, value.hasPrefix("http"), let url = URL(string: value) { return url }
            return nil
        }

        public var qrURL: URL? {
            guard let raw = imageUrl?.nilIfBlank else { return nil }
            return URL(string: raw)
        }

        public var defaultIcon: String {
            switch channelType?.lowercased() {
                case "phone": "phone"
                case "email": "envelope"
                case "wechat", "wechat_group", "wecom", "feishu_group", "qq", "qq_group": "message"
                case "url": "link"
                default: "bubble.left.and.bubble.right"
            }
        }

        public func actionTitle(_ action: String) -> String {
            switch action {
                case "call": L("Call")
                case "email": L("Email")
                case "open": L("Open")
                case "copy_value", "copy_link": L("Copy")
                case "qr": L("Show QR Code")
                default: action
            }
        }

        public func actionIcon(_ action: String) -> String {
            switch action {
                case "call": "phone"
                case "email": "envelope"
                case "open": "arrow.up.right.square"
                case "copy_value", "copy_link": "doc.on.doc"
                case "qr": "qrcode"
                default: "circle"
            }
        }
    }
}

// MARK: - Helpers

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
