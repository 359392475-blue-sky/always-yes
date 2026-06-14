import Foundation

enum ReportParser {
    static let imuReportLen = 22
    static let imuDataOffset = 6
    static let scale: Double = 1.0 / 65536.0

    static func parse(_ buf: UnsafePointer<UInt8>, length: Int) -> (x: Double, y: Double, z: Double)? {
        guard length == imuReportLen else { return nil }
        let off = imuDataOffset
        let xi = readInt32LE(buf, offset: off)
        let yi = readInt32LE(buf, offset: off + 4)
        let zi = readInt32LE(buf, offset: off + 8)
        return (Double(xi) * scale, Double(yi) * scale, Double(zi) * scale)
    }

    private static func readInt32LE(_ buf: UnsafePointer<UInt8>, offset: Int) -> Int32 {
        let u = UInt32(buf[offset])
              | (UInt32(buf[offset + 1]) << 8)
              | (UInt32(buf[offset + 2]) << 16)
              | (UInt32(buf[offset + 3]) << 24)
        return Int32(bitPattern: u)
    }
}
