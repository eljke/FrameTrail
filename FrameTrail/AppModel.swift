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
    var alertMessage: String?
    var hasCatalogToken = false
    var localeIdentifier: String {
        didSet { UserDefaults.standard.set(localeIdentifier, forKey: "assistant.locale") }
    }

    init() {
        let defaultLocale = Locale.preferredLanguages.first?.hasPrefix("ru") == true ? "ru_RU" : "en_US"
        localeIdentifier = UserDefaults.standard.string(forKey: "assistant.locale") ?? defaultLocale
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
        do { featured = try await catalog.featured() }
        catch is CancellationError {} catch { alertMessage = error.localizedDescription }
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
        if library.activeAccountID == accountID { try library.eraseCurrentAccount() }
        activate(nil, library: library)
    }

    private func activate(_ session: SupabaseSession?, library: LibraryStore) {
        cloudSession = session
        let id = session.map { LibrarySyncCoordinator.accountID($0.userID) } ?? "guest"
        if library.activeAccountID != id { library.switchAccount(id) }
        sync?.activate(accountID: session == nil ? nil : id)
    }
}
