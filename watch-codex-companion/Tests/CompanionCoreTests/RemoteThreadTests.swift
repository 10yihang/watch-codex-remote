import Foundation
import XCTest
@testable import CompanionCore

final class RemoteThreadTests: XCTestCase {
    private func row(status: String = "idle", turns: [[String: Any]] = []) -> [String: Any] {
        ["id": "thread-1", "name": "Real task", "preview": "First request", "cwd": "/project",
         "updatedAt": 1_800_000_000, "status": ["type": status], "turns": turns]
    }
    private func response(_ result: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["id": 1, "result": result])
    }
    private func turn(_ status: String, id: String = "turn-1") -> [String: Any] {
        ["id": id, "status": status, "items": [["type": "agentMessage", "text": "Actual result"]]]
    }
    func testEmptyAndPaginatedPages() throws {
        let empty = try RemoteThread.decodePage(response(["data": [], "nextCursor": NSNull()]))
        XCTAssertTrue(empty.threads.isEmpty)
        XCTAssertNil(empty.nextCursor)
        let page = try RemoteThread.decodePage(response(["data": [row()], "nextCursor": "opaque"]))
        XCTAssertEqual(page.nextCursor, "opaque")
        XCTAssertEqual(page.threads[0].id, "thread-1")
        XCTAssertEqual(page.threads[0].title, "Real task")
        XCTAssertEqual(page.threads[0].project, "/project")
        XCTAssertEqual(page.threads[0].updatedAt, Date(timeIntervalSince1970: 1_800_000_000))
    }
    func testRealRunningStateWithoutFabricatedTurnID() throws {
        let list = try RemoteThread.decodePage(response(["data": [row(status: "active")]]))
        XCTAssertEqual(list.threads[0].state, .running)
        XCTAssertNil(list.threads[0].currentTurnID)
        let detail = try RemoteThread.decodeRead(response(["thread": row(status: "active", turns: [turn("inProgress")])]), expectedThreadID: "thread-1")
        XCTAssertEqual(detail.currentTurnID, "turn-1")
        XCTAssertEqual(detail.summary, "Actual result")
    }
    func testErrorUnloadedUnknownAndFinishedStates() throws {
        for (status, expected) in [("notLoaded", RemoteThreadState.notLoaded), ("systemError", .failed), ("futureStatus", .unknown)] {
            let detail = try RemoteThread.decodeRead(response(["thread": row(status: status)]), expectedThreadID: "thread-1")
            XCTAssertEqual(detail.state, expected)
            XCTAssertNil(detail.currentTurnID)
        }
        for (status, expected) in [("completed", RemoteThreadState.ready), ("failed", .failed), ("interrupted", .interrupted)] {
            let detail = try RemoteThread.decodeRead(response(["thread": row(turns: [turn(status)])]), expectedThreadID: "thread-1")
            XCTAssertEqual(detail.state, expected)
            XCTAssertNil(detail.currentTurnID)
        }
        var failed = turn("failed")
        failed["error"] = ["message": "Host reported failure"]
        let detail = try RemoteThread.decodeRead(response(["thread": row(turns: [failed])]), expectedThreadID: "thread-1")
        XCTAssertEqual(detail.summary, "Host reported failure")
    }
    func testRejectStaleIDsConflictingTurnsDuplicatesAndMalformedJSON() throws {
        XCTAssertThrowsError(try RemoteThread.decodeRead(response(["thread": row()]), expectedThreadID: "old-thread")) {
            XCTAssertEqual($0 as? RemoteRelayError, .staleSelection)
        }
        XCTAssertThrowsError(try RemoteThread.decodeRead(response(["thread": row(turns: [turn("inProgress")])]), expectedThreadID: "thread-1"))
        XCTAssertThrowsError(try RemoteThread.decodeRead(response(["thread": row(status: "active", turns: [turn("inProgress"), turn("inProgress", id: "second")])]), expectedThreadID: "thread-1"))
        XCTAssertThrowsError(try RemoteThread.decodePage(response(["data": [row(), row()]])))
        for data in [Data("not json".utf8), Data("[]".utf8), try response([:]), try response(["data": "wrong"])] {
            XCTAssertThrowsError(try RemoteThread.decodePage(data))
        }
        var bad = row(); bad["updatedAt"] = true
        XCTAssertThrowsError(try RemoteThread.decodePage(response(["data": [bad]])))
        XCTAssertThrowsError(try RemoteThread.decodePage(Data(#"{"id":1,"error":{"code":-1}}"#.utf8))) {
            XCTAssertEqual($0 as? RemoteRelayError, .remoteFailure)
        }
    }
    func testStartedTurnUsesActualReturnedID() throws {
        XCTAssertEqual(try RemoteThread.decodeStartedTurn(response(["turn": turn("inProgress")])), "turn-1")
        XCTAssertThrowsError(try RemoteThread.decodeStartedTurn(response(["turn": [:]])))
    }
    func testNoMutationsBeforeConnection() async {
        let relay = RemoteRelay()
        do { _ = try await relay.resumeThread(id: "thread-1"); XCTFail() }
        catch { XCTAssertEqual(error as? RemoteRelayError, .notInitialized) }
        do { _ = try await relay.startTurn(threadID: "thread-1", text: "Hello"); XCTFail() }
        catch { XCTAssertEqual(error as? RemoteRelayError, .notInitialized) }
        do { _ = try await relay.interruptTurn(threadID: "thread-1", turnID: "turn-1"); XCTFail() }
        catch { XCTAssertEqual(error as? RemoteRelayError, .notInitialized) }
    }
}
