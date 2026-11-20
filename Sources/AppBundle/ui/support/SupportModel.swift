import Combine
import Foundation

@MainActor
public final class SupportModel: ObservableObject {
    public enum Section: String, CaseIterable, Identifiable, Sendable {
        case docs, announcements, agreements, contacts

        public var id: String { rawValue }

        var title: String {
            switch self {
                case .docs: L("Help & Documentation")
                case .announcements: L("Announcements")
                case .agreements: L("Agreements")
                case .contacts: L("Contact Support")
            }
        }

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
        guard !loadingSections.contains(section) else { return }
        await load(section)
    }

    public func reload(_ section: Section) async {
        guard !loadingSections.contains(section) else { return }
        await load(section)
    }

    /// Clears cached content and reloads the visible section after the app language changes.
    public func reloadForLocaleChange() async {
        loadedSections.removeAll()
        loadedLocales.removeAll()
        errors.removeAll()
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
        loadingSections.insert(section)
        errors[section] = nil
        defer { loadingSections.remove(section) }

        do {
            switch section {
                case .docs:
                    docs = try await client.docs(locale: locale).items
                    if selectedDocSlug == nil {
                        selectedDocSlug = docs.first?.key
                    }
                case .announcements:
                    activities = try await client.activities(locale: locale).items
                    if selectedActivityId == nil {
                        selectedActivityId = activities.first?.key
                    }
                case .agreements:
                    agreements = try await client.agreements(locale: locale)
                    if selectedAgreementSlug == nil {
                        selectedAgreementSlug = agreements.first?.key
                    }
                case .contacts:
                    contacts = try await client.contacts(locale: locale).items
            }
            loadedSections.insert(section)
            loadedLocales[section] = locale
        } catch is CancellationError {
            return
        } catch {
            errors[section] = error.localizedDescription
        }
    }
}
