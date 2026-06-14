import Foundation
import SharedTypes
import os

final class DaemonClient: NSObject, YesEngineerClientProtocol {
    private let log = Logger(subsystem: "ai.yesengineer", category: "client")
    private var connection: NSXPCConnection?
    private var reconnectWorkItem: DispatchWorkItem?
    var onSlap: ((SlapEvent) -> Void)?
    var onConnected: (() -> Void)?

    func connect() {
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil

        let conn = NSXPCConnection(machServiceName: YesEngineerDaemonMachServiceName, options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: YesEngineerDaemonProtocol.self)
        conn.exportedInterface = NSXPCInterface(with: YesEngineerClientProtocol.self)
        conn.exportedObject = self
        conn.invalidationHandler = { [weak self, weak conn] in
            self?.handleDisconnect("invalidated", connection: conn)
        }
        conn.interruptionHandler = { [weak self, weak conn] in
            self?.handleDisconnect("interrupted", connection: conn)
        }
        conn.resume()
        self.connection = conn

        proxy(for: conn)?.subscribe { [weak self] ok in
            guard let self = self else { return }
            self.log.info("subscribe: \(ok, privacy: .public)")
            if ok {
                DispatchQueue.main.async { self.onConnected?() }
            } else {
                self.scheduleReconnect()
            }
        }
    }

    func ping(reply: @escaping (String?) -> Void) {
        guard let p = proxy() else { reply(nil); return }
        p.ping { reply($0) }
    }

    func push(config: DaemonConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        proxy()?.updateConfig(data) { _ in }
    }

    private func proxy() -> YesEngineerDaemonProtocol? {
        guard let connection = connection else { return nil }
        return proxy(for: connection)
    }

    private func proxy(for connection: NSXPCConnection) -> YesEngineerDaemonProtocol? {
        connection.remoteObjectProxyWithErrorHandler { [weak self] err in
            self?.log.error("xpc proxy: \(err.localizedDescription, privacy: .public)")
        } as? YesEngineerDaemonProtocol
    }

    private func handleDisconnect(_ reason: String, connection disconnected: NSXPCConnection?) {
        log.error("xpc: \(reason, privacy: .public)")
        if let disconnected = disconnected, connection !== disconnected {
            return
        }
        connection = nil
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard reconnectWorkItem == nil else { return }
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.reconnectWorkItem = nil
            self.connect()
        }
        reconnectWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: item)
    }

    // MARK: YesEngineerClientProtocol

    func slapDetected(_ data: Data) {
        guard let event = try? JSONDecoder().decode(SlapEvent.self, from: data) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onSlap?(event)
        }
    }
}
