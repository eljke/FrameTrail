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
    }

    var isUITesting: Bool { ProcessInfo.processInfo.arguments.contains("--uitesting") }

    func restoreAccount(library: LibraryStore) async {
        guard !isUITesting else { return }
        do { try await refreshAccountState(library: library) }
        catch { alertMessage = error.localizedDescription }
    }

    func refreshAccountState(library: LibraryStore) async throws {
        hasCatalogToken = try await auth.hasTMDBReadToken()
        let restored = try await auth.cachedAccount()
        account = restored
        let accountID = restored.map { "tmdb-" + $0.id } ?? "guest"
        if library.activeAccountID != accountID { library.switchAccount(accountID) }
    }

    func loadFeatured() async {
        guard featured.isEmpty, !isUITesting else { return }
        do { featured = try await catalog.featured() }
        catch is CancellationError {} catch { alertMessage = error.localizedDescription }
    }

    func finishAuthorization(library: LibraryStore) async throws {
        let authorized = try await auth.completeAuthorization()
        library.switchAccount("tmdb-" + authorized.id)
        account = authorized
    }

    func signOut(library: LibraryStore) async {
        do { try await auth.logout() }
        catch { alertMessage = error.localizedDescription }
        do { try await refreshAccountState(library: library) }
        catch { alertMessage = error.localizedDescription }
    }
}
