import Foundation
import WatchConnectivity

// WCSession availability says nothing about Codex Remote authentication.
final class CompanionConnectivity: NSObject, WCSessionDelegate {
    var onActivated: (() -> Void)?
    var onStatus: ((Bool, String) -> Void)?
    var onSnapshot: ((Snapshot) -> Void)?
    var onCommand: ((Command) -> Reply)?
    private var session: WCSession?

    func activate() {
        guard WCSession.isSupported() else { onStatus?(false, "此设备不支持 WatchConnectivity"); return }
        let session = WCSession.default
        self.session = session
        session.delegate = self
        session.activate()
    }
    func publish(_ snapshot: Snapshot) {
        guard let session, session.activationState == .activated else { return }
        do { try session.updateApplicationContext([Wire.key: Wire.encode(snapshot)]) }
        catch { onStatus?(session.isReachable, "快照同步失败：\(error.localizedDescription)") }
    }
    func send(_ command: Command, completion: @escaping (Result<Reply, Error>) -> Void) {
        guard let session, session.activationState == .activated, session.isReachable else {
            completion(.failure(WireError.invalid("iPhone 当前不可达；请求未发送"))); return
        }
        do {
            let data = try Wire.encode(command)
            session.sendMessage([Wire.key: data], replyHandler: { message in
                let result = Result { () throws -> Reply in
                    guard let data = message[Wire.key] as? Data else { throw WireError.invalid("iPhone 返回了无效回执") }
                    let reply = try Wire.decode(Reply.self, from: data)
                    guard reply.version == 1, reply.requestID == command.id else { throw WireError.invalid("回执不属于本次请求") }
                    try reply.snapshot.validate()
                    return reply
                }
                DispatchQueue.main.async { completion(result) }
            }, errorHandler: { error in
                DispatchQueue.main.async { completion(.failure(error)) }
            })
        } catch { completion(.failure(error)) }
    }
    private func report(_ session: WCSession, error: Error? = nil) {
        DispatchQueue.main.async { [weak self] in
            let active = session.activationState == .activated
            let reachable = active && session.isReachable
            self?.onStatus?(reachable, error.map { "设备链路：\($0.localizedDescription)" } ??
                (reachable ? "iPhone ↔ Watch 可达" : "设备暂不可达；可查看演示快照"))
        }
    }
    private func receive(_ context: [String: Any]) {
        guard let data = context[Wire.key] as? Data else { return }
        do {
            let snapshot = try Wire.decode(Snapshot.self, from: data)
            try snapshot.validate()
            DispatchQueue.main.async { [weak self] in self?.onSnapshot?(snapshot) }
        } catch {
            DispatchQueue.main.async { [weak self] in self?.onStatus?(false, "收到无效快照，已忽略") }
        }
    }
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        report(session, error: error)
        if activationState == .activated {
            receive(session.receivedApplicationContext)
            DispatchQueue.main.async { [weak self] in self?.onActivated?() }
        }
    }
    func sessionReachabilityDidChange(_ session: WCSession) { report(session) }
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) { receive(applicationContext) }
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        guard let data = message[Wire.key] as? Data, let command = try? Wire.decode(Command.self, from: data) else {
            replyHandler(["error": "Invalid demo request"]); return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, let reply = self.onCommand?(command), let data = try? Wire.encode(reply) else {
                replyHandler(["error": "Demo handler unavailable"]); return
            }
            replyHandler([Wire.key: data])
        }
    }
    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) { report(session) }
    func sessionDidDeactivate(_ session: WCSession) {
        report(session)
        session.activate()
    }
    func sessionWatchStateDidChange(_ session: WCSession) { report(session) }
    #endif
}
