import SwiftUI

/// A small SVG renderer, scoped to what the bundled character artwork uses:
/// nested groups with transforms, filled and stroked paths, rectangles, linear
/// and radial gradients, and clip paths.
///
/// The character stays vector so it is crisp at every size the app draws it, and
/// so its face can be animated natively rather than baked into a bitmap.
struct VectorArtwork {
    var viewBox: CGRect
    var root: VectorGroup
    var gradients: [String: VectorGradient]
    var clipPaths: [String: Path]

    /// The named group a caller wants to draw or animate on its own.
    func group(_ id: String) -> VectorGroup? { root.find(id) }
}

struct VectorGroup {
    var id: String?
    var transform: CGAffineTransform
    var clipPathId: String?
    var opacity: Double
    var children: [VectorNode]

    func find(_ id: String) -> VectorGroup? {
        if self.id == id { return self }
        for child in children {
            if case .group(let group) = child, let found = group.find(id) { return found }
        }
        return nil
    }
}

enum VectorNode {
    case group(VectorGroup)
    case shape(VectorShape)
}

struct VectorShape {
    var id: String?
    var path: Path
    var fill: VectorPaint?
    var stroke: VectorPaint?
    var strokeWidth: CGFloat
    var strokeCap: CGLineCap
    var opacity: Double
    var evenOdd: Bool
}

enum VectorPaint {
    case color(Color)
    case gradient(String)
}

struct VectorGradient {
    enum Kind { case linear, radial }
    var kind: Kind
    var start: CGPoint
    var end: CGPoint
    var center: CGPoint
    var radius: CGFloat
    var stops: [Gradient.Stop]
}

// MARK: - Parsing

enum VectorArtworkLoader {
    private static var cache: [String: VectorArtwork] = [:]

    static func load(contentsOf url: URL) -> VectorArtwork? {
        if let cached = cache[url.path] { return cached }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        guard let parsed = parse(text) else { return nil }
        cache[url.path] = parsed
        return parsed
    }

    static func parse(_ text: String) -> VectorArtwork? {
        let elements = XMLReader.elements(in: text)
        guard let svg = elements.first(where: { $0.name == "svg" }) else { return nil }

        let box = (svg.attributes["viewBox"] ?? "0 0 512 512")
            .split(whereSeparator: { $0 == " " || $0 == "," })
            .compactMap { Double($0) }
        let viewBox = box.count == 4
            ? CGRect(x: box[0], y: box[1], width: box[2], height: box[3])
            : CGRect(x: 0, y: 0, width: 512, height: 512)

        var gradients: [String: VectorGradient] = [:]
        var clipPaths: [String: Path] = [:]
        for element in svg.descendants {
            switch element.name {
            case "linearGradient", "radialGradient":
                guard let id = element.attributes["id"] else { continue }
                gradients[id] = gradient(from: element)
            case "clipPath":
                guard let id = element.attributes["id"] else { continue }
                var combined = Path()
                for child in element.children where child.name == "path" {
                    if let definition = child.attributes["d"], let path = SVGPath.parse(definition) {
                        combined.addPath(path)
                    }
                }
                clipPaths[id] = combined
            default:
                break
            }
        }

        let root = group(from: svg)
        return VectorArtwork(
            viewBox: viewBox, root: root, gradients: gradients, clipPaths: clipPaths
        )
    }

    private static func gradient(from element: XMLElement) -> VectorGradient {
        let stops = element.children.filter { $0.name == "stop" }.map { stop -> Gradient.Stop in
            let offset = Double(stop.attributes["offset"] ?? "0") ?? 0
            let opacity = Double(stop.attributes["stop-opacity"] ?? "1") ?? 1
            let color = parseColor(stop.attributes["stop-color"] ?? "#000000") ?? .black
            return Gradient.Stop(color: color.opacity(opacity), location: offset)
        }
        let number: (String, CGFloat) -> CGFloat = { key, fallback in
            element.attributes[key].flatMap { Double($0) }.map { CGFloat($0) } ?? fallback
        }
        if element.name == "radialGradient" {
            let center = CGPoint(x: number("cx", 0), y: number("cy", 0))
            return VectorGradient(
                kind: .radial, start: center, end: center,
                center: center, radius: number("r", 1), stops: stops
            )
        }
        return VectorGradient(
            kind: .linear,
            start: CGPoint(x: number("x1", 0), y: number("y1", 0)),
            end: CGPoint(x: number("x2", 0), y: number("y2", 1)),
            center: .zero, radius: 0, stops: stops
        )
    }

