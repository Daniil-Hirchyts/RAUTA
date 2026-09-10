import CoreGraphics
import SwiftUI

/// An SVG `d` attribute, turned into a `Path`.
///
/// The anatomy map ships as path data, so the outlines have to be read the way a
/// browser reads them: every command the generator emits, absolute and relative,
/// including the shorthand curves and the elliptical arc.
enum SVGPath {
    static func parse(_ definition: String) -> Path? {
        var scanner = Scanner(definition)
        var path = Path()
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var lastControl: CGPoint?
        var lastQuadControl: CGPoint?
        var command: Character?
        var started = false

        while true {
            scanner.skipSeparators()
            if let next = scanner.peekCommand() {
                command = next
                scanner.advance()
            } else if scanner.isAtEnd {
                break
            } else if command == nil {
                return nil
            }
            guard let active = command else { break }

            let relative = active.isLowercase
            func point(_ x: Double, _ y: Double) -> CGPoint {
                relative
                    ? CGPoint(x: current.x + x, y: current.y + y)
                    : CGPoint(x: x, y: y)
            }

            switch Character(active.uppercased()) {
            case "M":
                guard let x = scanner.number(), let y = scanner.number() else { return finish(path, started) }
                current = point(x, y)
                subpathStart = current
                path.move(to: current)
                started = true
                // A second coordinate pair after a moveto is an implicit lineto.
                command = relative ? "l" : "L"

            case "L":
                guard let x = scanner.number(), let y = scanner.number() else { break }
                current = point(x, y)
                path.addLine(to: current)
                lastControl = nil
                lastQuadControl = nil

            case "H":
                guard let x = scanner.number() else { break }
                current = CGPoint(x: relative ? current.x + x : x, y: current.y)
                path.addLine(to: current)
                lastControl = nil
                lastQuadControl = nil

            case "V":
                guard let y = scanner.number() else { break }
                current = CGPoint(x: current.x, y: relative ? current.y + y : y)
                path.addLine(to: current)
                lastControl = nil
                lastQuadControl = nil

            case "C":
                guard let x1 = scanner.number(), let y1 = scanner.number(),
                      let x2 = scanner.number(), let y2 = scanner.number(),
                      let x = scanner.number(), let y = scanner.number()
                else { break }
                let control1 = point(x1, y1)
                let control2 = point(x2, y2)
                current = point(x, y)
                path.addCurve(to: current, control1: control1, control2: control2)
                lastControl = control2
                lastQuadControl = nil

            case "S":
                guard let x2 = scanner.number(), let y2 = scanner.number(),
                      let x = scanner.number(), let y = scanner.number()
                else { break }
                let control1 = lastControl.map {
                    CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y)
                } ?? current
                let control2 = point(x2, y2)
                current = point(x, y)
                path.addCurve(to: current, control1: control1, control2: control2)
                lastControl = control2
                lastQuadControl = nil

            case "Q":
                guard let x1 = scanner.number(), let y1 = scanner.number(),
                      let x = scanner.number(), let y = scanner.number()
                else { break }
                let control = point(x1, y1)
                current = point(x, y)
                path.addQuadCurve(to: current, control: control)
                lastQuadControl = control
                lastControl = nil

            case "T":
                guard let x = scanner.number(), let y = scanner.number() else { break }
                let control = lastQuadControl.map {
                    CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y)
                } ?? current
                current = point(x, y)
                path.addQuadCurve(to: current, control: control)
                lastQuadControl = control
                lastControl = nil

            case "A":
                guard let rx = scanner.number(), let ry = scanner.number(),
                      let rotation = scanner.number(),
                      let largeArc = scanner.flag(), let sweep = scanner.flag(),
                      let x = scanner.number(), let y = scanner.number()
                else { break }
                let end = point(x, y)
                appendArc(
                    to: &path,
                    from: current,
                    to: end,
                    radii: CGSize(width: abs(rx), height: abs(ry)),
                    rotationDegrees: rotation,
                    largeArc: largeArc,
                    sweep: sweep
                )
                current = end
                lastControl = nil
                lastQuadControl = nil

            case "Z":
                path.closeSubpath()
                current = subpathStart
                lastControl = nil
                lastQuadControl = nil

            default:
                return finish(path, started)
            }

