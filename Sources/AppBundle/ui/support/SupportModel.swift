import Combine
import Foundation

@MainActor
public final class SupportModel: ObservableObject {
    public enum Section: String, CaseIterable, Identifiable, Sendable {
        case docs, announcements, agreements, contacts

        public var id: String { rawValue }

        var systemImage: String {
            switch self {
                case .docs: "book"
                case .announcements: "megaphone"
                case .agreements: "doc.text"
                case .contacts: "bubble.left.and.bubble.right"
            }
        }
    }

    public static let shared = SupportModel()

    @Published public var section: Section = .docs
    @Published public private(set) var docs: [WalnutClient.DocListItem] = []
    @Published public private(set) var agreements: [WalnutClient.AgreementItem] = []
    @Published public private(set) var activities: [WalnutClient.ActivityItem] = []
    @Published public private(set) var contacts: [WalnutClient.ContactChannel] = []
    @Published public var selectedDocSlug: String?
    @Published public var selectedAgreementSlug: String?
    @Published public var selectedActivityId: String?
    @Published public private(set) var docDetail: WalnutClient.DocDetail?
    @Published public private(set) var isDocLoading = false
    @Published public private(set) var docError: String?
    @Published private var loadingSections: Set<Section> = []
    @Published private var errors: [Section: String] = [:]

    private let client: WalnutClient
    private var loadedSections: Set<Section> = []
    private var loadedLocales: [Section: String] = [:]
    private var loadingLocales: [Section: String] = [:]
    private var requestIDs: [Section: UUID] = [:]
    private var docRequestID = UUID()

    private init(client: WalnutClient = .shared) {
        self.client = client
    }

    public var selectedAgreement: WalnutClient.AgreementItem? {
        agreements.first { $0.key == selectedAgreementSlug }
    }

    public var selectedActivity: WalnutClient.ActivityItem? {
        activities.first { $0.key == selectedActivityId }
    }

    public func isLoading(_ section: Section) -> Bool {
        loadingSections.contains(section)
    }

    public func error(_ section: Section) -> String? {
        errors[section]
    }

    public func loadIfNeeded(_ section: Section) async {
        let locale = AppLanguage.selected.portalLocale
        if loadedSections.contains(section), loadedLocales[section] == locale { return }
        // Only skip when the request already in flight targets the current locale. A request for a
        // previous locale must not block the reload that a language change requests.
        if loadingSections.contains(section), loadingLocales[section] == locale { return }
        await load(section)
    }

    public func reload(_ section: Section) async {
        await load(section)
    }

    /// Clears cached content and reloads the visible section after the app language changes.
    public func reloadForLocaleChange() async {
        loadedSections.removeAll()
        loadedLocales.removeAll()
        errors.removeAll()
        docRequestID = UUID()
        isDocLoading = false
        docDetail = nil
        docError = nil
        selectedDocSlug = nil
        selectedAgreementSlug = nil
        selectedActivityId = nil
        await loadIfNeeded(section)
    }

    public func loadDoc(_ slug: String?) async {
        let requestID = UUID()
        docRequestID = requestID
        selectedDocSlug = slug

        guard let slug = slug?.nilIfBlank else {
            docDetail = nil
            docError = nil
            isDocLoading = false
            return
        }

        isDocLoading = true
        docError = nil
        docDetail = nil
        defer {
            if docRequestID == requestID {
                isDocLoading = false
            }
        }

        do {
            let detail = try await client.doc(identifier: slug, locale: AppLanguage.selected.portalLocale)
            guard docRequestID == requestID else { return }
            docDetail = detail
        } catch is CancellationError {
            return
        } catch {
            guard docRequestID == requestID else { return }
            docError = error.localizedDescription
        }
    }

    private func load(_ section: Section) async {
        let locale = AppLanguage.selected.portalLocale
        let requestID = UUID()
        requestIDs[section] = requestID
        loadingSections.insert(section)
        loadingLocales[section] = locale
        errors[section] = nil
        defer {
            if requestIDs[section] == requestID {
                loadingSections.remove(section)
                loadingLocales[section] = nil
            }
        }

        do {
            switch section {
                case .docs:
                    let items = try await client.docs(locale: locale).items
                    guard requestIDs[section] == requestID else { return }
                    docs = items
                    if selectedDocSlug == nil {
                        selectedDocSlug = items.first?.key
                    }
                case .announcements:
                    let items = try await client.activities(locale: locale).items
                    guard requestIDs[section] == requestID else { return }
                    activities = items
                    if selectedActivityId == nil {
                        selectedActivityId = items.first?.key
                    }
                case .agreements:
                    let items = try await client.agreements(locale: locale)
                    guard requestIDs[section] == requestID else { return }
                    agreements = items
                    if selectedAgreementSlug == nil {
                        selectedAgreementSlug = items.first?.key
                    }
                case .contacts:
                    let items = try await client.contacts(locale: locale).items
                    guard requestIDs[section] == requestID else { return }
                    contacts = items
            }
            loadedSections.insert(section)
            loadedLocales[section] = locale
        } catch is CancellationError {
            return
        } catch {
            guard requestIDs[section] == requestID else { return }
            errors[section] = error.localizedDescription
        }
    }
}
