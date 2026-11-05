import XCTest
@testable import CompanionCore

final class CoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_794_000_000)
    private let threadID = "demo-existing-thread-02"
    private func command(_ kind: CommandKind = .sendText, id: UUID = UUID(), text: String? = "继续检查") -> Command {
        Command(id: id, createdAt: now, kind: kind, threadID: threadID, text: text)
    }
    func testWireRoundTrip() throws {
        let value = command(text: "你好 👋")
        XCTAssertEqual(try Wire.decode(Command.self, from: Wire.encode(value)), value)
        let snapshot = Snapshot.sample(now: now)
        XCTAssertEqual(try Wire.decode(Snapshot.self, from: Wire.encode(snapshot)), snapshot)
    }
    func testWireRejectsOversizeBothDirections() {
        XCTAssertThrowsError(try Wire.encode(String(repeating: "x", count: Wire.maximumBytes)))
        XCTAssertThrowsError(try Wire.decode(Command.self, from: Data(repeating: 0, count: Wire.maximumBytes + 1)))
    }
    func testSampleNeverClaimsRemoteConnection() throws {
        let snapshot = Snapshot.sample(now: now)
        try snapshot.validate(now: now)
        XCTAssertFalse(snapshot.remoteConnected)
        XCTAssertEqual(snapshot.source, "demo")
        XCTAssertEqual(snapshot.threads.count, 3)
    }
    func testRejectsRemoteOrUnknownSnapshot() {
        var snapshot = Snapshot.sample(now: now)
        snapshot.remoteConnected = true
        XCTAssertThrowsError(try snapshot.validate(now: now))
        snapshot.remoteConnected = false; snapshot.source = "remote"
        XCTAssertThrowsError(try snapshot.validate(now: now))
    }
    func testRejectsDuplicateSnapshotIDsAndMissingTurn() {
        var snapshot = Snapshot.sample(now: now)
        snapshot.threads.append(snapshot.threads[0])
        XCTAssertThrowsError(try snapshot.validate(now: now))
        snapshot = .sample(now: now); snapshot.threads[0].currentTurnID = nil
        XCTAssertThrowsError(try snapshot.validate(now: now))
    }
    func testRejectsFutureSnapshot() {
        XCTAssertThrowsError(try Snapshot.sample(now: now.addingTimeInterval(31)).validate(now: now))
    }
    func testRejectsExpiredAndFutureCommands() {
        for offset in [-30.0, -100, 6] {
            let request = Command(createdAt: now.addingTimeInterval(offset), kind: .refresh)
            XCTAssertThrowsError(try request.validate(now: now))
        }
        XCTAssertNoThrow(try Command(createdAt: now.addingTimeInterval(-29), kind: .refresh).validate(now: now))
    }
    func testRejectsWrongModeAndVersion() {
        var request = command(); request.mode = "live"
        XCTAssertThrowsError(try request.validate(now: now))
        request.mode = "demo"; request.version = 99
        XCTAssertThrowsError(try request.validate(now: now))
    }
    func testInputBounds() throws {
        for text in ["", "  \n ", String(repeating: "字", count: 2001)] {
            XCTAssertThrowsError(try command(text: text).validate(now: now))
        }
        var engine = DemoEngine(now: now)
        let reply = engine.handle(command(text: String(repeating: "字", count: 2000)), now: now)
        XCTAssertEqual(reply.state, .demoApplied)
        try reply.snapshot.validate(now: now)
    }
    func testRefreshRejectsExtraneousFields() {
        XCTAssertThrowsError(try command(.refresh).validate(now: now))
    }
    func testExistingThreadIsReusedWithoutCreation() {
        var engine = DemoEngine(now: now)
        let ids = engine.snapshot.threads.map(\.id)
        let reply = engine.handle(command(), now: now)
        XCTAssertEqual(reply.state, .demoApplied)
        XCTAssertEqual(engine.snapshot.threads.map(\.id), ids)
        XCTAssertEqual(engine.snapshot.threads[1].state, .running)
    }
    func testUnknownThreadCannotCreateReplacement() {
        var engine = DemoEngine(now: now)
        let request = Command(createdAt: now, kind: .sendText, threadID: "demo-unknown", text: "hello")
        XCTAssertEqual(engine.handle(request, now: now).state, .rejected)
        XCTAssertEqual(engine.snapshot.threads.count, 3)
    }
    func testDuplicateIDDoesNotApplyTwice() {
        var engine = DemoEngine(now: now)
        let request = command()
        let first = engine.handle(request, now: now)
        XCTAssertEqual(engine.handle(request, now: now.addingTimeInterval(2)), first)
        XCTAssertEqual(engine.snapshot.threads[1].currentTurnID, first.snapshot.threads[1].currentTurnID)
        XCTAssertEqual(engine.handle(command(id: request.id, text: "changed"), now: now).state, .rejected)
    }
    func testRunningThreadRejectsAnotherStart() {
        var engine = DemoEngine(now: now)
        _ = engine.handle(command(), now: now)
        XCTAssertEqual(engine.handle(command(), now: now).state, .rejected)
    }
    func testInterruptRequiresExactTurn() {
        var engine = DemoEngine(now: now)
        let thread = engine.snapshot.threads[0]
        let wrong = Command(createdAt: now, kind: .interrupt, threadID: thread.id, turnID: "demo-old-turn")
        XCTAssertEqual(engine.handle(wrong, now: now).state, .rejected)
        XCTAssertEqual(engine.snapshot.threads[0].state, .running)
        let right = Command(createdAt: now, kind: .interrupt, threadID: thread.id, turnID: thread.currentTurnID)
        XCTAssertEqual(engine.handle(right, now: now).state, .demoApplied)
        XCTAssertEqual(engine.snapshot.threads[0].state, .interrupted)
        XCTAssertNil(engine.snapshot.threads[0].currentTurnID)
    }
    func testMissingTurnIsRejected() {
        let request = Command(createdAt: now, kind: .interrupt, threadID: threadID)
        XCTAssertThrowsError(try request.validate(now: now))
    }
    func testRefreshOnlyUpdatesSnapshotTimestamp() {
        var engine = DemoEngine(now: now)
        let before = engine.snapshot.threads
        let reply = engine.handle(Command(createdAt: now, kind: .refresh), now: now.addingTimeInterval(1))
        XCTAssertEqual(reply.state, .demoApplied)
        XCTAssertEqual(engine.snapshot.threads, before)
        XCTAssertEqual(engine.snapshot.generatedAt, now.addingTimeInterval(1))
    }
    func testUnknownCommandTypeFailsDecoding() throws {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Wire.encode(command())) as? [String: Any])
        json["kind"] = "thread/start"
        XCTAssertThrowsError(try Wire.decode(Command.self, from: JSONSerialization.data(withJSONObject: json)))
    }
}
