import CoreGraphics
import Foundation
import ImageIO
import UIKit

/// Prepares the demonstration image a Live Activity shows.
///
/// The source art is the same white-background WebP the web app animates, and
/// the app applies a CSS filter chain to it — see `EXERCISE_ANIMATION_FILTER`
/// in `src/lib/visuals.ts`. The widget extension cannot run CSS filters, and
/// WidgetKit's own rendering of blend modes is not something to rely on, so the
/// identical maths runs here once per exercise and the result is written to the
/// shared container as a finished PNG.
///
/// CSS shorthand filters operate on non-linear sRGB, which is exactly what a
/// bitmap context hands back, so the per-pixel pass below reproduces the
/// browser rather than approximating it with Core Image's linear working space.
enum ExerciseFrameRenderer {
    /// Large enough for the Lock Screen card's demonstration panel on a 3x
    /// screen, small enough that the pass is a few milliseconds.
    private static let side = 320

    /// How many stills the movement is decomposed into. Four is enough to read
    /// as a rep rather than a pose, and small enough that preparing an exercise
    /// stays a handful of milliseconds.
    static let frameCount = 4

    /// Prepared frames are worth keeping between sessions, but the library has
    /// over a thousand exercises, each now costs `frameCount` files, and the
    /// container is shared with the widget — and with the muscle maps, which
    /// are pruned by the same rule. Only the recently used ones stay.
    static let cacheLimit = 240

    /// The web filter chain, term for term.
    private static let hueRotation = 191.0
    private static let saturation = 1.75
    private static let contrast = 1.03

    /// Prepares the whole set of stills for `exerciseId` if it is not already
    /// on disk, and returns the file name for `frameIndex` — the one this
    /// update of the card should show. `nil` when there is nothing to show: an
    /// unknown id, or no reachable App Group.
    ///
    /// The set is written all at once. The card asks for a different index on
    /// every update, so preparing them one at a time would only spread the same
    /// work over the first four updates of an exercise while showing an empty
    /// panel in between.
    static func prepareFrame(exerciseId: String, frameIndex: Int) -> String? {
        guard !exerciseId.isEmpty else { return nil }

        let names = (0..<frameCount).map { frameName(exerciseId: exerciseId, index: $0) }
        let urls = names.compactMap { WorkoutActivityStore.frameURL(named: $0) }
        guard urls.count == names.count else { return nil }

        let manager = FileManager.default
        if urls.allSatisfy({ manager.fileExists(atPath: $0.path) }) {
            urls.forEach(touch)
            return names[wrapped(frameIndex, count: names.count)]
        }

        let images = bundledFrames(exerciseId: exerciseId)
        guard images.count == names.count else { return nil }

        for (url, image) in zip(urls, images) {
            guard let data = render(image) else { return nil }
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                return nil
            }
        }
        pruneCache()

