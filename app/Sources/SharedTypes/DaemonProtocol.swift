import Foundation

public let YesEngineerDaemonMachServiceName = "ai.yesengineer.daemon"

@objc public protocol YesEngineerDaemonProtocol {
    func ping(reply: @escaping (String) -> Void)
    func updateConfig(_ data: Data, reply: @escaping (Bool) -> Void)
    func subscribe(reply: @escaping (Bool) -> Void)
}

@objc public protocol YesEngineerClientProtocol {
    func slapDetected(_ data: Data)
}
