import Foundation
import XCTest
@testable import CompanionCore

final class LiveWireTests: XCTestCase {
    private let binding = LiveBinding(accountID: "account", controllerID: "controller", environmentID: "host", sessionID: "connection")
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    func testLiveEnvelopeRoundTripDoesNotDecodeAsDemo() throws {
        let command = LiveCommand(issuedAt: now, binding: binding, kind: .sendText, threadID: "real-thread", text: "hello")
        let data = try LiveWire.encode(command)
        let decoded = try LiveWire.decode(LiveCommand.self, from: data)
        XCTAssertEqual(decoded.id, command.id)
        XCTAssertEqual(decoded.binding, binding)
        XCTAssertThrowsError(try Wire.decode(Command.self, from: data))
        XCTAssertThrowsError(try LiveWire.decode(LiveCommand.self, from: Wire.encode(Command(kind: .refresh))))
    }
    func testExpiryAndFutureClockBounds() throws {
        for age in [-5.0, 0, 30] {
            XCTAssertNoThrow(try LiveCommand(issuedAt: now.addingTimeInterval(-age), binding: binding, kind: .refresh).validate(now: now))
        }
        for age in [-5.01, 30.01] {
            XCTAssertThrowsError(try LiveCommand(issuedAt: now.addingTimeInterval(-age), binding: binding, kind: .refresh).validate(now: now))
        }
    }
    func testExtraneousFieldsAndMissingTargetsFail() {
        let values = [
            LiveCommand(issuedAt: now, binding: binding, kind: .refresh, threadID: "thread"),
            LiveCommand(issuedAt: now, binding: binding, kind: .read, threadID: "thread", text: "text"),
            LiveCommand(issuedAt: now, binding: binding, kind: .sendText, threadID: "thread", text: "text", turnID: "turn"),
            LiveCommand(issuedAt: now, binding: binding, kind: .interrupt, threadID: "thread", text: "text", turnID: "turn"),
            LiveCommand(issuedAt: now, binding: binding, kind: .read),
            LiveCommand(issuedAt: now, binding: binding, kind: .interrupt, threadID: "thread")
        ]
        for command in values { XCTAssertThrowsError(try command.validate(now: now)) }
    }
    func testInputAndBindingLimits() {
        for text in ["", " \n\t", String(repeating: "x", count: 2001)] {
            XCTAssertThrowsError(try LiveCommand(issuedAt: now, binding: binding, kind: .sendText, threadID: "thread", text: text).validate(now: now))
        }
        for id in ["", "line\nbreak", String(repeating: "x", count: 513)] {
            XCTAssertThrowsError(try LiveBinding(accountID: id, controllerID: "controller", environmentID: "host", sessionID: "connection").validate())
            XCTAssertThrowsError(try LiveCommand(issuedAt: now, binding: binding, kind: .read, threadID: id).validate(now: now))
        }
    }
    func testWrongEnvelopeVersionAndModeRejected() throws {
        let data = try LiveWire.encode(LiveCommand(issuedAt: now, binding: binding, kind: .refresh))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["version"] = 2
        XCTAssertThrowsError(try LiveWire.decode(LiveCommand.self, from: JSONSerialization.data(withJSONObject: object)))
        object["version"] = 1; object["mode"] = "demo"
        XCTAssertThrowsError(try LiveWire.decode(LiveCommand.self, from: JSONSerialization.data(withJSONObject: object)))
        XCTAssertThrowsError(try LiveWire.decode(LiveCommand.self, from: Data(repeating: 32, count: 60_001)))
    }
    func testSnapshotRequiresBindingAndUniqueBoundedThreads() throws {
        let thread = RemoteThread(id: "real-thread", title: "Task", project: "Project", state: .ready, summary: "Result", currentTurnID: nil, updatedAt: Date())
        XCTAssertThrowsError(try LiveSnapshot(binding: nil, hostName: "Host", threads: [], connected: true).validate())
        XCTAssertThrowsError(try LiveSnapshot(binding: binding, hostName: "Host", threads: [thread, thread], connected: true).validate())
        let rows = (0..<21).map { i in RemoteThread(id: "thread-\(i)", title: "Task", project: "Project", state: .ready, summary: "Result", currentTurnID: nil, updatedAt: Date()) }
        XCTAssertThrowsError(try LiveSnapshot(binding: binding, hostName: "Host", threads: rows, connected: true).validate())
        XCTAssertNoThrow(try LiveSnapshot(binding: binding, hostName: "Host", threads: [thread], connected: true).validate())
    }
    func testDisconnectedAndStaleSnapshotsAreNotMutationAuthority() {
        XCTAssertFalse(LiveSnapshot(binding: binding, hostName: "Host", threads: [], connected: false).fresh)
        XCTAssertFalse(LiveSnapshot(binding: binding, generatedAt: Date().addingTimeInterval(-121), hostName: "Host", threads: [], connected: true).fresh)
        XCTAssertTrue(LiveSnapshot(binding: binding, hostName: "Host", threads: [], connected: true).fresh)
    }
}
