import CoreImage
import Synchronization
import ImageIO
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The bundled artwork: equipment photographs, goal cards, the grain overlay and
/// the animated exercise demonstrations.
nonisolated enum MediaLibrary {
    private static let root = Bundle.main.bundleURL.appendingPathComponent("Media")

    static func equipmentURL(_ equipment: String) -> URL {
        root
            .appendingPathComponent("equipment")
            .appendingPathComponent("\(equipment.replacingOccurrences(of: " ", with: "-")).webp")
    }

    static func exerciseAnimationURL(_ exerciseId: String) -> URL {
        root
            .appendingPathComponent("exercises/webp")
            .appendingPathComponent("\(exerciseId).webp")
    }

    static func goalURL(_ goal: TrainingGoal) -> URL {
        root
            .appendingPathComponent("goals")
            .appendingPathComponent("\(goal.rawValue.replacingOccurrences(of: "_", with: "-")).png")
    }

    static let grainImage: UIImage? = {
        UIImage(contentsOfFile: root.appendingPathComponent("grain.png").path)
    }()

}

/// Which theme an exercise demonstration is prepared for.
nonisolated enum ExerciseMediaTone: String, Sendable {
    case light, dark

    init(_ scheme: ColorScheme) {
        self = scheme == .dark ? .dark : .light
    }
}

/// How a demonstration is drawn: for which theme, and how far its highlight is
/// turned from the brand orange to the accent in use.
nonisolated struct ExerciseMediaStyle: Hashable, Sendable {
    var tone: ExerciseMediaTone
    /// Whole degrees, so a colour dragged across the picker does not render a
    /// new set of frames for every fraction of a degree.
    var hueShift: Int

    init(tone: ExerciseMediaTone, hueShift: Double) {
        self.tone = tone
        self.hueShift = Int(hueShift.rounded())
    }
}

