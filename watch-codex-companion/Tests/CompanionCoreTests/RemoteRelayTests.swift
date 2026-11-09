import Foundation
import XCTest
@testable import CompanionCore

final class RemoteRelayTests: XCTestCase {
    private func codec() throws -> RemoteRelayCodec {
        try RemoteRelayCodec(clientID: "client", environmentID: "host", streamID: "stream")
    }
    private func frame(sequence: Int = 1, stream: String = "stream", host: String = "host", type: String = "server_message", message: [String: Any] = ["id": 1, "result": [:]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["type": type, "client_id": "client", "env_id": host,
            "stream_id": stream, "seq_id": sequence, "message": message])
    }
    private func start(_ codec: inout RemoteRelayCodec, id: Int = 1) throws {
        _ = try codec.envelope(RemoteRelayCodec.request(id: id, method: "thread/list"))
    }

    func testV3EnvelopeAndReadOnlyRPCs() throws {
        var codec = try codec()
        let request = try RemoteRelayCodec.request(id: 1, method: "initialize")
        let frame = try RemoteRelayCodec.object(codec.envelope(request))
        XCTAssertEqual(frame["type"] as? String, "client_message")
        XCTAssertEqual(frame["stream_id"] as? String, "stream")
        XCTAssertEqual(frame["env_id"] as? String, "host")
        XCTAssertEqual(frame["client_id"] as? String, "client")
        XCTAssertEqual(frame["seq_id"] as? Int, 1)
        XCTAssertEqual(frame["skip_history"] as? Bool, false)
        let body = try XCTUnwrap(frame["message"] as? [String: Any])
        XCTAssertEqual(body["method"] as? String, "initialize")
        XCTAssertNil(body["jsonrpc"])
        for method in ["thread/start", "thread/fork"] {
            XCTAssertThrowsError(try RemoteRelayCodec.request(id: 2, method: method)) {
                XCTAssertEqual($0 as? RemoteRelayError, .unsupportedMethod)
            }
        }
        let read = try RemoteRelayCodec.object(RemoteRelayCodec.request(id: 2, method: "thread/read", threadID: "existing"))
        let params = try XCTUnwrap(read["params"] as? [String: Any])
        XCTAssertEqual(params["threadId"] as? String, "existing")
        XCTAssertEqual(params["includeTurns"] as? Bool, true)
    }

    func testExistingThreadMutationShapesNeverOverrideConfiguration() throws {
        let resume = try RemoteRelayCodec.object(RemoteRelayCodec.request(id: 1, method: "thread/resume", threadID: "existing"))
        let resumeParams = try XCTUnwrap(resume["params"] as? [String: Any])
        XCTAssertEqual(Set(resumeParams.keys), ["threadId"])
        let start = try RemoteRelayCodec.object(RemoteRelayCodec.request(id: 2, method: "turn/start", threadID: "existing", text: "Continue"))
        let startParams = try XCTUnwrap(start["params"] as? [String: Any])
        XCTAssertEqual(Set(startParams.keys), ["threadId", "input"])
        let input = try XCTUnwrap(startParams["input"] as? [[String: Any]])
        XCTAssertEqual(input.count, 1)
        XCTAssertEqual(input[0]["type"] as? String, "text")
        XCTAssertEqual(input[0]["text"] as? String, "Continue")
        XCTAssertEqual((input[0]["text_elements"] as? [String])?.count, 0)
        let stop = try RemoteRelayCodec.object(RemoteRelayCodec.request(id: 3, method: "turn/interrupt", threadID: "existing", turnID: "exact-turn"))
        let stopParams = try XCTUnwrap(stop["params"] as? [String: Any])
        XCTAssertEqual(Set(stopParams.keys), ["threadId", "turnId"])
        XCTAssertEqual(stopParams["turnId"] as? String, "exact-turn")
        for method in ["thread/resume", "turn/start", "turn/interrupt"] {
            XCTAssertThrowsError(try RemoteRelayCodec.request(id: 1, method: method))
            XCTAssertThrowsError(try RemoteRelayCodec.request(id: 1, method: method, threadID: " ", turnID: "turn", text: "hello"))
        }
        XCTAssertThrowsError(try RemoteRelayCodec.request(id: 1, method: "turn/start", threadID: "existing", text: " "))
        XCTAssertThrowsError(try RemoteRelayCodec.request(id: 1, method: "turn/start", threadID: "existing", text: String(repeating: "a", count: 2001)))
        XCTAssertThrowsError(try RemoteRelayCodec.request(id: 1, method: "turn/interrupt", threadID: "existing"))
    }

