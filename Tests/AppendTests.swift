import XCTest
@testable import MusicSyncCore

private actor Counter {
    var value = 0
    func increment() { value += 1 }
}

@MainActor
final class AppendTests: XCTestCase {
    func testUncertainWriteBlocksReplayUntilReadConfirmsIt() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SyncDiskStore(directory: dir)
        let appender = PlaylistAppender(store: store)
        let calls = Counter()
        do {
            try await appender.append(playlistID: "p", ids: ["a"], existingIDs: { [] }, write: { _ in
                await calls.increment()
                throw URLError(.networkConnectionLost)
            })
            XCTFail("Expected connection error")
        } catch {}
        do {
            try await appender.append(playlistID: "p", ids: ["a"], existingIDs: { [] }, write: { _ in await calls.increment() })
            XCTFail("Expected uncertain write")
        } catch { XCTAssertTrue(error is SyncIntegrityError) }
        let afterFailure = await calls.value
        XCTAssertEqual(afterFailure, 1)
        try await appender.append(playlistID: "p", ids: ["a", "b"], existingIDs: { ["a"] }, write: { ids in
            await calls.increment(); XCTAssertEqual(ids, ["b"])
        })
        let afterRetry = await calls.value
        XCTAssertEqual(afterRetry, 2)
        XCTAssertEqual(try store.read().pendingAppends["p"], ["b"])
    }
    func testCancellationAfterFirstBatchDoesNotSendSecond() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let appender = PlaylistAppender(store: SyncDiskStore(directory: dir))
        let task = Task {
            try await appender.append(playlistID: "p", ids: (0..<70).map(String.init), existingIDs: { [] }, write: { ids in
                XCTAssertEqual(ids.count, 50)
                withUnsafeCurrentTask { $0?.cancel() }
            })
        }
        do { try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(try appender.store.read().pendingAppends["p"]?.count, 50)
    }
    func testDefinitiveRejectionCanRetryWithoutLosingEarlierBatch() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SyncDiskStore(directory: dir)
        let appender = PlaylistAppender(store: store)
        let ids = (0..<70).map(String.init)
        do {
            try await appender.append(playlistID: "p", ids: ids, existingIDs: { [] }, write: { batch in
                if batch.first == "50" { throw URLError(.userAuthenticationRequired) }
            }, wasRejected: { _ in true })
            XCTFail("Expected rejection")
        } catch {}
        XCTAssertEqual(try store.read().pendingAppends["p"], Array(ids.prefix(50)))
        try await appender.append(playlistID: "p", ids: ids, existingIDs: { Set(ids.prefix(50)) }, write: { batch in
            XCTAssertEqual(batch, Array(ids.suffix(20)))
        })
        XCTAssertEqual(try store.read().pendingAppends["p"], Array(ids.suffix(20)))
    }
    func testRejectedFirstBatchClearsJournal() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let appender = PlaylistAppender(store: SyncDiskStore(directory: dir))
        do {
            try await appender.append(playlistID: "p", ids: ["a"], existingIDs: { [] }, write: { _ in
                throw URLError(.userAuthenticationRequired)
            }, wasRejected: { _ in true })
            XCTFail("Expected rejection")
        } catch {}
        XCTAssertNil(try appender.store.read().pendingAppends["p"])
        try await appender.append(playlistID: "p", ids: ["a"], existingIDs: { [] }, write: { XCTAssertEqual($0, ["a"]) })
    }
    func testRepeatedPaginationCursorFailsClosed() throws {
        var cursor = PageCursor()
        try cursor.visit("/v1/test?offset=0")
        try cursor.visit("/v1/test?offset=100")
        XCTAssertThrowsError(try cursor.visit("/v1/test?offset=0"))
    }
}