            if scanner.isAtEnd { break }
        }
        return finish(path, started)
    }

    private static func finish(_ path: Path, _ started: Bool) -> Path? {
        started ? path : nil
    }

    /// The endpoint parameterisation SVG uses, converted to the centre form
    /// `Path` can draw, following the implementation notes in the SVG spec.
    private static func appendArc(
        to path: inout Path,
        from start: CGPoint,
        to end: CGPoint,
        radii: CGSize,
        rotationDegrees: Double,
        largeArc: Bool,
        sweep: Bool
    ) {
        guard radii.width > 0, radii.height > 0 else {
            path.addLine(to: end)
            return
        }
        if start == end { return }

        let phi = rotationDegrees * .pi / 180
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)

        let dx2 = (start.x - end.x) / 2
        let dy2 = (start.y - end.y) / 2
        let x1p = cosPhi * dx2 + sinPhi * dy2
        let y1p = -sinPhi * dx2 + cosPhi * dy2

        var rx = radii.width
        var ry = radii.height
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            let scale = sqrt(lambda)
            rx *= scale
            ry *= scale
        }

        let sign: CGFloat = largeArc == sweep ? -1 : 1
        let numerator = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
        let denominator = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        let coefficient = denominator == 0 ? 0 : sign * sqrt(Swift.max(0, numerator / denominator))

        let cxp = coefficient * rx * y1p / ry
        let cyp = -coefficient * ry * x1p / rx
        let cx = cosPhi * cxp - sinPhi * cyp + (start.x + end.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (start.y + end.y) / 2

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy
            let length = sqrt(ux * ux + uy * uy) * sqrt(vx * vx + vy * vy)
            guard length > 0 else { return 0 }
            let value = Swift.max(-1, Swift.min(1, dot / length))
            let result = acos(value)
            return (ux * vy - uy * vx) < 0 ? -result : result
        }

        let startAngle = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var deltaAngle = angle(
            (x1p - cxp) / rx, (y1p - cyp) / ry,
            (-x1p - cxp) / rx, (-y1p - cyp) / ry
        )
        if !sweep && deltaAngle > 0 { deltaAngle -= 2 * .pi }
        if sweep && deltaAngle < 0 { deltaAngle += 2 * .pi }

        // Keep the arc in the current SVG subpath. Building a separate
        // CGMutablePath and adding it here creates a new subpath; when the
        // shape is filled SwiftUI then closes that detached arc with a chord.
        // That showed up most obviously as a straight bar across the anatomy
        // head, and it also made `Path.contains` disagree with the browser.
        //
        // Split the unit-circle arc into <= 90 degree cubic Bézier segments,
        // then transform those control points into the requested ellipse.
        let transform = CGAffineTransform(translationX: cx, y: cy)
            .rotated(by: phi)
            .scaledBy(x: rx, y: ry)
        let segmentCount = Swift.max(1, Int(ceil(abs(deltaAngle) / (.pi / 2))))
        let segmentAngle = deltaAngle / CGFloat(segmentCount)

        for index in 0..<segmentCount {
            let theta0 = startAngle + CGFloat(index) * segmentAngle
            let theta1 = theta0 + segmentAngle
            let alpha = 4 / 3 * tan(segmentAngle / 4)

            let cos0 = cos(theta0)
            let sin0 = sin(theta0)
            let cos1 = cos(theta1)
            let sin1 = sin(theta1)

            let control1 = CGPoint(
                x: cos0 - alpha * sin0,
                y: sin0 + alpha * cos0
            ).applying(transform)
            let control2 = CGPoint(
                x: cos1 + alpha * sin1,
                y: sin1 - alpha * cos1
            ).applying(transform)
            let curveEnd = index == segmentCount - 1
                ? end
                : CGPoint(x: cos1, y: sin1).applying(transform)

            path.addCurve(to: curveEnd, control1: control1, control2: control2)
        }
    }
}

/// A small forward-only reader over the path data.
private struct Scanner {
    private let characters: [Character]
    private var index: Int = 0

    init(_ text: String) { characters = Array(text) }

    var isAtEnd: Bool { index >= characters.count }

    mutating func advance() { index += 1 }

    func peekCommand() -> Character? {
        guard index < characters.count else { return nil }
        let character = characters[index]
        return "MmLlHhVvCcSsQqTtAaZz".contains(character) ? character : nil
    }

    mutating func skipSeparators() {
        while index < characters.count {
            let character = characters[index]
            if character == "," || character.isWhitespace { index += 1 } else { break }
        }
    }

    mutating func number() -> Double? {
        skipSeparators()
        var text = ""
        var seenDigit = false
        while index < characters.count {
            let character = characters[index]
            if character == "-" || character == "+" {
                // A sign is only part of this number at its start, or straight
                // after an exponent marker.
                if text.isEmpty || text.last == "e" || text.last == "E" {
                    text.append(character)
                    index += 1
                    continue
                }
                break
            }
            if character.isNumber {
                text.append(character)
                seenDigit = true
                index += 1
                continue
            }
            if character == "." {
                // A second dot begins the next number: "1.5.5" is two values.
                if text.contains(".") { break }
                text.append(character)
                index += 1
                continue
            }
            if character == "e" || character == "E", seenDigit {
                text.append(character)
                index += 1
                continue
            }
            break
        }
        return seenDigit ? Double(text) : nil
    }

    /// Arc flags are single characters and may run together with what follows.
    mutating func flag() -> Bool? {
        skipSeparators()
        guard index < characters.count else { return nil }
        let character = characters[index]
        guard character == "0" || character == "1" else { return number().map { $0 != 0 } }
        index += 1
        return character == "1"
    }
}
