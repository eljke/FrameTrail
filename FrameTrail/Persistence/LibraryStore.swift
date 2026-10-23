import CryptoKit
import Foundation
import FrameTrailCore
import Observation

struct LibraryEntry: Identifiable, Codable, Hashable {
    var id: String { title.id }
    var title: MediaTitle
    var progress: WatchProgress
    var episodes: [Episode]
    var facts: [StoryFact]
    var chat: [ChatTurn]
    var reflections: [Reflection]
    var updatedAt: Date

    init(title: MediaTitle) {
        self.title = title
        progress = WatchProgress()
        episodes = []
        facts = []
        chat = []
        reflections = []
        updatedAt = Date()
    }
}

enum LibraryStoreError: LocalizedError {
    case tooLarge
    case unsupportedSchema
    case invalidData(String)
    case unreadableLibrary
    case unreadableSyncBaseline
    case syncUnavailable

    var errorDescription: String? {
        switch self {
        case .tooLarge:
            return "Файл библиотеки превышает лимит 10 МБ."
        case .unsupportedSchema:
            return "Версия библиотеки не поддерживается этим приложением."
        case .invalidData(let reason):
            return "Не удалось проверить библиотеку: \(reason)."
        case .unreadableLibrary:
            return "Файл библиотеки повреждён. Исходный файл сохранён; изменения заблокированы."
        case .unreadableSyncBaseline:
            return "История синхронизации повреждена. Библиотека доступна для чтения и экспорта; запись и синхронизация заблокированы."
        case .syncUnavailable:
            return "Синхронизация недоступна для гостевого или повреждённого аккаунта."
        }
    }
}

@MainActor @Observable
final class LibraryStore {
    private(set) var entries: [LibraryEntry] = []
    private(set) var lastError: String?
    private(set) var activeAccountID = "guest"
    private(set) var syncBaseline = LibrarySyncBaseline()
    private(set) var ratingUndo: RatingUndo?

    struct RatingUndo {
        let accountID: String
        let titleID: String
        let before: [Reflection]
        let after: [Reflection]
        let count: Int
    }

