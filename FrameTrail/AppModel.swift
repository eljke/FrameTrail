import Foundation
import Observation
import FrameTrailCore

@MainActor
@Observable
final class AppModel {
    let catalog = CatalogService()
    let auth = TMDBAuthService()
    let assistant = OnDeviceAssistant()
    let plots = WikiPlotService()
    let cloudAuth: SupabaseAuthService?
    let cloud: CloudLibraryService?
    let sync: LibrarySyncCoordinator?
    var cloudSession: SupabaseSession?
    var account: AuthAccount?
    var selectedTab = 0
    var featured: [MediaTitle] = []
    var catalogRevision = UUID()
    var alertMessage: String?
    var hasCatalogToken = false
    private var displayedTitles: [String: MediaTitle] = [:]
    private var displayedTitleOrder: [String] = []
    private var titleRequests: [String: UUID] = [:]
    var catalogLanguage: String { localeIdentifier == "ru_RU" ? "ru-RU" : "en-US" }
    var localeIdentifier: String {
        didSet {
            UserDefaults.standard.set(localeIdentifier, forKey: "assistant.locale")
            UserDefaults.standard.set(localeIdentifier.hasPrefix("ru") ? "ru" : "en", forKey: "app.language")
            catalogDidChange()
        }
    }

    init() {
        let defaultLocale = Locale.preferredLanguages.first?.hasPrefix("ru") == true ? "ru_RU" : "en_US"
        let arguments = ProcessInfo.processInfo.arguments
        let selectedLocale = arguments.contains("--uitesting")
            ? (arguments.contains("--language=en") ? "en_US" : "ru_RU")
            : (UserDefaults.standard.string(forKey: "app.language").map { $0 == "ru" ? "ru_RU" : "en_US" }
                ?? UserDefaults.standard.string(forKey: "assistant.locale") ?? defaultLocale)
        localeIdentifier = selectedLocale
        UserDefaults.standard.set(selectedLocale.hasPrefix("ru") ? "ru" : "en", forKey: "app.language")
        do {
            let config = try SupabaseConfiguration.bundled()
            let auth = SupabaseAuthService(config: config)
            let service = CloudLibraryService(config: config)
            cloudAuth = auth
            cloud = service
            sync = LibrarySyncCoordinator(auth: auth, cloud: service)
        } catch {
            cloudAuth = nil
            cloud = nil
            sync = nil
        }
    }

    var isUITesting: Bool { ProcessInfo.processInfo.arguments.contains("--uitesting") }

    func restoreAccount(library: LibraryStore) async {
        guard !isUITesting else { return }
        do { try await refreshAccountState(library: library) }
        catch { alertMessage = error.localizedDescription }
        guard let cloudAuth else { return }
        do { activate(try await cloudAuth.restoreSession(), library: library) }
        catch {
            activate(await cloudAuth.session, library: library)
            alertMessage = error.localizedDescription
        }
        await sync?.syncNow(library: library)
    }

    func refreshAccountState(library: LibraryStore) async throws {
        hasCatalogToken = try await auth.hasTMDBReadToken()
        let restored = try await auth.cachedAccount()
        account = restored
    }

    func loadFeatured() async {
        guard featured.isEmpty, !isUITesting else { return }
        let revision = catalogRevision
        do {
            let loaded = try await catalog.featured(language: catalogLanguage)
            try Task.checkCancellation()
            guard revision == catalogRevision else { return }
            featured = loaded
        }
        catch is CancellationError {} catch { alertMessage = error.localizedDescription }
    }

    func catalogDidChange() {
        assistant.translation.clearCache()
        featured = []
        displayedTitles = [:]
        displayedTitleOrder = []
        titleRequests = [:]
        catalogRevision = UUID()
    }

    func displayTitle(_ title: MediaTitle) -> MediaTitle { displayedTitles[title.id] ?? title }

    func localizeTitle(_ title: MediaTitle) async {
        guard !isUITesting, title.provider != "local", displayedTitles[title.id] == nil, titleRequests[title.id] == nil else { return }
        let requestID = UUID()
        let revision = catalogRevision
        titleRequests[title.id] = requestID
        defer { if titleRequests[title.id] == requestID { titleRequests[title.id] = nil } }
        let localized = (try? await catalog.localizedTitle(title, language: catalogLanguage)) ?? title
        guard !Task.isCancelled, revision == catalogRevision else { return }
        if displayedTitleOrder.count >= 128 {
            displayedTitles[displayedTitleOrder.removeFirst()] = nil
        }
        displayedTitleOrder.append(title.id)
        displayedTitles[title.id] = localized
    }

    func finishAuthorization(library: LibraryStore) async throws {
        let authorized = try await auth.completeAuthorization()
        account = authorized
    }

    func signOut(library: LibraryStore) async {
        do { try await auth.logout() }
        catch { alertMessage = error.localizedDescription }
        do { try await refreshAccountState(library: library) }
        catch { alertMessage = error.localizedDescription }
    }

    func signInFrameTrail(email: String, password: String, createAccount: Bool, library: LibraryStore) async throws -> Bool {
        guard let cloudAuth else { throw SupabaseAuthError.notConfigured }
        let session: SupabaseSession?
        if createAccount { session = try await cloudAuth.signUp(email: email, password: password) }
        else { session = try await cloudAuth.signIn(email: email, password: password) }
        guard let session else { return false }
        activate(session, library: library)
        await sync?.syncNow(library: library)
        return true
    }

    func signOutFrameTrail(library: LibraryStore) async {
        guard let cloudAuth else { return }
        sync?.activate(accountID: nil)
        do { try await cloudAuth.signOut() }
        catch { alertMessage = error.localizedDescription }
        activate(await cloudAuth.session, library: library)
    }

    func deleteFrameTrailAccount(library: LibraryStore) async throws {
        guard let cloudAuth, let cloud, let session = try await cloudAuth.currentSession() else {
            throw SupabaseAuthError.sessionExpired
        }
        let accountID = library.activeAccountID
        sync?.activate(accountID: nil)
        do { try await cloud.deleteAccount(accessToken: session.accessToken) }
        catch {
            sync?.activate(accountID: accountID)
            throw error
        }
        // The server has already removed the account and revoked its refresh sessions.
        try? await cloudAuth.signOut()
        defer { activate(nil, library: library) }
        if library.activeAccountID == accountID { try library.eraseCurrentAccount() }
    }

    private func activate(_ session: SupabaseSession?, library: LibraryStore) {
        cloudSession = session
        let id = session.map { LibrarySyncCoordinator.accountID($0.userID) } ?? "guest"
        if library.activeAccountID != id { assistant.translation.clearCache(); library.switchAccount(id) }
        sync?.activate(accountID: session == nil ? nil : id)
    }
}
