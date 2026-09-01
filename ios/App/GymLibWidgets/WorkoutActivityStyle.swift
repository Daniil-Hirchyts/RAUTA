import SwiftUI
import UIKit

extension Color {
    init(_ color: WorkoutActivityColor) {
        self.init(red: color.red, green: color.green, blue: color.blue)
    }
}

/// Loads a PNG the app prepared in the shared container. Everything the card
/// draws comes through here: the widget extension has no access to the web
/// bundle and cannot run the app's CSS filters, so the app renders both the
/// demonstration frame and the muscle map ahead of time.
@available(iOS 16.1, *)
func sharedFrameImage(named name: String) -> Image? {
    guard
        let url = WorkoutActivityStore.frameURL(named: name),
        let image = UIImage(contentsOfFile: url.path)
    else { return nil }

    return Image(uiImage: image)
}

/// The demonstration panel: the largest thing on the card, because it is the
/// one part that answers "what am I supposed to be doing" without reading.
///
/// The movement is decomposed into stills and the card steps to the next one
/// on every update, which is as close to playing it as the platform gets:
/// WidgetKit renders a Live Activity as a static view and redraws it only when
/// the content state changes, so there is no clock here to animate against and
/// no way to hand it an animated image.
///
/// The frame is composited onto ``WorkoutActivityPalette.surface`` when it is
/// prepared, so it must be drawn on that exact color to look seamless. Nothing
/// stands in when there is no frame: an empty tile reads as "no picture for
/// this exercise", where a placeholder icon reads as a broken one.
@available(iOS 16.1, *)
struct ExerciseFrame: View {
    var name: String
    var side: CGFloat

    var body: some View {
        Group {
            if let image = sharedFrameImage(named: name) {
                image.resizable().scaledToFit()
            } else {
                Color.clear
            }
        }
        .frame(width: side, height: side)
        .background(Color(WorkoutActivityPalette.surface))
        .clipShape(RoundedRectangle(cornerRadius: side * 0.2, style: .continuous))
    }
}

/// The body with the exercise's muscles lit, standing in for the list of
/// muscle names the card used to spell out. One figure, facing whichever way
/// the exercise is about (see `preferredSide` in `src/lib/muscle-map-image.ts`)
/// — two shrunk to fit beside the timer read as a smudge rather than a
/// diagram. The art carries its own transparency and sits directly on the
/// card, with no tile behind it.
@available(iOS 16.1, *)
struct MuscleMapFrame: View {
    var name: String
    var width: CGFloat
    var height: CGFloat

    var body: some View {
        Group {
            if let image = sharedFrameImage(named: name) {
                image.resizable().scaledToFit()
            } else {
                Color.clear
            }
        }
        .frame(width: width, height: height)
    }
}

/// What a workout looks like when there is room for one shape and nothing
/// else. Deliberately not a runner — this is a weights app, and the Island's
/// smallest presentation is the only thing some glances ever see.
@available(iOS 16.1, *)
struct WorkoutGlyph: View {
    var isPaused: Bool

    var body: some View {
        if isPaused {
            Image(systemName: "pause.fill")
        } else if #available(iOS 18.0, *) {
            Image(systemName: "dumbbell.fill")
        } else {
            // `dumbbell.fill` only arrived in iOS 18; below that a flame is
            // the closest symbol that is not a person.
            Image(systemName: "flame.fill")
        }
    }
}

/// The workout clock. A running session hands WidgetKit the instant to count
/// from and never touches it again; a paused one shows the frozen reading.
@available(iOS 16.1, *)
struct WorkoutTimerText: View {
    var state: WorkoutActivityAttributes.ContentState

    var body: some View {
        Group {
            if let start = state.timerStart, !state.isPaused {
                Text(start, style: .timer)
            } else {
                Text(state.elapsedText)
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.55)
    }
}

/// One dot per exercise, filled as each is completed and outlined while it is
/// the one being performed. Long workouts fall back to the count alone rather
/// than a row of dots too small to read.
@available(iOS 16.1, *)
struct ProgressDots: View {
    var state: WorkoutActivityAttributes.ContentState

    private static let maximumDots = 10

    var body: some View {
        if state.totalCount > 0, state.totalCount <= Self.maximumDots {
            HStack(spacing: 4) {
                ForEach(0..<state.totalCount, id: \.self) { index in
                    Capsule()
                        .fill(
                            index < state.completedCount
                                ? Color(WorkoutActivityPalette.accent)
                                : Color(WorkoutActivityPalette.accent).opacity(0.22)
                        )
                        .frame(width: index == state.completedCount ? 14 : 7, height: 5)
                }
            }
        }
    }
}