    private static func group(from element: XMLElement) -> VectorGroup {
        var children: [VectorNode] = []
        for child in element.children {
            switch child.name {
            case "g":
                children.append(.group(group(from: child)))
            case "path":
                if let shape = shape(from: child) { children.append(.shape(shape)) }
            case "rect":
                if let shape = rect(from: child) { children.append(.shape(shape)) }
            default:
                break
            }
        }
        return VectorGroup(
            id: element.attributes["id"],
            transform: transform(element.attributes["transform"]),
            clipPathId: reference(element.attributes["clip-path"]),
            opacity: Double(element.attributes["opacity"] ?? "1") ?? 1,
            children: children
        )
    }

    private static func shape(from element: XMLElement) -> VectorShape? {
        guard let definition = element.attributes["d"], let path = SVGPath.parse(definition)
        else { return nil }
        return VectorShape(
            id: element.attributes["id"],
            path: path.applying(transform(element.attributes["transform"])),
            fill: paint(element.attributes["fill"] ?? "#000000"),
            stroke: paint(element.attributes["stroke"]),
            strokeWidth: CGFloat(Double(element.attributes["stroke-width"] ?? "1") ?? 1),
            strokeCap: element.attributes["stroke-linecap"] == "round" ? .round : .butt,
            opacity: Double(element.attributes["opacity"] ?? "1") ?? 1,
            evenOdd: element.attributes["fill-rule"] == "evenodd"
        )
    }

    private static func rect(from element: XMLElement) -> VectorShape? {
        let number: (String) -> CGFloat = { key in
            CGFloat(Double(element.attributes[key] ?? "0") ?? 0)
        }
        let frame = CGRect(
            x: number("x"), y: number("y"), width: number("width"), height: number("height")
        )
        guard frame.width > 0, frame.height > 0 else { return nil }
        let radius = number("rx")
        let path = radius > 0
            ? Path(roundedRect: frame, cornerRadius: radius)
            : Path(frame)
        return VectorShape(
            id: element.attributes["id"],
            path: path.applying(transform(element.attributes["transform"])),
            fill: paint(element.attributes["fill"] ?? "#000000"),
            stroke: paint(element.attributes["stroke"]),
            strokeWidth: CGFloat(Double(element.attributes["stroke-width"] ?? "1") ?? 1),
            strokeCap: .butt,
            opacity: Double(element.attributes["opacity"] ?? "1") ?? 1,
            evenOdd: false
        )
    }

    private static func paint(_ value: String?) -> VectorPaint? {
        guard let value, value != "none" else { return nil }
        if let id = reference(value) { return .gradient(id) }
        return parseColor(value).map(VectorPaint.color)
    }

    private static func reference(_ value: String?) -> String? {
        guard let value, value.hasPrefix("url(#"), value.hasSuffix(")") else { return nil }
        return String(value.dropFirst(5).dropLast())
    }

    private static func parseColor(_ value: String) -> Color? {
        var text = value.trimmingCharacters(in: .whitespaces)
        guard text.hasPrefix("#") else { return nil }
        text.removeFirst()
        if text.count == 3 {
            text = text.map { "\($0)\($0)" }.joined()
        }
        guard text.count == 6, let hex = UInt32(text, radix: 16) else { return nil }
        return Color(hex: hex)
    }

    /// `translate(x y)`, `scale(s)` and `rotate(deg)`, composed left to right.
    static func transform(_ value: String?) -> CGAffineTransform {
        guard let value else { return .identity }
        var result = CGAffineTransform.identity
        let pattern = #"(translate|scale|rotate|matrix)\s*\(([^)]*)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return result }
        let range = NSRange(value.startIndex..., in: value)

        for match in regex.matches(in: value, range: range) {
            guard let nameRange = Range(match.range(at: 1), in: value),
                  let argsRange = Range(match.range(at: 2), in: value)
            else { continue }
            let name = String(value[nameRange])
            let numbers = value[argsRange]
                .split(whereSeparator: { $0 == " " || $0 == "," })
                .compactMap { Double($0) }
                .map { CGFloat($0) }

            switch name {
            case "translate":
                result = result.translatedBy(
                    x: numbers.first ?? 0, y: numbers.count > 1 ? numbers[1] : 0
                )
            case "scale":
                let sx = numbers.first ?? 1
                result = result.scaledBy(x: sx, y: numbers.count > 1 ? numbers[1] : sx)
            case "rotate":
                result = result.rotated(by: (numbers.first ?? 0) * .pi / 180)
            case "matrix" where numbers.count == 6:
                result = result.concatenating(CGAffineTransform(
                    a: numbers[0], b: numbers[1], c: numbers[2],
                    d: numbers[3], tx: numbers[4], ty: numbers[5]
                ))
            default:
                break
            }
        }
        return result
    }
}