/// Decodes still and animated WebP through ImageIO, then applies the app's
/// treatment for the current theme.
///
/// The source animations carry a pre-baked alpha channel; recolouring the figure
/// is what makes them read as part of the app rather than as pasted-in clip art.
///
/// Decoding runs off the main actor (``loadPoster(for:style:)``,
/// ``loadAnimation(for:style:)``); only the cache lookups are cheap enough for
/// the main thread. The caches are `NSCache`, kept for its memory-pressure
/// eviction, and reached only under their locks.
nonisolated enum ExerciseMedia {
    private static let srgbSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private static let context = CIContext(options: [
        .useSoftwareRenderer: false,
        .workingColorSpace: srgbSpace,
    ])
    private static let posterCache = Mutex(makeCache(limit: 120))
    // Only what is on screen needs its frames; a grid scrolled past decodes
    // again rather than holding every loop it has shown.
    private static let animationCache = Mutex(makeCache(limit: 24))

    private static func makeCache(limit: Int) -> NSCache<NSString, UIImage> {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = limit
        return cache
    }

    /// Decodes the first frame away from the main actor. Nil when the bundle
    /// has no artwork, or when the view that asked has gone.
    @concurrent
    static func loadPoster(for exerciseId: String, style: ExerciseMediaStyle) async -> UIImage? {
        guard !Task.isCancelled else { return nil }
        return poster(for: exerciseId, style: style)
    }

    /// Decodes the whole demonstration away from the main actor, stopping
    /// between frames if the view that asked has gone.
    @concurrent
    static func loadAnimation(for exerciseId: String, style: ExerciseMediaStyle) async -> UIImage? {
        guard !Task.isCancelled else { return nil }
        return animation(for: exerciseId, style: style)
    }

    /// The treatment for the exercise animations.
    ///
    /// On a dark theme these invert and recolour the figure, and the rotation lands the
    /// source red on the app's primary orange. On a light theme the figure keeps
    /// its own greys, which already read on paper, and only its red is turned a
    /// little towards the orange. Either way the highlight is then turned on by
    /// the accent's distance from orange, so the muscles light up in the app's
    /// colour.
    private static func treated(_ input: CIImage, style: ExerciseMediaStyle) -> CIImage? {
        let shift = Double(style.hueShift)
        // The artwork arrives already cut out, so nothing here separates figure
        // from ground; this is only a recolouring.
        //
        // Core Image hands us premultiplied components, and two of the steps
        // below are not safe on those: inverting a half-covered edge pixel would
        // invert a value already scaled by its own coverage, and contrast pivots
        // around 0.5 rather than scaling. Both come back as a fringe along every
        // edge. Hue and saturation are linear and would survive either way.
        let straight = input.applyingFilter("CIUnpremultiply")

        if style.tone == .light {
            let warmed = straight
                .applyingFilter("CIHueAdjust", parameters: [
                    kCIInputAngleKey: (20.0 + shift) * .pi / 180.0,
                ])
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: 1.35,
                    kCIInputContrastKey: 1.04,
                    kCIInputBrightnessKey: 0.0,
                ])
            return warmed.applyingFilter("CIPremultiply")
        }

        guard let inverted = CIFilter(name: "CIColorInvert", parameters: [
            kCIInputImageKey: straight,
        ])?.outputImage else { return nil }

        // 188 degrees, expressed in radians, as the web filter chain asked for.
        let hue = inverted.applyingFilter("CIHueAdjust", parameters: [
            kCIInputAngleKey: (188.0 + shift) * .pi / 180.0,
        ])

        let controls = hue.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 2.2,
            kCIInputContrastKey: 1.05,
            kCIInputBrightnessKey: 0.0,
        ])

        // Back to premultiplied: the colour filters above all pass alpha through
        // untouched, so the asset's own coverage is still intact here.
        return controls.applyingFilter("CIPremultiply")
    }

    private static func render(_ image: CIImage, size: CGSize, style: ExerciseMediaStyle) -> UIImage? {
        guard let treatedImage = treated(image, style: style),
              let cgImage = context.createCGImage(
                  treatedImage,
                  from: CGRect(origin: .zero, size: size),
                  format: .RGBA8,
                  colorSpace: srgbSpace
              )
        else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// The demonstration for one exercise, decoded and treated. Nil when the
    /// bundle carries no artwork for it.
    static func animation(for exerciseId: String, style: ExerciseMediaStyle, maxFrames: Int = 40) -> UIImage? {
        let key = cacheKey(exerciseId, style)
        if let cached = cachedAnimation(for: exerciseId, style: style) { return cached }

        let url = MediaLibrary.exerciseAnimationURL(exerciseId)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }

        // A long animation is sampled rather than decoded whole: the figure
        // reads the same and the memory cost stays bounded.
        let stride = Swift.max(1, Int((Double(count) / Double(maxFrames)).rounded(.up)))
        var frames: [UIImage] = []
        var duration: TimeInterval = 0
        // UIImageView gives every item in animationImages the same duration.
        // WebP does not: most exercise clips hold their first and last pose,
        // then run the movement frames at roughly 10 fps. Repeating references
        // to a decoded frame preserves those source timings without duplicating
        // the image pixels in memory.
        let timingQuantum: TimeInterval = 0.1

        for index in Swift.stride(from: 0, to: count, by: stride) {
            // A card scrolled away mid-decode leaves the rest undone and
            // uncached; the next appearance starts again.
            if Task.isCancelled { return nil }
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil)
            else { continue }
            let size = CGSize(width: cgImage.width, height: cgImage.height)
            let ciImage = CIImage(cgImage: cgImage, options: [.colorSpace: srgbSpace])
            guard let rendered = render(ciImage, size: size, style: style) else { continue }
            let nextIndex = Swift.min(index + stride, count)
            let sourceDuration = (index..<nextIndex).reduce(0.0) { partial, frameIndex in
                partial + frameDelay(source, frameIndex)
            }
            let repeats = Swift.max(1, Int((sourceDuration / timingQuantum).rounded()))
            frames.append(contentsOf: repeatElement(rendered, count: repeats))
            if index == 0 {
                posterCache.withLock { cache in
                    if cache.object(forKey: key as NSString) == nil { cache.setObject(rendered, forKey: key as NSString) }
                }
            }
            duration += Double(repeats) * timingQuantum
        }
        guard !frames.isEmpty else { return nil }
        let animated = frames.count == 1
            ? frames[0]
            : (UIImage.animatedImage(with: frames, duration: Swift.max(duration, 0.1)) ?? frames[0])
        animationCache.withLock { $0.setObject(animated, forKey: key as NSString) }
        return animated
    }

    static func cachedAnimation(for exerciseId: String, style: ExerciseMediaStyle) -> UIImage? {
        let key = cacheKey(exerciseId, style)
        return animationCache.withLock { $0.object(forKey: key as NSString) }
    }

    /// Each theme and accent is cached on its own, so switching back and forth
    /// never re-decodes what has already been drawn once.
    /// A `String`, turned into the cache's `NSString` only inside its lock.
    private static func cacheKey(_ exerciseId: String, _ style: ExerciseMediaStyle) -> String {
        "\(exerciseId)|\(style.tone.rawValue)|\(style.hueShift)"
    }

    /// A single treated frame, cached — what a grid of hundreds of cards can
    /// afford to show.
    /// A poster already decoded, without decoding one: the only lookup that is
    /// safe on the main thread.
    static func cachedPoster(for exerciseId: String, style: ExerciseMediaStyle) -> UIImage? {
        let key = cacheKey(exerciseId, style)
        if let cached = posterCache.withLock({ $0.object(forKey: key as NSString) }) { return cached }
        if let firstFrame = cachedAnimation(for: exerciseId, style: style)?.images?.first {
            posterCache.withLock { $0.setObject(firstFrame, forKey: key as NSString) }
            return firstFrame
        }
        return nil
    }

    static func poster(for exerciseId: String, style: ExerciseMediaStyle) -> UIImage? {
        let key = cacheKey(exerciseId, style)
        if let cached = cachedPoster(for: exerciseId, style: style) { return cached }

        let url = MediaLibrary.exerciseAnimationURL(exerciseId)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }

        let size = CGSize(width: cgImage.width, height: cgImage.height)
        let ciImage = CIImage(cgImage: cgImage, options: [.colorSpace: srgbSpace])
        guard let rendered = render(ciImage, size: size, style: style) else { return nil }
        posterCache.withLock { $0.setObject(rendered, forKey: key as NSString) }
        return rendered
    }

    private static func frameDelay(_ source: CGImageSource, _ index: Int) -> TimeInterval {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
            as? [CFString: Any]
        else { return 0.1 }

        if let webp = properties[kCGImagePropertyWebPDictionary] as? [CFString: Any] {
            if let unclamped = webp[kCGImagePropertyWebPUnclampedDelayTime] as? Double,
               unclamped > 0 { return unclamped }
            if let delay = webp[kCGImagePropertyWebPDelayTime] as? Double, delay > 0 {
                return delay
            }
        }

        if let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
            if let unclamped = gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double,
               unclamped > 0 { return unclamped }
            if let delay = gif[kCGImagePropertyGIFDelayTime] as? Double, delay > 0 {
                return delay
            }
        }

        return 0.1
    }
}

