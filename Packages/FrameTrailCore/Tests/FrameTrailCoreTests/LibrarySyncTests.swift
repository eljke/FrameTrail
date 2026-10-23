import XCTest
@testable import FrameTrailCore

final class LibrarySyncTests: XCTestCase {
    func testFirstLocalItemCreatesWithoutDeletingUnknownRemoteItems() {
        let local = item("local")
        let remote = record(item("remote"), revision: 4)

        let plan = LibrarySyncPlanner.plan(local: [local], remote: [remote], baseline: LibrarySyncBaseline())

        XCTAssertEqual(plan.uploads, [CloudLibraryUpload(mediaID: "local", payload: local, expectedRevision: 0)])
        XCTAssertEqual(plan.applies, [remote])
        XCTAssertEqual(plan.nextBaseline.records["remote"], remote)
        XCTAssertNil(plan.nextBaseline.records["local"])
        XCTAssertTrue(plan.conflicts.isEmpty)
    }

    func testOfflineLocalEditUsesCurrentRemoteRevision() {
        let original = item("film")
        var changed = original
        changed.progress.finished = true
        let remote = record(original, revision: 8)
        let baseline = LibrarySyncBaseline(records: ["film": record(original, revision: 7)])

        let plan = LibrarySyncPlanner.plan(local: [changed], remote: [remote], baseline: baseline)

        XCTAssertEqual(plan.uploads, [CloudLibraryUpload(mediaID: "film", payload: changed, expectedRevision: 8)])
        XCTAssertTrue(plan.applies.isEmpty)
        XCTAssertTrue(plan.conflicts.isEmpty)
        XCTAssertEqual(plan.nextBaseline, baseline)
    }

    func testRemoteOnlyEditIsApplied() {
        let original = item("film")
        var changed = original
        changed.reflections = [Reflection(titleID: "film", summary: "A remote thought.", rating: 9)]
        let remote = record(changed, revision: 2)

        let plan = LibrarySyncPlanner.plan(
            local: [original], remote: [remote], baseline: LibrarySyncBaseline(records: ["film": record(original, revision: 1)])
        )

        XCTAssertEqual(plan.applies, [remote])
        XCTAssertEqual(plan.nextBaseline.records["film"], remote)
        XCTAssertTrue(plan.uploads.isEmpty)
    }

    func testBothChangedRequiresExplicitResolution() {
        let original = item("film")
        var local = original
        local.progress.finished = true
        var remoteItem = original
        remoteItem.reflections = [Reflection(titleID: "film", summary: "Changed elsewhere.")]
        let baseline = LibrarySyncBaseline(records: ["film": record(original, revision: 1)])

        let plan = LibrarySyncPlanner.plan(local: [local], remote: [record(remoteItem, revision: 2)], baseline: baseline)

        XCTAssertEqual(plan.conflicts.map(\.reason), [.concurrentChanges])
        XCTAssertEqual(plan.nextBaseline, baseline)
        XCTAssertTrue(plan.uploads.isEmpty)
        XCTAssertTrue(plan.applies.isEmpty)
    }

    func testDifferentFirstSyncItemsConflict() {
        let original = item("film")
        var remote = original
        remote.progress.finished = true

        let plan = LibrarySyncPlanner.plan(local: [original], remote: [record(remote, revision: 3)], baseline: LibrarySyncBaseline())

        XCTAssertEqual(plan.conflicts.map(\.reason), [.initialDivergence])
        XCTAssertTrue(plan.nextBaseline.records.isEmpty)
        XCTAssertTrue(plan.uploads.isEmpty)
        XCTAssertTrue(plan.applies.isEmpty)
    }

    func testLocalDeletionUploadsTombstoneOnlyAfterBaseline() {
        let original = item("film")
        let remote = record(original, revision: 5)

        let plan = LibrarySyncPlanner.plan(
            local: [], remote: [remote], baseline: LibrarySyncBaseline(records: ["film": remote])
        )

        XCTAssertEqual(plan.uploads, [CloudLibraryUpload(mediaID: "film", payload: nil, expectedRevision: 5)])
        XCTAssertTrue(plan.applies.isEmpty)
        XCTAssertFalse(plan.uploads.contains { !$0.deleted })
    }

    func testRemoteDeletionAppliesAndRetainsTombstone() {
        let original = item("film")
        let tombstone = CloudLibraryRecord(mediaID: "film", payload: nil, revision: 6, deleted: true)
        let plan = LibrarySyncPlanner.plan(
            local: [original], remote: [tombstone], baseline: LibrarySyncBaseline(records: ["film": record(original, revision: 5)])
        )

        XCTAssertEqual(plan.applies, [tombstone])
        XCTAssertEqual(plan.nextBaseline.records["film"], tombstone)
        let converged = LibrarySyncPlanner.plan(local: [], remote: [tombstone], baseline: plan.nextBaseline)
        XCTAssertTrue(converged.uploads.isEmpty)
        XCTAssertTrue(converged.applies.isEmpty)
        XCTAssertEqual(converged.nextBaseline.records["film"], tombstone)
    }

    func testMissingRemoteIsNotTreatedAsDeletionOrResurrection() {
        let original = item("film")
        let baseline = LibrarySyncBaseline(records: ["film": record(original, revision: 5)])

        let plan = LibrarySyncPlanner.plan(local: [original], remote: [], baseline: baseline)

        XCTAssertEqual(plan.conflicts.map(\.reason), [.remoteMissing])
        XCTAssertEqual(plan.nextBaseline, baseline)
        XCTAssertTrue(plan.applies.isEmpty)
        XCTAssertTrue(plan.uploads.isEmpty)
    }

    func testEqualConcurrentEditsConvergeWithoutConflict() {
        let original = item("film")
        var changed = original
        changed.progress.finished = true
        let remote = record(changed, revision: 2)

        let plan = LibrarySyncPlanner.plan(
            local: [changed], remote: [remote], baseline: LibrarySyncBaseline(records: ["film": record(original, revision: 1)])
        )

        XCTAssertEqual(plan.nextBaseline.records["film"], remote)
        XCTAssertTrue(plan.conflicts.isEmpty)
        XCTAssertTrue(plan.applies.isEmpty)
        XCTAssertTrue(plan.uploads.isEmpty)
    }

    func testInvalidOrRegressedRemoteRecordsNeverMutatePlan() {
        let original = item("film")
        let baseline = LibrarySyncBaseline(records: ["film": record(original, revision: 5)])
        let invalid = CloudLibraryRecord(mediaID: "film", payload: item("foreign"), revision: 6, deleted: false)
        for remote in [invalid, record(original, revision: 4)] {
            let plan = LibrarySyncPlanner.plan(local: [original], remote: [remote], baseline: baseline)
            XCTAssertEqual(plan.conflicts.map(\.reason), [.invalidRecord])
            XCTAssertTrue(plan.uploads.isEmpty)
            XCTAssertTrue(plan.applies.isEmpty)
            XCTAssertEqual(plan.nextBaseline, baseline)
        }
    }

    private func item(_ id: String) -> CloudLibraryItem {
        CloudLibraryItem(
            title: MediaTitle(id: id, title: id, kind: .movie, provider: "test", providerID: id),
            progress: WatchProgress(), reflections: []
        )
    }

    private func record(_ item: CloudLibraryItem, revision: Int64) -> CloudLibraryRecord {
        CloudLibraryRecord(mediaID: item.id, payload: item, revision: revision, deleted: false)
    }
}