// MARK: - A minimal XML reader

struct XMLElement {
    var name: String
    var attributes: [String: String]
    var children: [XMLElement]

    var descendants: [XMLElement] {
        children + children.flatMap(\.descendants)
    }
}

private enum XMLReader {
    static func elements(in text: String) -> [XMLElement] {
        let delegate = Delegate()
        let parser = XMLParser(data: Data(text.utf8))
        parser.delegate = delegate
        parser.parse()
        return delegate.roots
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var roots: [XMLElement] = []
        private var stack: [XMLElement] = []

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName: String?,
            attributes: [String: String] = [:]
        ) {
            stack.append(XMLElement(name: elementName, attributes: attributes, children: []))
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName: String?
        ) {
            guard let finished = stack.popLast() else { return }
            if stack.isEmpty { roots.append(finished) }
            else { stack[stack.count - 1].children.append(finished) }
        }
    }
}

// MARK: - Drawing

extension GraphicsContext {
    /// Draws one parsed group, resolving gradients and clips as it goes.
    func draw(_ group: VectorGroup, in artwork: VectorArtwork, skipping skipped: Set<String> = []) {
        if let id = group.id, skipped.contains(id) { return }
        var layer = self
        layer.opacity *= group.opacity
        layer.concatenate(group.transform)
        if let clipPathId = group.clipPathId, let clip = artwork.clipPaths[clipPathId] {
            layer.clip(to: clip)
        }
        for child in group.children {
            switch child {
            case .group(let nested):
                layer.draw(nested, in: artwork, skipping: skipped)
            case .shape(let shape):
                layer.draw(shape, in: artwork)
            }
        }
    }

    func draw(_ shape: VectorShape, in artwork: VectorArtwork) {
        var layer = self
        layer.opacity *= shape.opacity

        if let fill = shape.fill {
            layer.fill(
                shape.path,
                with: style(for: fill, in: artwork),
                style: FillStyle(eoFill: shape.evenOdd)
            )
        }
        if let stroke = shape.stroke {
            layer.stroke(
                shape.path,
                with: style(for: stroke, in: artwork),
                style: StrokeStyle(lineWidth: shape.strokeWidth, lineCap: shape.strokeCap)
            )
        }
    }

    private func style(for paint: VectorPaint, in artwork: VectorArtwork) -> GraphicsContext.Shading {
        switch paint {
        case .color(let color):
            return .color(color)
        case .gradient(let id):
            guard let gradient = artwork.gradients[id] else { return .color(.clear) }
            let stops = Gradient(stops: gradient.stops)
            switch gradient.kind {
            case .linear:
                return .linearGradient(stops, startPoint: gradient.start, endPoint: gradient.end)
            case .radial:
                return .radialGradient(
                    stops,
                    center: gradient.center,
                    startRadius: 0,
                    endRadius: gradient.radius
                )
            }
        }
    }
}

/// Draws a parsed artwork, scaled to fit, optionally leaving named groups out so
/// a caller can animate them itself.
struct VectorArtworkView: View {
    var artwork: VectorArtwork
    var skipping: Set<String> = []

    var body: some View {
        Canvas { context, size in
            let scale = Swift.min(
                size.width / artwork.viewBox.width,
                size.height / artwork.viewBox.height
            )
            var layer = context
            layer.translateBy(
                x: (size.width - artwork.viewBox.width * scale) / 2,
                y: (size.height - artwork.viewBox.height * scale) / 2
            )
            layer.scaleBy(x: scale, y: scale)
            layer.translateBy(x: -artwork.viewBox.minX, y: -artwork.viewBox.minY)
            layer.draw(artwork.root, in: artwork, skipping: skipping)
        }
    }
}