        return names[wrapped(frameIndex, count: names.count)]
    }

    /// The version suffix retires frames prepared by an earlier build: the
    /// size and the sampled point of the movement are both baked into the PNG.
    private static func frameName(exerciseId: String, index: Int) -> String {
        "exercise-\(exerciseId)-\(index)-v3.png"
    }

    private static func wrapped(_ index: Int, count: Int) -> Int {
        count > 0 ? ((index % count) + count) % count : 0
    }

    /// Keeps the cache honest about which frames are still in use, so pruning
    /// drops the ones no workout has reached for in a long time.
    static func touch(_ url: URL) {
        try? FileManager.default.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: url.path
        )
    }

    static func pruneCache() {
        guard let directory = WorkoutActivityStore.framesDirectory else { return }

        let manager = FileManager.default
        guard
            let frames = try? manager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey]
            ),
            frames.count > cacheLimit
        else { return }

        let oldestFirst = frames.sorted { left, right in
            modified(left) < modified(right)
        }
        for url in oldestFirst.prefix(frames.count - cacheLimit) {
            try? manager.removeItem(at: url)
        }
    }

    private static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast
    }

    /// Where in the sequence the first still is taken from. Frame zero of the
    /// source animation is the rest position, which is the least recognisable
    /// moment of most exercises; starting a third of the way in means the
    /// still the card spends most of its time showing is one where the
    /// exercise is being *done*.
    private static let motionOffset = 1.0 / 3.0

    /// `frameCount` stills spanning one repetition, in the order the card
    /// steps through them. The animations ship inside the web bundle's
    /// `public` folder reference; `CGImageSource` reads the individual frames
    /// of an animated WebP, where `UIImage` would only ever decode the first.
    ///
    /// A still source — or one ImageIO will not take apart — yields the same
    /// image `frameCount` times, so the card simply does not appear to move.
    private static func bundledFrames(exerciseId: String) -> [UIImage] {
        guard
            let url = Bundle.main.url(
                forResource: exerciseId,
                withExtension: "webp",
                subdirectory: "public/assets/exercises/webp"
            )
        else { return [] }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return still(at: url)
        }

        let count = CGImageSourceGetCount(source)
        guard count > 1 else { return still(at: url) }

        let frames = (0..<frameCount).compactMap { step -> UIImage? in
            let position = motionOffset + Double(step) / Double(frameCount)
            let index = Int(Double(count) * position.truncatingRemainder(dividingBy: 1))
            return CGImageSourceCreateImageAtIndex(source, min(index, count - 1), nil)
                .map(UIImage.init(cgImage:))
        }

        return frames.count == frameCount ? frames : still(at: url)
    }

    private static func still(at url: URL) -> [UIImage] {
        guard let image = UIImage(contentsOfFile: url.path) else { return [] }
        return Array(repeating: image, count: frameCount)
    }

    private static func render(_ image: UIImage) -> Data? {
        guard
            let cgImage = image.cgImage,
            let context = CGContext(
                data: nil,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
        else { return nil }

        // The art is drawn on white, and `invert` is what turns that white into
        // the black the screen blend erases. Padding the square with white too
        // keeps the letterboxed edges from becoming grey bars.
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        context.interpolationQuality = .high
        context.draw(cgImage, in: aspectFitRect(for: cgImage))

        guard let pixels = context.data else { return nil }
        applyFilterChain(to: pixels.bindMemory(to: UInt8.self, capacity: side * side * 4))

        guard let output = context.makeImage() else { return nil }
        return UIImage(cgImage: output).pngData()
    }

    private static func aspectFitRect(for image: CGImage) -> CGRect {
        let bounds = CGFloat(side)
        let scale = min(bounds / CGFloat(image.width), bounds / CGFloat(image.height))
        let width = CGFloat(image.width) * scale
        let height = CGFloat(image.height) * scale

        return CGRect(
            x: (bounds - width) / 2,
            y: (bounds - height) / 2,
            width: width,
            height: height
        )
    }

    private static func applyFilterChain(to pixels: UnsafeMutablePointer<UInt8>) {
        let ground = WorkoutActivityPalette.surface

        for index in stride(from: 0, to: side * side * 4, by: 4) {
            var color = Color(
                red: Double(pixels[index]) / 255,
                green: Double(pixels[index + 1]) / 255,
                blue: Double(pixels[index + 2]) / 255
            )

            // Every step clamps, exactly as each filter primitive in the CSS
            // pipeline does. Without it `contrast` pushes black slightly below
            // zero, the screen blend lifts it, and the tile ends up a visibly
            // darker box than the surface it sits on.
            color = clamped(inverted(color))
            color = clamped(hueRotated(color, degrees: hueRotation))
            color = clamped(saturated(color, amount: saturation))
            color = clamped(contrasted(color, amount: contrast))
            // Stands in for the web layer's `mix-blend-screen` over the card
            // surface: the inverted white ground is black, and screening black
            // over the tile leaves the tile untouched.
            color = screened(color, over: ground)

            pixels[index] = channel(color.red)
            pixels[index + 1] = channel(color.green)
            pixels[index + 2] = channel(color.blue)
        }
    }

    private static func channel(_ value: Double) -> UInt8 {
        // Rounded, not truncated, so a channel that lands exactly on the tile
        // colour renders as the same byte SwiftUI paints behind it.
        UInt8((max(0, min(1, value)) * 255).rounded())
    }

    private static func clamped(_ color: Color) -> Color {
        Color(
            red: max(0, min(1, color.red)),
            green: max(0, min(1, color.green)),
            blue: max(0, min(1, color.blue))
        )
    }

    // MARK: - The CSS filter functions

    private struct Color {
        var red: Double
        var green: Double
        var blue: Double
    }

    private static func inverted(_ color: Color) -> Color {
        Color(red: 1 - color.red, green: 1 - color.green, blue: 1 - color.blue)
    }

    /// The hue-rotation matrix from the Filter Effects specification.
    private static func hueRotated(_ color: Color, degrees: Double) -> Color {
        let radians = degrees * .pi / 180
        let cosine = cos(radians)
        let sine = sin(radians)

        return Color(
            red: (0.213 + cosine * 0.787 - sine * 0.213) * color.red
                + (0.715 - cosine * 0.715 - sine * 0.715) * color.green
                + (0.072 - cosine * 0.072 + sine * 0.928) * color.blue,
            green: (0.213 - cosine * 0.213 + sine * 0.143) * color.red
                + (0.715 + cosine * 0.285 + sine * 0.140) * color.green
                + (0.072 - cosine * 0.072 - sine * 0.283) * color.blue,
            blue: (0.213 - cosine * 0.213 - sine * 0.787) * color.red
                + (0.715 - cosine * 0.715 + sine * 0.715) * color.green
                + (0.072 + cosine * 0.928 + sine * 0.072) * color.blue
        )
    }

    private static func saturated(_ color: Color, amount: Double) -> Color {
        Color(
            red: (0.213 + 0.787 * amount) * color.red
                + (0.715 - 0.715 * amount) * color.green
                + (0.072 - 0.072 * amount) * color.blue,
            green: (0.213 - 0.213 * amount) * color.red
                + (0.715 + 0.285 * amount) * color.green
                + (0.072 - 0.072 * amount) * color.blue,
            blue: (0.213 - 0.213 * amount) * color.red
                + (0.715 - 0.715 * amount) * color.green
                + (0.072 + 0.928 * amount) * color.blue
        )
    }

    private static func contrasted(_ color: Color, amount: Double) -> Color {
        let offset = 0.5 - 0.5 * amount
        return Color(
            red: color.red * amount + offset,
            green: color.green * amount + offset,
            blue: color.blue * amount + offset
        )
    }

    private static func screened(_ color: Color, over ground: WorkoutActivityColor) -> Color {
        Color(
            red: 1 - (1 - color.red) * (1 - ground.red),
            green: 1 - (1 - color.green) * (1 - ground.green),
            blue: 1 - (1 - color.blue) * (1 - ground.blue)
        )
    }
}


/// The muscle map the Lock Screen card shows instead of a list of muscle
/// names. Unlike the demonstration frame there is nothing to compute here: the
/// web layer rasterizes the same figures the app draws on screen and hands the
/// bytes over, so this only has to put them somewhere the widget can read.
enum MuscleMapStore {
    /// Writes the map for `key` if it is not already in the shared container
    /// and returns the file name to put in the activity's content state. The
    /// PNG may be empty — the web layer sends it only the first time a set of
    /// muscles comes up — which is fine as long as the file is already there.
    static func prepareMap(key: String, base64Png: String) -> String? {
        guard !key.isEmpty else { return nil }

        let name = "muscles-\(key).png"
        guard let url = WorkoutActivityStore.frameURL(named: name) else { return nil }
        if FileManager.default.fileExists(atPath: url.path) {
            ExerciseFrameRenderer.touch(url)
            return name
        }

        guard
            !base64Png.isEmpty,
            let data = Data(base64Encoded: base64Png)
        else { return nil }

        do {
            try data.write(to: url, options: .atomic)
            ExerciseFrameRenderer.pruneCache()
            return name
        } catch {
            return nil
        }
    }
}
