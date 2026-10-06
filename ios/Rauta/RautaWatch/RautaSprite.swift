import Foundation
import ImageIO
import SwiftUI

/// RAUTA on the wrist, moving: frames of the real rig — the same character the
/// phone animates with Rive, which has no watchOS runtime — rendered by
/// `scripts/rauta-frames/build.py`, one sprite sheet per mood loop.
///
/// The loop follows what the workout is doing, and a change of loop crossfades
/// rather than cuts. On Always On, and with Reduce Motion, it holds a still
/// frame: a moving character with the wrist down only costs power.
struct RautaSprite: View {
    enum Loop: String {
        case calm, determined, recovering, happy, proud
    }

    var loop: Loop

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var still: Bool { isLuminanceReduced || reduceMotion }

    var body: some View {
        ZStack {
            frames(loop)
                .id(loop)
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.35), value: loop)
        .accessibilityHidden(true)
    }

    private func frames(_ loop: Loop) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15, paused: still)) { context in
            if let sheet = RautaSpriteSheet.named(loop),
               let frame = sheet.frame(at: still ? 0 : context.date.timeIntervalSinceReferenceDate) {
                Image(decorative: frame, scale: 2, orientation: .up)
                    .resizable()
                    .scaledToFit()
            }
        }
    }
}

/// One loop's sheet, decoded once and cut into frames as they are needed. Only
/// the loops in use are kept: every sheet decoded at once would be more than a
/// watch should hold.
@MainActor
final class RautaSpriteSheet {
    private let image: CGImage
    private let cell: CGSize
    private let columns: Int
    private let count: Int
    private let framesPerSecond: Double
    private var frames: [Int: CGImage] = [:]

    /// The sheets decoded so far, newest last; two at most, for a crossfade.
    private static var cache: [(loop: RautaSprite.Loop, sheet: RautaSpriteSheet)] = []

    static func named(_ loop: RautaSprite.Loop) -> RautaSpriteSheet? {
        if let cached = cache.first(where: { $0.loop == loop }) { return cached.sheet }
        guard let sheet = load(loop) else { return nil }
        cache.append((loop, sheet))
        if cache.count > 2 { cache.removeFirst() }
        return sheet
    }

    private static func load(_ loop: RautaSprite.Loop) -> RautaSpriteSheet? {
        let name = "rauta-\(loop.rawValue)"
        guard let metadataURL = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: metadataURL),
              let metadata = try? JSONDecoder().decode(Metadata.self, from: data),
              let imageURL = Bundle.main.url(forResource: name, withExtension: "png"),
              let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(
                  source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
              )
        else { return nil }
        return RautaSpriteSheet(image: image, metadata: metadata)
    }

    private struct Metadata: Decodable {
        var cellW: Int
        var cellH: Int
        var cols: Int
        var count: Int
        var fps: Double
    }

    private init(image: CGImage, metadata: Metadata) {
        self.image = image
        cell = CGSize(width: metadata.cellW, height: metadata.cellH)
        columns = max(1, metadata.cols)
        count = max(1, metadata.count)
        framesPerSecond = metadata.fps
    }

    /// The frame showing at `time`, in seconds on any steady clock.
    func frame(at time: TimeInterval) -> CGImage? {
        let index = Int((time * framesPerSecond).rounded(.down)) % count
        if let cut = frames[index] { return cut }
        let (row, column) = index.quotientAndRemainder(dividingBy: columns)
        let rect = CGRect(
            x: CGFloat(column) * cell.width, y: CGFloat(row) * cell.height,
            width: cell.width, height: cell.height
        )
        // A crop shares the sheet's pixels, so cutting costs no memory.
        let cut = image.cropping(to: rect)
        frames[index] = cut
        return cut
    }
}