    func testAckAndForeignResponsesNeverCompleteRequest() throws {
        var codec = try codec(); try start(&codec)
        XCTAssertNil(try codec.receive(Data(#"{"type":"ack"}"#.utf8)))
        XCTAssertEqual(codec.pendingID, 1)
        XCTAssertNil(try codec.receive(frame(message: ["id": 99, "result": [:]])))
        XCTAssertEqual(codec.pendingID, 1)
        XCTAssertNotNil(try codec.receive(frame(sequence: 2)))
        XCTAssertNil(codec.pendingID)
    }

    func testStaleStreamsDuplicatesAndSequenceGaps() throws {
        var codec = try codec(); try start(&codec)
        XCTAssertNil(try codec.receive(frame(sequence: 90, stream: "previous")))
        XCTAssertNil(codec.lastServerSequence)
        XCTAssertNotNil(try codec.receive(frame(sequence: 7)))
        try start(&codec, id: 2)
        XCTAssertNil(try codec.receive(frame(sequence: 7)))
        XCTAssertEqual(codec.pendingID, 2)
        XCTAssertThrowsError(try codec.receive(frame(sequence: 9, message: ["id": 2, "result": [:]]))) {
            XCTAssertEqual($0 as? RemoteRelayError, .sequenceGap)
        }
        XCTAssertNotNil(try codec.receive(frame(sequence: 8, message: ["id": 2, "result": [:]])))
    }

    func testWrongDestinationIsFatalEvenOnOldStream() throws {
        var codec = try codec()
        XCTAssertThrowsError(try codec.receive(frame(stream: "old", host: "other"))) {
            XCTAssertEqual($0 as? RemoteRelayError, .wrongDestination)
        }
    }

    func testChunksRejectedWithoutAllocationAndStaleChunksIgnored() throws {
        var codec = try codec()
        XCTAssertNil(try codec.receive(frame(stream: "old", type: "server_message_chunk")))
        XCTAssertThrowsError(try codec.receive(frame(type: "server_message_chunk"))) {
            XCTAssertEqual($0 as? RemoteRelayError, .chunksUnsupported)
        }
        XCTAssertThrowsError(try codec.receive(Data(repeating: 65, count: RemoteRelayCodec.maximumFrameBytes + 1))) {
            XCTAssertEqual($0 as? RemoteRelayError, .frameTooLarge)
        }
    }

    func testOutgoingLimitDoesNotAdvanceSequenceOrReserveRequest() throws {
        var codec = try codec()
        let message = try JSONSerialization.data(withJSONObject: ["id": 1, "method": String(repeating: "x", count: RemoteRelayCodec.maximumFrameBytes - 60)])
        XCTAssertThrowsError(try codec.envelope(message))
        XCTAssertEqual(codec.nextSequence, 1)
        XCTAssertNil(codec.pendingID)
    }

    func testSinglePendingRequestAndUncorrelatedRelayError() throws {
        var codec = try codec(); try start(&codec)
        XCTAssertThrowsError(try start(&codec, id: 2)) {
            XCTAssertEqual($0 as? RemoteRelayError, .busy)
        }
        XCTAssertThrowsError(try codec.receive(frame(message: ["type": "error", "code": "unavailable"]))) {
            XCTAssertEqual($0 as? RemoteRelayError, .remoteFailure)
        }
        // A relay-level error cannot correlate a definite mutation failure.
        XCTAssertEqual(codec.pendingID, 1)
    }

    func testNotificationDoesNotCompleteReadAndMalformedResultFails() throws {
        var codec = try codec(); try start(&codec)
        XCTAssertNil(try codec.receive(frame(message: ["method": "thread/updated", "params": [:]])))
        XCTAssertThrowsError(try codec.receive(frame(sequence: 2, message: ["id": 1, "result": [:], "error": [:]])))
        XCTAssertEqual(codec.pendingID, 1)
    }

    func testRejectsBooleanFractionalAndMissingSequence() throws {
        for value in [true, 1.5, -1, "1", NSNull(), 9_007_199_254_740_992 as Int, Int.max] as [Any] {
            var codec = try codec()
            var object = try RemoteRelayCodec.object(frame())
            object["seq_id"] = value
            XCTAssertThrowsError(try codec.receive(JSONSerialization.data(withJSONObject: object)))
        }
    }

    func testSafeIntegerBoundaryAndInitializationCompatibility() throws {
        XCTAssertEqual(try RemoteRelayCodec.integer(NSNumber(value: 9_007_199_254_740_991 as Int)), RemoteRelayCodec.maximumSafeInteger)
        XCTAssertThrowsError(try RemoteRelayCodec.request(id: 9_007_199_254_740_992, method: "thread/list"))
        let message = try RemoteRelayCodec.object(RemoteRelayCodec.request(id: 1, method: "initialize"))
        let params = try XCTUnwrap(message["params"] as? [String: Any])
        // Matches probe.mjs: do not opt this read-only client into experimental methods.
        XCTAssertTrue(params["capabilities"] is NSNull)
    }

    func testNoReadBeforeAuthorizedConnection() async {
        let relay = RemoteRelay()
        do { _ = try await relay.listThreads(); XCTFail("Read must require initialization") }
        catch { XCTAssertEqual(error as? RemoteRelayError, .notInitialized) }
        do { _ = try await relay.readThread(id: "existing"); XCTFail("Read must require initialization") }
        catch { XCTAssertEqual(error as? RemoteRelayError, .notInitialized) }
        await relay.disconnect()
    }
    func testReadFailuresPreserveSafeCauseAndMutationsRemainUnknown() {
        let cases: [(Error, RemoteRelayError)] = [
            (CancellationError(), .cancelled), (URLError(.cancelled), .cancelled),
            (URLError(.timedOut), .timedOut), (URLError(.networkConnectionLost), .transportFailed),
            (RemoteRelayError.chunksUnsupported, .chunksUnsupported),
            (RemoteRelayError.frameTooLarge, .frameTooLarge),
            (RemoteRelayError.sequenceGap, .sequenceGap),
            (RemoteRelayError.disconnected, .disconnected)
        ]
        for (error, expected) in cases {
            for method in ["initialize", "thread/list", "thread/read"] {
                XCTAssertEqual(RemoteRelay.failureAfterDispatch(error, method: method, requestID: 7), expected)
            }
            let mutatingMethods: [String?] = ["thread/resume", "turn/start", "turn/interrupt", "future/method", nil]
            for method in mutatingMethods {
                XCTAssertEqual(RemoteRelay.failureAfterDispatch(error, method: method, requestID: 7), .outcomeUnknown(requestID: 7))
            }
        }
    }

}
