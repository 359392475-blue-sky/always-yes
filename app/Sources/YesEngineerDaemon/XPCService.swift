import Foundation
import SharedTypes
import os

final class XPCService: NSObject, NSXPCListenerDelegate, YesEngineerDaemonProtocol {
    private let listener: NSXPCListener
    private var subscribers: [NSXPCConnection] = []
    private let lock = NSLock()
    private let log = Logger(subsystem: "ai.yesengineer", category: "xpc")

    var configHandler: ((DaemonConfig) -> Void)?

    init(machServiceName: String) {
        self.listener = NSXPCListener(machServiceName: machServiceName)
        super.init()
        self.listener.delegate = self
    }

    func resume() {
        listener.resume()
    }

    // MARK: NSXPCListenerDelegate

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection conn: NSXPCConnection) -> Bool {
        conn.exportedInterface = NSXPCInterface(with: YesEngineerDaemonProtocol.self)
        conn.exportedObject = self
        conn.remoteObjectInterface = NSXPCInterface(with: YesEngineerClientProtocol.self)
        conn.invalidationHandler = { [weak self, weak conn] in
            self?.removeSubscriber(conn)
        }
        conn.interruptionHandler = { [weak self, weak conn] in
            self?.removeSubscriber(conn)
        }
        conn.resume()
        log.info("xpc: connection accepted")
        return true
    }

    private func removeSubscriber(_ conn: NSXPCConnection?) {
        guard let conn = conn else { return }
        lock.lock()
        subscribers.removeAll { $0 === conn }
        lock.unlock()
    }

    // MARK: YesEngineerDaemonProtocol

    func ping(reply: @escaping (String) -> Void) {
        reply("pong")
    }

    func updateConfig(_ data: Data, reply: @escaping (Bool) -> Void) {
        guard let cfg = try? JSONDecoder().decode(DaemonConfig.self, from: data) else {
            reply(false); return
        }
        configHandler?(cfg)
        reply(true)
    }

    func subscribe(reply: @escaping (Bool) -> Void) {
        guard let conn = NSXPCConnection.current() else { reply(false); return }
        lock.lock()
        subscribers.append(conn)
        lock.unlock()
        log.info("xpc: subscribed (total=\(self.subscribers.count, privacy: .public))")
        reply(true)
    }

    // MARK: Broadcast

    func broadcast(slap: SlapEvent) {
        guard let data = try? JSONEncoder().encode(slap) else { return }
        lock.lock()
        let snapshot = subscribers
        lock.unlock()
        for conn in snapshot {
            let proxy = conn.remoteObjectProxyWithErrorHandler { [weak self] err in
                self?.log.error("xpc broadcast: \(err.localizedDescription, privacy: .public)")
            } as? YesEngineerClientProtocol
            proxy?.slapDetected(data)
        }
    }
}
