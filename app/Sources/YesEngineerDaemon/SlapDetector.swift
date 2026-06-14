import Foundation

// v0.2.0 simplified detector: high-pass + magnitude threshold.
// v0.2.2 will replace this with the full 6-detector port.
final class SlapDetector {
    // 1-pole high-pass to remove gravity DC.
    // alpha tuned for ~1kHz sample rate, ~1 Hz cutoff.
    private let alpha: Double = 0.995
    private var lastX = 0.0, lastY = 0.0, lastZ = 0.0
    private var hpX = 0.0, hpY = 0.0, hpZ = 0.0
    private var primed = false

    // Recent peak magnitude (one-sample window — slap is impulsive).
    func process(x: Double, y: Double, z: Double) -> Double {
        if !primed {
            lastX = x; lastY = y; lastZ = z
            primed = true
            return 0
        }
        hpX = alpha * (hpX + x - lastX)
        hpY = alpha * (hpY + y - lastY)
        hpZ = alpha * (hpZ + z - lastZ)
        lastX = x; lastY = y; lastZ = z
        return (hpX * hpX + hpY * hpY + hpZ * hpZ).squareRoot()
    }
}
