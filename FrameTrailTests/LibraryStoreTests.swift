import Foundation
import FrameTrailCore
import XCTest
@testable import FrameTrail

@MainActor
final class LibraryStoreTests: XCTestCase {
    func testAccountsAreIsolatedAndGuestReturns() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LibraryStore(directory: directory)
        store.add(title("guest-film"))

        store.switchAccount("tmdb:42")
        XCTAssertTrue(store.entries.isEmpty)
        store.add(title("account-film"))
        store.switchAccount("guest")
        XCTAssertEqual(store.entries.map(\.id), ["guest-film"])
        store.switchAccount("tmdb:42")
        XCTAssertEqual(store.entries.map(\.id), ["account-film"])

        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(files.count, 2)
        XCTAssertFalse(files.contains { $0.contains("tmdb") || $0.contains("guest") })
    }

    func testExportRoundTripMergesIntoExistingLibrary() async throws {
        let firstDirectory = temporaryDirectory()
        let secondDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: firstDirectory)
            try? FileManager.default.removeItem(at: secondDirectory)
        }
        let source = LibraryStore(directory: firstDirectory)
        source.add(title("exported"))
        var entry = try XCTUnwrap(source.entry(for: "exported"))
        entry.progress = WatchProgress(finished: true)
        entry.chat = [ChatTurn(role: .user, text: "Why did she leave?")]
        entry.reflections = [Reflection(titleID: "exported", summary: "An open ending.", liked: ["The score"], rating: 8)]
        source.update(entry)
        let exported = try source.exportData()

        let destination = LibraryStore(directory: secondDirectory)
        destination.add(title("existing"))
        try destination.importData(exported)

        XCTAssertEqual(Set(destination.entries.map(\.id)), ["existing", "exported"])
        XCTAssertEqual(destination.entry(for: "exported"), source.entry(for: "exported"))
        XCTAssertEqual(LibraryStore(directory: secondDirectory).entries, destination.entries)
        XCTAssertGreaterThan(destination.bytesOnDisk, 0)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: exported) as? [String: Any])
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        XCTAssertNil(object["token"])
        XCTAssertNil(object["accountID"])
    }

    func testCorruptImportLeavesMemoryAndDiskUntouched() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LibraryStore(directory: directory)
        store.add(title("safe"))
        let before = try store.exportData()

        XCTAssertThrowsError(try store.importData(Data("not json".utf8)))

        XCTAssertEqual(try store.exportData(), before)
        XCTAssertEqual(try LibraryStore(directory: directory).exportData(), before)
        XCTAssertNotNil(store.lastError)
    }

    func testUnsupportedSchemaAndUnsafeSourceAreRejected() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LibraryStore(directory: directory)
        store.add(title("safe"))
        let before = try store.exportData()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: before) as? [String: Any])
        object["schemaVersion"] = 99
        XCTAssertThrowsError(try store.importData(JSONSerialization.data(withJSONObject: object)))

        object["schemaVersion"] = 1
        var entries = try XCTUnwrap(object["entries"] as? [[String: Any]])
        var unsafeTitle = try XCTUnwrap(entries[0]["title"] as? [String: Any])
        unsafeTitle["sourceURL"] = "file:///private/secret"
        entries[0]["title"] = unsafeTitle
        object["entries"] = entries
        XCTAssertThrowsError(try store.importData(JSONSerialization.data(withJSONObject: object)))
        XCTAssertEqual(try store.exportData(), before)
    }

    func testImportedUnknownChatRoleIsRejected() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LibraryStore(directory: directory)
        store.add(title("film"))
        var entry = try XCTUnwrap(store.entry(for: "film"))
        entry.chat = [ChatTurn(role: .user, text: "Hi")]
        store.update(entry)
        let before = try store.exportData()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: before) as? [String: Any])
        var entries = try XCTUnwrap(object["entries"] as? [[String: Any]])
        var chat = try XCTUnwrap(entries[0]["chat"] as? [[String: Any]])
        chat[0]["role"] = "system"
        entries[0]["chat"] = chat
        object["entries"] = entries

        XCTAssertThrowsError(try store.importData(JSONSerialization.data(withJSONObject: object)))
        XCTAssertEqual(try store.exportData(), before)
    }

    func testFactScopeIsNormalizedAndForeignFactsAreRejected() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LibraryStore(directory: directory)
        var entry = LibraryEntry(title: title("film"))
        entry.facts = [StoryFact(id: "f", text: "An event.")]
        store.update(entry)
        XCTAssertEqual(store.entry(for: "film")?.facts.first?.titleID, "film")
        let before = try store.exportData()

        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: before) as? [String: Any])
        var entries = try XCTUnwrap(object["entries"] as? [[String: Any]])
        var facts = try XCTUnwrap(entries[0]["facts"] as? [[String: Any]])
        facts[0]["titleID"] = "another-film"
        entries[0]["facts"] = facts
        object["entries"] = entries

        XCTAssertThrowsError(try store.importData(JSONSerialization.data(withJSONObject: object)))
        XCTAssertEqual(try store.exportData(), before)
    }

    func testOversizedImportIsRejected() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LibraryStore(directory: directory)

        XCTAssertThrowsError(try store.importData(Data(count: 10 * 1024 * 1024 + 1)))
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(store.bytesOnDisk, 0)
    }

    func testClearingMaterialsPreservesProgressAndThoughts() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LibraryStore(directory: directory)
        var entry = LibraryEntry(title: title("series", kind: .series))
        entry.episodes = [Episode(id: "ep1", season: 1, number: 1, name: "Pilot", summary: "A meeting.")]
        entry.facts = [StoryFact(id: "fact", text: "They meet.", episodeID: "ep1")]
        entry.progress = WatchProgress(watchedEpisodeIDs: ["ep1"])
        entry.chat = [ChatTurn(role: .assistant, text: "A new friendship begins.")]
        entry.reflections = [Reflection(titleID: "series", summary: "Promising.")]
        store.update(entry)

        store.clearDownloadedMaterials()

        let cleared = try XCTUnwrap(LibraryStore(directory: directory).entry(for: "series"))
        XCTAssertTrue(cleared.episodes.isEmpty)
        XCTAssertTrue(cleared.facts.isEmpty)
        XCTAssertEqual(cleared.progress, entry.progress)
        XCTAssertEqual(cleared.chat, entry.chat)
        XCTAssertEqual(cleared.reflections, entry.reflections)
        XCTAssertEqual(cleared.title, entry.title)
    }

    func testFailedPersistDoesNotChangeMemory() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LibraryStore(directory: directory)
        store.add(title("first"))
        let before = store.entries
        try FileManager.default.removeItem(at: directory)
        try Data("a file blocks the directory".utf8).write(to: directory)

        store.add(title("second"))
        XCTAssertEqual(store.entries, before)
        XCTAssertNotNil(store.lastError)
        store.remove("first")
        XCTAssertEqual(store.entries, before)
    }

    func testUnreadableLibraryIsPreserved() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let initial = LibraryStore(directory: directory)
        initial.add(title("first"))
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        let corrupted = Data("corrupted library".utf8)
        try corrupted.write(to: file)

        let recovered = LibraryStore(directory: directory)
        XCTAssertNotNil(recovered.lastError)
        recovered.add(title("second"))

        XCTAssertTrue(recovered.entries.isEmpty)
        XCTAssertEqual(try Data(contentsOf: file), corrupted)
        XCTAssertNotNil(recovered.lastError)
    }

    func testCorruptDestinationNeverShowsPreviousAccountsLibrary() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LibraryStore(directory: directory)
        store.switchAccount("tmdb:42")
        store.add(title("private-film"))
        let accountFile = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        store.switchAccount("guest")
        store.add(title("guest-film"))
        let corrupted = Data("invalid account library".utf8)
        try corrupted.write(to: accountFile)

        store.switchAccount("tmdb:42")

        XCTAssertEqual(store.activeAccountID, "tmdb:42")
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertNotNil(store.lastError)
        store.add(title("new-film"))
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(try Data(contentsOf: accountFile), corrupted)
        XCTAssertThrowsError(try store.exportData())
        store.switchAccount("guest")
        XCTAssertEqual(store.entries.map(\.id), ["guest-film"])
    }

    func testClearChatDoesNotRemoveReflection() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LibraryStore(directory: directory)
        var entry = LibraryEntry(title: title("film"))
        entry.chat = [ChatTurn(role: .user, text: "A thought.")]
        entry.reflections = [Reflection(titleID: "film", summary: "Keep this.")]
        store.update(entry)

        store.clearChat(for: "film")

        XCTAssertEqual(store.entry(for: "film")?.chat, [])
        XCTAssertEqual(store.entry(for: "film")?.reflections, entry.reflections)
    }

    func testProgressRewindClearsBroaderChatAtPersistenceBoundary() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LibraryStore(directory: directory)
        var entry = LibraryEntry(title: title("series", kind: .series))
        entry.progress = WatchProgress(watchedEpisodeIDs: ["ep1", "ep2"])
        entry.chat = [ChatTurn(role: .assistant, text: "The second episode reveals the killer.")]
        store.update(entry)

        entry.progress.watchedEpisodeIDs.remove("ep2")
        store.update(entry)

        XCTAssertTrue(try XCTUnwrap(store.entry(for: "series")).chat.isEmpty)
        XCTAssertTrue(try XCTUnwrap(LibraryStore(directory: directory).entry(for: "series")).chat.isEmpty)
    }

    func testImportedRewindClearsChatAndExpansionPreservesIt() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LibraryStore(directory: directory)
        var entry = LibraryEntry(title: title("film"))
        entry.progress.finished = true
        entry.chat = [ChatTurn(role: .assistant, text: "A full ending discussion.")]
        store.update(entry)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: store.exportData()) as? [String: Any])
        var entries = try XCTUnwrap(object["entries"] as? [[String: Any]])
        var progress = try XCTUnwrap(entries[0]["progress"] as? [String: Any])
        progress["finished"] = false
        entries[0]["progress"] = progress
        entries[0]["updatedAt"] = Date().addingTimeInterval(60).timeIntervalSinceReferenceDate
        object["entries"] = entries

        try store.importData(JSONSerialization.data(withJSONObject: object))

        XCTAssertFalse(try XCTUnwrap(store.entry(for: "film")).progress.finished)
        XCTAssertTrue(try XCTUnwrap(store.entry(for: "film")).chat.isEmpty)
        var expanded = try XCTUnwrap(store.entry(for: "film"))
        expanded.progress.finished = true
        expanded.chat = [ChatTurn(role: .user, text: "My new question.")]
        store.update(expanded)
        XCTAssertEqual(store.entry(for: "film")?.chat, expanded.chat)
    }

    func testInvalidRatingDoesNotChangeLibrary() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LibraryStore(directory: directory)
        store.add(title("film"))
        let before = try store.exportData()
        var entry = try XCTUnwrap(store.entry(for: "film"))
        entry.reflections = [Reflection(titleID: "film", summary: "A review.", rating: 0)]

        store.update(entry)

        XCTAssertNotNil(store.lastError)
        XCTAssertEqual(try store.exportData(), before)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("FrameTrailTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func title(_ id: String, kind: MediaKind = .movie) -> MediaTitle {
        MediaTitle(id: id, title: "Test \(id)", kind: kind, provider: "test", providerID: id)
    }
}
