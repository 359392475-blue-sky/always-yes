import Foundation
import SharedTypes
import os

let log = Logger(subsystem: "ai.yesengineer", category: "daemon")
log.info("yes-engineer daemon starting")

var config = DaemonConfig()
let detector = SlapDetector()
let xpc = XPCService(machServiceName: YesEngineerDaemonMachServiceName)

xpc.configHandler = { newCfg in
    config = newCfg
    log.debug("config updated: amp=\(newCfg.minAmplitude), cooldown=\(newCfg.cooldownMs)ms")
}

let sensor = IMUSensor()
var lastSlap = Date.distantPast
let cooldownQueue = DispatchQueue(label: "ai.yesengineer.cooldown")

sensor.onSample = { x, y, z in
    let mag = detector.process(x: x, y: y, z: z)
    guard mag >= config.minAmplitude else { return }

    var fire = false
    cooldownQueue.sync {
        let now = Date()
        let cooldown = TimeInterval(config.cooldownMs) / 1000.0
        if now.timeIntervalSince(lastSlap) >= cooldown {
            lastSlap = now
            fire = true
        }
    }
    guard fire else { return }

    let event = SlapEvent(
        amplitude: mag,
        timestamp: Date(),
        severity: mag > 0.4 ? "hard" : (mag > 0.2 ? "medium" : "light")
    )
    log.info("slap amp=\(mag, format: .fixed(precision: 4))")
    xpc.broadcast(slap: event)
}

do {
    try sensor.start()
} catch {
    log.error("sensor start failed: \(error.localizedDescription, privacy: .public)")
    exit(1)
}

xpc.resume()
log.info("xpc listening on \(YesEngineerDaemonMachServiceName, privacy: .public)")

CFRunLoopRun()
