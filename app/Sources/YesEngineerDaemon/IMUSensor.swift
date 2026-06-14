import Foundation
import IOKit
import IOKit.hid

private let pageVendor: Int = 0xFF00
private let usageAccel: Int = 3
private let reportBufSize = 4096
private let reportIntervalUS: Int32 = 1000

final class IMUSensor {
    var onSample: ((Double, Double, Double) -> Void)?

    private var openedDevices: [IOHIDDevice] = []
    private var reportBuffers: [UnsafeMutablePointer<UInt8>] = []

    func start() throws {
        try wakeDrivers()
        try registerDevices()
    }

    private func wakeDrivers() throws {
        let matching = IOServiceMatching("AppleSPUHIDDriver")
        var iter: io_iterator_t = 0
        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter)
        guard kr == KERN_SUCCESS else {
            throw NSError(domain: "IMUSensor", code: Int(kr),
                          userInfo: [NSLocalizedDescriptionKey: "AppleSPUHIDDriver match failed"])
        }
        defer { IOObjectRelease(iter) }

        while case let svc = IOIteratorNext(iter), svc != 0 {
            setInt32Property(svc, key: "SensorPropertyReportingState", value: 1)
            setInt32Property(svc, key: "SensorPropertyPowerState", value: 1)
            setInt32Property(svc, key: "ReportInterval", value: reportIntervalUS)
            IOObjectRelease(svc)
        }
    }

    private func registerDevices() throws {
        let matching = IOServiceMatching("AppleSPUHIDDevice")
        var iter: io_iterator_t = 0
        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter)
        guard kr == KERN_SUCCESS else {
            throw NSError(domain: "IMUSensor", code: Int(kr),
                          userInfo: [NSLocalizedDescriptionKey: "AppleSPUHIDDevice match failed"])
        }
        defer { IOObjectRelease(iter) }

        var foundAccel = false
        while case let svc = IOIteratorNext(iter), svc != 0 {
            defer { IOObjectRelease(svc) }
            let up = readInt32Property(svc, key: "PrimaryUsagePage")
            let u = readInt32Property(svc, key: "PrimaryUsage")
            guard up == pageVendor, u == usageAccel else { continue }

            guard let device = IOHIDDeviceCreate(kCFAllocatorDefault, svc) else { continue }
            let openKR = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
            guard openKR == kIOReturnSuccess else { continue }

            let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: reportBufSize)
            buf.initialize(repeating: 0, count: reportBufSize)
            reportBuffers.append(buf)
            openedDevices.append(device)

            let context = Unmanaged.passUnretained(self).toOpaque()
            IOHIDDeviceRegisterInputReportCallback(
                device,
                buf,
                CFIndex(reportBufSize),
                imuReportCallback,
                context
            )
            IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            foundAccel = true
        }

        guard foundAccel else {
            throw NSError(domain: "IMUSensor", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No AppleSPUHIDDevice with accel usage found"])
        }
    }

    fileprivate func handleReport(_ buf: UnsafePointer<UInt8>, length: Int) {
        guard let (x, y, z) = ReportParser.parse(buf, length: length) else { return }
        onSample?(x, y, z)
    }

    private func setInt32Property(_ entry: io_registry_entry_t, key: String, value: Int32) {
        var v = value
        let num = CFNumberCreate(kCFAllocatorDefault, .sInt32Type, &v)
        IORegistryEntrySetCFProperty(entry, key as CFString, num)
    }

    private func readInt32Property(_ entry: io_registry_entry_t, key: String) -> Int {
        guard let ref = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0) else {
            return -1
        }
        let cf = ref.takeRetainedValue()
        guard CFGetTypeID(cf) == CFNumberGetTypeID() else { return -1}
        let num = cf as! CFNumber
        var out: Int32 = 0
        CFNumberGetValue(num, .sInt32Type, &out)
        return Int(out)
    }
}

private func imuReportCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    type: IOHIDReportType,
    reportID: UInt32,
    report: UnsafeMutablePointer<UInt8>,
    reportLength: CFIndex
) {
    guard let context = context else { return }
    let sensor = Unmanaged<IMUSensor>.fromOpaque(context).takeUnretainedValue()
    sensor.handleReport(report, length: Int(reportLength))
}