/// A still image loaded straight off disk, cached by path.
enum StillImage {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 120
        return cache
    }()

    static func load(_ url: URL) -> UIImage? {
        let key = url.path as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}

/// The exercise demonstration, shown as a poster in lists and as the running
/// animation on a detail hero.
struct ExerciseMediaView: View {
    var exerciseId: String
    var animated: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var poster: UIImage?
    @State private var animatedImage: UIImage?

    /// Off, a demonstration rests on its first frame like every list poster.
    /// Reduce Motion is the setting that applies here, not video autoplay
    /// (`accessibilityPlayAnimatedImages` mirrors `isVideoAutoplayEnabled`,
    /// which governs App Store/TV previews, not these demonstrations, and
    /// reads false when the person has never touched it).
    private var plays: Bool { animated && !reduceMotion }

    var body: some View {
        ZStack {
            if plays, let animatedImage {
                AnimatedImageView(image: animatedImage)
            } else if let poster {
                Image(uiImage: poster)
                    .resizable()
                    .scaledToFit()
            } else {
                Color.clear
            }
        }
        .task(id: "\(exerciseId)-\(plays)-\(colorScheme)-\(Int(Theme.palette.hueShift.rounded()))") {
            await load()
        }
    }

    private func load() async {
        let id = exerciseId
        let wantsAnimation = plays
        let style = ExerciseMediaStyle(tone: ExerciseMediaTone(colorScheme), hueShift: Theme.palette.hueShift)

        // Decoding and recolouring a frame is real work: only a cache hit is taken
        // on the main thread, and a card scrolled away before its turn skips it.
        if let existing = ExerciseMedia.cachedPoster(for: id, style: style) {
            poster = existing
        } else {
            guard !Task.isCancelled else { return }
            let rendered = await ExerciseMedia.loadPoster(for: id, style: style)
            guard id == exerciseId else { return }
            poster = rendered
        }

        guard wantsAnimation else {
            animatedImage = nil
            return
        }

        if let existingAnim = ExerciseMedia.cachedAnimation(for: id, style: style) {
            animatedImage = existingAnim
        } else {
            guard !Task.isCancelled else { return }
            let decoded = await ExerciseMedia.loadAnimation(for: id, style: style)
            guard id == exerciseId, plays else { return }
            animatedImage = decoded
        }
    }
}

/// `UIImage.animatedImage` plays only inside a `UIImageView`, so the frames are
/// handed to one.
struct AnimatedImageView: UIViewRepresentable {
    var image: UIImage

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.clipsToBounds = true
        applyImage(image, to: view)
        return view
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {
        if uiView.image !== image {
            applyImage(image, to: uiView)
        }
    }

    private func applyImage(_ img: UIImage, to view: UIImageView) {
        view.image = img
        if let images = img.images, !images.isEmpty {
            view.animationImages = images
            view.animationDuration = img.duration
            view.animationRepeatCount = 0
            view.startAnimating()
        }
    }
}

/// Equipment artwork, on the warm card ground the grid draws it against.
struct EquipmentImageView: View {
    var equipment: String

    var body: some View {
        if let image = StillImage.load(MediaLibrary.equipmentURL(equipment)) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .padding(10)
                .saturation(1.25)
                // The art's orange details turn to the accent; its blacks and
                // greys have no hue to turn.
                .hueRotation(.degrees(Theme.palette.hueShift))
        } else {
            Image(systemName: "dumbbell")
                .font(.system(size: 28))
                .foregroundStyle(Theme.mutedForeground)
        }
    }
}

struct GoalImageView: View {
    var goal: TrainingGoal

    var body: some View {
        if let image = StillImage.load(MediaLibrary.goalURL(goal)) {
            Image(uiImage: image)
                .interpolation(.high)
                .resizable()
                .scaledToFit()
                .padding(4)
                .shadow(
                    color: Theme.obsidian.opacity(0.52),
                    radius: 14,
                    y: 10
                )
                .accessibilityHidden(true)
        } else {
            Color.clear
        }
    }
}