    private let directory: URL
    private var unreadableAccountIDs: Set<String> = []
    private var unreadableBaselineAccountIDs: Set<String> = []
    private static let maximumBytes = 10 * 1024 * 1024

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FrameTrail", isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
        do {
            try activateLoaded(try load(accountID: activeAccountID), accountID: activeAccountID)
        } catch {
            if !unreadableBaselineAccountIDs.contains(activeAccountID) {
                unreadableAccountIDs.insert(activeAccountID)
            }
            lastError = error.localizedDescription
        }
    }

    var isReadable: Bool { !unreadableAccountIDs.contains(activeAccountID) }
    var canSync: Bool {
        activeAccountID != "guest" && isReadable && !unreadableBaselineAccountIDs.contains(activeAccountID)
    }

    var bytesOnDisk: Int {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        return files.reduce(0) { total, url in
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true else { return total }
            return total + (values.fileSize ?? 0)
        }
    }

    func switchAccount(_ id: String) {
        guard Self.validIdentifier(id, maximum: 256) else {
            lastError = LibraryStoreError.invalidData("некорректный идентификатор аккаунта").localizedDescription
            return
        }
        ratingUndo = nil
        unreadableBaselineAccountIDs.remove(id)
        do {
            let loaded = try load(accountID: id)
            activeAccountID = id
            unreadableAccountIDs.remove(id)
            try activateLoaded(loaded, accountID: id)
        } catch {
            activeAccountID = id
            if !unreadableBaselineAccountIDs.contains(id) {
                entries = []
                syncBaseline = LibrarySyncBaseline()
                unreadableAccountIDs.insert(id)
            }
            lastError = error.localizedDescription
        }
    }

    func entry(for titleID: String) -> LibraryEntry? {
        entries.first { $0.id == titleID }
    }

    func dismissError() {
        lastError = nil
    }

    func add(_ title: MediaTitle) {
        guard entry(for: title.id) == nil else { return }
        commit(entries + [LibraryEntry(title: title)])
    }

    func addTitles(_ titles: [MediaTitle]) throws -> Int {
        do {
            var known = Set(entries.map(\.id))
            var next = entries
            for title in titles where known.insert(title.id).inserted { next.append(LibraryEntry(title: title)) }
            let added = next.count - entries.count
            try persist(next)
            entries = next
            lastError = nil
            return added
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    func update(_ entry: LibraryEntry) {
        var updated = entry
        updated.updatedAt = Date()
        var next = entries
        if let index = next.firstIndex(where: { $0.id == entry.id }) {
            next[index] = updated
        } else {
            next.append(updated)
        }
        commit(next)
    }

    func remove(_ titleID: String) {
        commit(entries.filter { $0.id != titleID })
    }

    func updateWithEpisodeRatings(_ entry: LibraryEntry, rating: Int, season: Int?, overwrite: Bool) {
        let plan = EpisodeRatingPlan(titleID: entry.id, episodes: entry.episodes, watchedEpisodeIDs: entry.progress.watchedEpisodeIDs,
                                     records: entry.reflections, rating: rating, season: season, overwrite: overwrite)
        var changed = entry
        changed.reflections = plan.records
        update(changed)
        if lastError == nil && plan.changedCount > 0 {
            ratingUndo = RatingUndo(accountID: activeAccountID, titleID: entry.id, before: entry.reflections, after: plan.records, count: plan.changedCount)
        }
    }

    func undoEpisodeRatings(for titleID: String) {
        guard let undo = ratingUndo, undo.accountID == activeAccountID, undo.titleID == titleID,
              var entry = entry(for: titleID) else { return }
        guard entry.reflections == undo.after else {
            ratingUndo = nil
            lastError = "Оценки уже изменились. Массовое действие нельзя отменить без потери новых записей."
            return
        }
        entry.reflections = undo.before
        update(entry)
        if lastError == nil { ratingUndo = nil }
    }

    func eraseCurrentAccount() throws {
        ratingUndo = nil
        let url = fileURL(accountID: activeAccountID)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        entries = []
        syncBaseline = LibrarySyncBaseline()
        unreadableAccountIDs.remove(activeAccountID)
        unreadableBaselineAccountIDs.remove(activeAccountID)
        lastError = nil
    }

    func clearChat(for titleID: String) {
        var next = entries
        guard let index = next.firstIndex(where: { $0.id == titleID }) else { return }
        next[index].chat = []
        next[index].updatedAt = Date()
        commit(next)
    }

    var downloadedMaterialBytes: Int {
        let encoder = JSONEncoder()
        return ((try? encoder.encode(entries.map(\.episodes)).count) ?? 0)
            + ((try? encoder.encode(entries.map(\.facts)).count) ?? 0)
    }

    func clearDownloadedMaterials() {
        var next = entries
        for index in next.indices {
            next[index].episodes = []
            next[index].facts = []
            next[index].updatedAt = Date()
        }
        commit(next)
    }

    func exportData() throws -> Data {
        guard !unreadableAccountIDs.contains(activeAccountID) else {
            throw LibraryStoreError.unreadableLibrary
        }
        return try Self.encode(entries)
    }

    func cloudItems() -> [CloudLibraryItem] {
        entries.map { CloudLibraryItem(title: $0.title, progress: $0.progress, reflections: $0.reflections) }
    }

    func applyCloudRecord(_ record: CloudLibraryRecord) throws {
        var baseline = syncBaseline
        baseline.records[record.mediaID] = record
        try commitCloudChanges(applies: [record], baseline: baseline)
    }

    func recordSyncedCloudRecord(_ record: CloudLibraryRecord) throws {
        var baseline = syncBaseline
        baseline.records[record.mediaID] = record
        try commitCloudChanges(applies: [], baseline: baseline)
    }

    /// Commits remote records and their acknowledged revisions in the same atomic file.
    func commitCloudChanges(applies: [CloudLibraryRecord], baseline: LibrarySyncBaseline) throws {
        do {
            guard canSync else { throw LibraryStoreError.syncUnavailable }
            try Self.validateBaseline(baseline)
            guard Set(syncBaseline.records.keys).isSubset(of: Set(baseline.records.keys)) else {
                throw LibraryStoreError.invalidData("история синхронизации не должна терять подтверждённые записи")
            }
            guard Set(applies.map(\.mediaID)).count == applies.count else {
                throw LibraryStoreError.invalidData("повторяющиеся облачные записи")
            }
            var next = entries
            for record in applies {
                try Self.validateRecord(record)
                guard baseline.records[record.mediaID] == record else {
                    throw LibraryStoreError.invalidData("облачная запись не соответствует истории синхронизации")
                }
                if record.deleted {
                    next.removeAll { $0.id == record.mediaID }
                } else if let item = record.payload {
                    var entry = next.first { $0.id == item.id } ?? LibraryEntry(title: item.title)
                    entry.title = item.title
                    entry.progress = item.progress
                    entry.reflections = item.reflections
                    entry.updatedAt = Date()
                    if let index = next.firstIndex(where: { $0.id == item.id }) { next[index] = entry }
                    else { next.append(entry) }
                }
            }
            let safe = Self.scopedEntries(clearingChatsOnRewind(next))
            try persist(safe, baseline: baseline)
            entries = safe
            syncBaseline = baseline
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    /// Merges a validated archive. More recent records win; equal timestamps retain local data.
    func importData(_ data: Data) throws {
        do {
            let imported = try Self.decode(data)
            var next = entries
            for entry in imported {
                if let index = next.firstIndex(where: { $0.id == entry.id }) {
                    if entry.updatedAt > next[index].updatedAt { next[index] = entry }
                } else {
                    next.append(entry)
                }
            }
            let safe = clearingChatsOnRewind(next)
            try persist(safe)
            entries = safe
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    private func commit(_ next: [LibraryEntry]) {
        do {
            let scoped = Self.scopedEntries(clearingChatsOnRewind(next))
            try persist(scoped)
            entries = scoped
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func persist(_ next: [LibraryEntry], baseline: LibrarySyncBaseline? = nil) throws {
        guard !unreadableAccountIDs.contains(activeAccountID) else {
            throw LibraryStoreError.unreadableLibrary
        }
        guard !unreadableBaselineAccountIDs.contains(activeAccountID) else {
            throw LibraryStoreError.unreadableSyncBaseline
        }
        let data = try Self.encode(next, baseline: baseline ?? syncBaseline)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS)
        try data.write(to: fileURL(accountID: activeAccountID), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: fileURL(accountID: activeAccountID), options: [.atomic])
        #endif
    }

    private func clearingChatsOnRewind(_ next: [LibraryEntry]) -> [LibraryEntry] {
        let previous = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0.progress) })
        return next.map { entry in
            guard let old = previous[entry.id] else { return entry }
            let reduced = (old.finished && !entry.progress.finished)
                || !old.watchedEpisodeIDs.isSubset(of: entry.progress.watchedEpisodeIDs)
            guard reduced else { return entry }
            var safe = entry
            safe.chat = []
            return safe
        }
    }

    private func load(accountID: String) throws -> Archive {
        let url = fileURL(accountID: accountID)
        guard FileManager.default.fileExists(atPath: url.path) else { return Archive(entries: []) }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        if let size = attributes[.size] as? NSNumber, size.intValue > Self.maximumBytes {
            throw LibraryStoreError.tooLarge
        }
        return try Self.decodeArchive(Data(contentsOf: url))
    }

    private func activateLoaded(_ archive: Archive, accountID: String) throws {
        entries = archive.entries
        syncBaseline = LibrarySyncBaseline()
        unreadableAccountIDs.remove(accountID)
        unreadableBaselineAccountIDs.remove(accountID)
        do {
            guard !archive.baselineUnreadable else { throw LibraryStoreError.unreadableSyncBaseline }
            let baseline = archive.syncBaseline ?? LibrarySyncBaseline()
            try Self.validateBaseline(baseline)
            syncBaseline = baseline
            lastError = nil
        } catch {
            unreadableBaselineAccountIDs.insert(accountID)
            throw LibraryStoreError.unreadableSyncBaseline
        }
    }

    private func fileURL(accountID: String) -> URL {
        let digest = SHA256.hash(data: Data(accountID.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("library-\(digest).json", isDirectory: false)
    }

    private struct Archive: Codable {
        var schemaVersion = 1
        var entries: [LibraryEntry]
        var syncBaseline: LibrarySyncBaseline?
        var baselineUnreadable = false

        private enum CodingKeys: String, CodingKey { case schemaVersion, entries, syncBaseline }

        init(entries: [LibraryEntry], syncBaseline: LibrarySyncBaseline? = nil) {
            self.entries = entries
            self.syncBaseline = syncBaseline
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
            entries = try container.decode([LibraryEntry].self, forKey: .entries)
            do { syncBaseline = try container.decodeIfPresent(LibrarySyncBaseline.self, forKey: .syncBaseline) }
            catch { baselineUnreadable = true; syncBaseline = nil }
        }
    }

    private static func decode(_ data: Data) throws -> [LibraryEntry] {
        try decodeArchive(data).entries
    }

    private static func decodeArchive(_ data: Data) throws -> Archive {
        guard data.count <= maximumBytes else { throw LibraryStoreError.tooLarge }
        var archive = try JSONDecoder().decode(Archive.self, from: data)
        guard archive.schemaVersion == 1 else { throw LibraryStoreError.unsupportedSchema }
        archive.entries = scopedEntries(archive.entries)
        try validate(archive.entries)
        return archive
    }

    private static func encode(_ entries: [LibraryEntry], baseline: LibrarySyncBaseline? = nil) throws -> Data {
        try validate(entries)
        if let baseline { try validateBaseline(baseline) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Archive(entries: entries, syncBaseline: baseline))
        guard data.count <= maximumBytes else { throw LibraryStoreError.tooLarge }
        return data
    }

    private static func validateBaseline(_ baseline: LibrarySyncBaseline) throws {
        guard baseline.records.count <= 10_000 else { throw LibraryStoreError.tooLarge }
        for (id, record) in baseline.records {
            guard id == record.mediaID else { throw LibraryStoreError.invalidData("неверный ключ истории синхронизации") }
            try validateRecord(record)
        }
    }

    private static func validateRecord(_ record: CloudLibraryRecord) throws {
        guard record.isValid, validIdentifier(record.mediaID, maximum: 256) else {
            throw LibraryStoreError.invalidData("некорректная облачная запись")
        }
        if let item = record.payload {
            var entry = LibraryEntry(title: item.title)
            entry.progress = item.progress
            entry.reflections = item.reflections
            try validate([entry])
        }
    }

    private static func scopedEntries(_ entries: [LibraryEntry]) -> [LibraryEntry] {
        entries.map { entry in
            var scoped = entry
            for index in scoped.facts.indices where scoped.facts[index].titleID == nil {
                scoped.facts[index].titleID = entry.id
            }
            return scoped
        }
    }

    private static func validate(_ entries: [LibraryEntry]) throws {
        guard entries.count <= 2_000, Set(entries.map(\.id)).count == entries.count else {
            throw LibraryStoreError.invalidData("слишком много произведений или повторяющиеся идентификаторы")
        }
        for entry in entries {
            let title = entry.title
            guard validIdentifier(title.id, maximum: 256), validIdentifier(title.provider, maximum: 64),
                  validIdentifier(title.providerID, maximum: 128), !title.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  title.title.count <= 512, (title.originalTitle?.count ?? 0) <= 512,
                  title.overview.count <= 50_000, validURL(title.posterURL), validURL(title.sourceURL),
                  entry.updatedAt.timeIntervalSince1970.isFinite else {
                throw LibraryStoreError.invalidData("некорректная карточка произведения")
            }
            guard entry.episodes.count <= 5_000, entry.facts.count <= 10_000, entry.chat.count <= 500,
                  entry.reflections.count <= 5_000, entry.progress.watchedEpisodeIDs.count <= 5_000,
                  entry.progress.watchedEpisodeIDs.allSatisfy({ validIdentifier($0, maximum: 256) }),
                  entry.progress.currentSeason.map({ $0 >= 0 && $0 <= 10_000 }) ?? true,
                  entry.progress.currentEpisode.map({ $0 >= 0 && $0 <= 100_000 }) ?? true else {
                throw LibraryStoreError.invalidData("превышен размер материалов или некорректный прогресс")
            }
            guard Set(entry.episodes.map(\.id)).count == entry.episodes.count,
                  Set(entry.facts.map(\.id)).count == entry.facts.count,
                  Set(entry.chat.map(\.id)).count == entry.chat.count,
                  Set(entry.reflections.map(\.id)).count == entry.reflections.count else {
                throw LibraryStoreError.invalidData("повторяющиеся идентификаторы материалов")
            }
            for episode in entry.episodes {
                guard validIdentifier(episode.id, maximum: 256), episode.season >= 0, episode.season <= 10_000,
                      episode.number >= 0, episode.number <= 100_000, episode.name.count <= 1_000,
                      episode.summary.count <= 50_000, validURL(episode.sourceURL) else {
                    throw LibraryStoreError.invalidData("некорректная серия")
                }
            }
            for fact in entry.facts {
                guard validIdentifier(fact.id, maximum: 512), fact.text.count <= 100_000,
                      fact.episodeID.map({ validIdentifier($0, maximum: 256) }) ?? true,
                      fact.titleID == nil || fact.titleID == entry.id,
                      validIdentifier(fact.kind, maximum: 64), validURL(fact.sourceURL) else {
                    throw LibraryStoreError.invalidData("некорректный источник сюжета")
                }
            }
            for turn in entry.chat {
                guard turn.text.count <= 30_000, turn.createdAt.timeIntervalSince1970.isFinite else {
                    throw LibraryStoreError.invalidData("слишком длинное сообщение")
                }
                if let citations = turn.citations {
                    guard citations.count <= 24, Set(citations.map(\.id)).count == citations.count,
                          Set(citations.map(\.number)).count == citations.count,
                          citations.allSatisfy({ validIdentifier($0.id, maximum: 512) && (1...24).contains($0.number)
                              && !$0.quote.isEmpty && $0.quote.count <= 1_200 && validURL($0.sourceURL) }) else {
                        throw LibraryStoreError.invalidData("некорректные ссылки ответа")
                    }
                }
            }
            for reflection in entry.reflections {
                let choices = reflection.likedChoices + reflection.dislikedChoices
                guard reflection.likedChoices.count <= 30, reflection.dislikedChoices.count <= 30,
                      Set(reflection.likedChoices.map(\.id)).count == reflection.likedChoices.count,
                      Set(reflection.dislikedChoices.map(\.id)).count == reflection.dislikedChoices.count,
                      choices.allSatisfy({ choice in
                          validIdentifier(choice.id, maximum: 1_024) && validIdentifier(choice.sourceID, maximum: 512)
                              && !choice.sourceQuote.isEmpty && choice.sourceQuote.count <= 220
                              && !choice.text.isEmpty && choice.text.count <= 1_000 && validURL(choice.sourceURL)
                              && (choice.episodeID.map { validIdentifier($0, maximum: 256) } ?? true)
                              && (reflection.episodeID == nil || choice.episodeID == reflection.episodeID)
                      }) else { throw LibraryStoreError.invalidData("некорректные варианты впечатлений") }
                guard reflection.titleID == entry.id, reflection.summary.count <= 30_000,
                      reflection.liked.count <= 100, reflection.disliked.count <= 100, reflection.questions.count <= 100,
                      reflection.liked.allSatisfy({ $0.count <= 5_000 }), reflection.questions.allSatisfy({ $0.count <= 5_000 }),
                      reflection.disliked.allSatisfy({ $0.count <= 5_000 }),
                      reflection.rating.map({ (1...10).contains($0) }) ?? true,
                      reflection.episodeID.map({ validIdentifier($0, maximum: 256) }) ?? true,
                      reflection.episodeSeason.map({ (0...10_000).contains($0) }) ?? true,
                      reflection.episodeNumber.map({ (0...100_000).contains($0) }) ?? true,
                      reflection.seasonNumber.map({ title.kind == .series && (0...10_000).contains($0) && reflection.episodeID == nil }) ?? true,
                      (reflection.episodeID == nil) == (reflection.episodeSeason == nil && reflection.episodeNumber == nil),
                      reflection.episodeID == nil || (title.kind == .series && reflection.episodeSeason != nil && reflection.episodeNumber != nil),
                      reflection.createdAt.timeIntervalSince1970.isFinite else {
                    throw LibraryStoreError.invalidData("некорректная запись впечатлений")
                }
            }
        }
    }

    private static func validIdentifier(_ value: String, maximum: Int) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.count <= maximum
            && value.rangeOfCharacter(from: .controlCharacters) == nil
    }

    private static func validURL(_ url: URL?) -> Bool {
        guard let url else { return true }
        return ["https", "http"].contains(url.scheme?.lowercased() ?? "")
            && !(url.host ?? "").isEmpty && url.user == nil && url.password == nil && url.absoluteString.count <= 2_048
    }
}
