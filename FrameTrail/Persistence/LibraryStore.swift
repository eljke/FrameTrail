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
        }
    }
}

@MainActor @Observable
final class LibraryStore {
    private(set) var entries: [LibraryEntry] = []
    private(set) var lastError: String?
    private(set) var activeAccountID = "guest"

    private let directory: URL
    private var unreadableAccountIDs: Set<String> = []
    private static let maximumBytes = 10 * 1024 * 1024

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FrameTrail", isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
        do {
            entries = try load(accountID: activeAccountID)
        } catch {
            unreadableAccountIDs.insert(activeAccountID)
            lastError = error.localizedDescription
        }
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
        do {
            let loaded = try load(accountID: id)
            activeAccountID = id
            entries = loaded
            unreadableAccountIDs.remove(id)
            lastError = nil
        } catch {
            activeAccountID = id
            entries = []
            unreadableAccountIDs.insert(id)
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

    func clearChat(for titleID: String) {
        var next = entries
        guard let index = next.firstIndex(where: { $0.id == titleID }) else { return }
        next[index].chat = []
        next[index].updatedAt = Date()
        commit(next)
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

    private func persist(_ next: [LibraryEntry]) throws {
        guard !unreadableAccountIDs.contains(activeAccountID) else {
            throw LibraryStoreError.unreadableLibrary
        }
        let data = try Self.encode(next)
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

    private func load(accountID: String) throws -> [LibraryEntry] {
        let url = fileURL(accountID: accountID)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        if let size = attributes[.size] as? NSNumber, size.intValue > Self.maximumBytes {
            throw LibraryStoreError.tooLarge
        }
        return try Self.decode(Data(contentsOf: url))
    }

    private func fileURL(accountID: String) -> URL {
        let digest = SHA256.hash(data: Data(accountID.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("library-\(digest).json", isDirectory: false)
    }

    private struct Archive: Codable {
        var schemaVersion: Int
        var entries: [LibraryEntry]
    }

    private static func decode(_ data: Data) throws -> [LibraryEntry] {
        guard data.count <= maximumBytes else { throw LibraryStoreError.tooLarge }
        let archive = try JSONDecoder().decode(Archive.self, from: data)
        guard archive.schemaVersion == 1 else { throw LibraryStoreError.unsupportedSchema }
        let entries = scopedEntries(archive.entries)
        try validate(entries)
        return entries
    }

    private static func encode(_ entries: [LibraryEntry]) throws -> Data {
        try validate(entries)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Archive(schemaVersion: 1, entries: entries))
        guard data.count <= maximumBytes else { throw LibraryStoreError.tooLarge }
        return data
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
                  entry.reflections.count <= 200, entry.progress.watchedEpisodeIDs.count <= 5_000,
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
            }
            for reflection in entry.reflections {
                guard reflection.titleID == entry.id, reflection.summary.count <= 30_000,
                      reflection.liked.count <= 100, reflection.questions.count <= 100,
                      reflection.liked.allSatisfy({ $0.count <= 5_000 }), reflection.questions.allSatisfy({ $0.count <= 5_000 }),
                      reflection.rating.map({ (1...10).contains($0) }) ?? true,
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
