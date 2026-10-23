import Foundation
import Observation
import FrameTrailCore

@MainActor @Observable
final class LibrarySyncCoordinator {
    private(set) var isSyncing = false
    private(set) var conflicts: [LibrarySyncConflict] = []
    private(set) var status = L10n.text("Войди в аккаунт для синхронизации.")
    private(set) var lastSyncedAt: Date?
    private let auth: SupabaseAuthService
    private let cloud: CloudLibraryService
    private var activeAccountID: String?
    private var generation = UUID()
    private var pending: Task<Void, Never>?
    private var needsAnotherPass = false

    init(auth: SupabaseAuthService, cloud: CloudLibraryService) {
        self.auth = auth
        self.cloud = cloud
    }

    func activate(accountID: String?) {
        pending?.cancel()
        pending = nil
        generation = UUID()
        activeAccountID = accountID
        conflicts = []
        isSyncing = false
        lastSyncedAt = nil
        needsAnotherPass = false
        status = accountID == nil ? L10n.text("Гостевая библиотека хранится на устройстве.") : L10n.text("Готово к синхронизации.")
    }

    func schedule(library: LibraryStore) {
        guard activeAccountID == library.activeAccountID else { return }
        if isSyncing { needsAnotherPass = true; return }
        pending?.cancel()
        pending = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(1)) }
            catch { return }
            await self?.syncNow(library: library)
        }
    }

    func syncNow(library: LibraryStore) async {
        guard !isSyncing, let accountID = activeAccountID, accountID == library.activeAccountID else { return }
        guard library.canSync else { status = library.lastError ?? L10n.text("Библиотека недоступна для синхронизации."); return }
        let operation = generation
        isSyncing = true
        status = L10n.text("Сравниваю изменения…")
        defer {
            if operation == generation {
                isSyncing = false
                if needsAnotherPass { needsAnotherPass = false; schedule(library: library) }
            }
        }
        do {
            guard let session = try await auth.currentSession() else { throw SupabaseAuthError.sessionExpired }
            guard valid(operation, accountID: accountID, library: library), Self.accountID(session.userID) == accountID else { return }
            let remote = try await cloud.fetchAll(accessToken: session.accessToken)
            guard valid(operation, accountID: accountID, library: library) else { return }
            let plan = LibrarySyncPlanner.plan(local: library.cloudItems(), remote: remote, baseline: library.syncBaseline)
            try library.commitCloudChanges(applies: plan.applies, baseline: plan.nextBaseline)
            conflicts = plan.conflicts
            for upload in plan.uploads {
                try Task.checkCancellation()
                guard valid(operation, accountID: accountID, library: library) else { return }
                let record = try await cloud.put(mediaID: upload.mediaID, item: upload.payload, expectedRevision: upload.expectedRevision, accessToken: session.accessToken)
                guard valid(operation, accountID: accountID, library: library) else { return }
                guard let record else { throw CloudLibraryError.changedDuringSync }
                try library.recordSyncedCloudRecord(record)
            }
            lastSyncedAt = Date()
            status = conflicts.isEmpty ? L10n.text("Библиотека синхронизирована.") : L10n.text("Выбери версии для конфликтов: %@.", String(describing: conflicts.count))
        } catch is CancellationError {
            if operation == generation { status = L10n.text("Синхронизация прервана. Локальные изменения сохранены.") }
        } catch {
            if operation == generation { status = L10n.error(error) }
        }
    }

    func resolve(_ conflict: LibrarySyncConflict, keepLocal: Bool, library: LibraryStore) async {
        guard !isSyncing, let accountID = activeAccountID, accountID == library.activeAccountID,
              let remote = conflict.remote, remote.isValid,
              [.concurrentChanges, .initialDivergence].contains(conflict.reason) else { return }
        let operation = generation
        isSyncing = true
        defer { if operation == generation { isSyncing = false } }
        do {
            if keepLocal {
                guard let session = try await auth.currentSession() else { throw SupabaseAuthError.sessionExpired }
                guard valid(operation, accountID: accountID, library: library), Self.accountID(session.userID) == accountID else { return }
                let item = library.cloudItems().first { $0.id == conflict.mediaID }
                let record = try await cloud.put(mediaID: conflict.mediaID, item: item, expectedRevision: remote.revision, accessToken: session.accessToken)
                guard valid(operation, accountID: accountID, library: library) else { return }
                guard let record else { throw CloudLibraryError.changedDuringSync }
                try library.recordSyncedCloudRecord(record)
            } else {
                try library.applyCloudRecord(remote)
            }
            conflicts.removeAll { $0.id == conflict.id }
            status = L10n.text("Выбранная версия сохранена. Повтори синхронизацию для проверки.")
        } catch {
            if operation == generation { status = L10n.error(error) }
        }
    }

    static func accountID(_ id: UUID) -> String { "supabase-" + id.uuidString.lowercased() }

    private func valid(_ operation: UUID, accountID: String, library: LibraryStore) -> Bool {
        operation == generation && activeAccountID == accountID && library.activeAccountID == accountID && !Task.isCancelled
    }
}
