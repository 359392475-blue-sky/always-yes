import Foundation
import ServiceManagement
import os

enum DaemonInstaller {
    private static let log = Logger(subsystem: "ai.yesengineer", category: "installer")
    static let plistName = "ai.yesengineer.daemon.plist"

    static var service: SMAppService {
        SMAppService.daemon(plistName: plistName)
    }

    static func install() throws {
        try service.register()
        log.info("daemon registered")
    }

    static func uninstall() throws {
        try service.unregister()
        log.info("daemon unregistered")
    }

    static var status: SMAppService.Status {
        service.status
    }

    static var statusDescription: String {
        switch service.status {
        case .notRegistered: return L10n.text("Not installed", "未安装")
        case .enabled: return L10n.text("Enabled", "已启用")
        case .requiresApproval: return L10n.text("Approval required in System Settings", "需在系统设置中批准")
        case .notFound: return L10n.text("plist not found", "未找到 plist")
        @unknown default: return L10n.text("Unknown", "未知")
        }
    }
}
