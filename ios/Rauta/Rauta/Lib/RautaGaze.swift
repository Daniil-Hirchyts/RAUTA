import CoreGraphics
import Foundation

enum RautaGaze {
    /// Where the eyes sit when they are not looking at anything.
    ///
    /// Not dead centre: eyes parked on exactly the same pixel every time are the
    /// one thing that reads as a still image. Each rest is a slightly different
    /// place, close enough to centre to still be facing you.
    static func rest(random: () -> Double) -> (x: Double, y: Double) {
        (x: (random() - 0.5) * 0.24, y: (random() - 0.5) * 0.14)
    }

    /// The eye direction that looks from `frame` toward `point`, both in the
    /// same coordinate space.
    ///
    /// Soft saturation rather than a clamp: a tap just beside the character
    /// moves its eyes a little, anything across the screen pins them to the edge,
    /// and nothing in between jumps.
    static func toward(_ point: CGPoint, from frame: CGRect) -> (x: Double, y: Double) {
        let dx = Double(point.x - frame.midX)
        let dy = Double(point.y - frame.midY)
        let reachX = Swift.max(60, Double(frame.width) * 0.9)
        let reachY = Swift.max(80, Double(frame.height) * 1.2)
        return (dx / (abs(dx) + reachX), dy / (abs(dy) + reachY))
    }
}
