import SwiftUI

struct CoverflowSlide<ID: Hashable>: Identifiable {
    let id: ID
    let title: String
    let description: String?

    init(id: ID, title: String, description: String? = nil) {
        self.id = id
        self.title = title
        self.description = description
    }
}

/// A single visual language for picture-led choices. The centred card is the
/// answer; neighbouring cards fold away while remaining visible enough to
/// communicate that the deck continues in either direction.
struct CoverflowCarousel<ID: Hashable, Media: View>: View {
    let label: String
    let slides: [CoverflowSlide<ID>]
    let value: ID
    var minimumCardWidth: CGFloat = 190
    var maximumCardWidth: CGFloat = 264
    var widthFraction: CGFloat = 0.58
    var cardHeightRatio: CGFloat = 1.22
    var loop = true
    var focusedScale: CGFloat = 1.08
    var depth: CGFloat = 0.20
    var fade: CGFloat = 0.10
    var falloff: CGFloat = 0.56
    var gap: CGFloat = 0.05
    var rotate: CGFloat = 44
    var perspective: CGFloat = 3
    let onChange: (ID) -> Void
    @ViewBuilder let media: (CoverflowSlide<ID>) -> Media

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// How far the deck is being dragged, in points. Returns to zero on the
    /// same spring that settles the chosen card, so a release never jumps.
    @State private var translation: CGFloat = 0

    private var selectedIndex: Int {
        slides.firstIndex { $0.id == value } ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                let cardWidth = min(
                    maximumCardWidth,
                    max(minimumCardWidth, proxy.size.width * widthFraction)
                )
                let pitch = cardWidth * (1 + gap)
                let cardHeight = cardWidth * cardHeightRatio

                ZStack {
                    ForEach(slides.indices, id: \.self) { index in
                        let distance = offset(for: index) + translation / pitch
                        let ramp = pow(abs(distance), falloff)
                        let recession = 1 / (1 + depth * ramp)
                        let focus = 1 + (focusedScale - 1) * max(0, 1 - abs(distance))

                        card(
                            slides[index],
                            selected: index == selectedIndex,
                            width: cardWidth,
                            height: cardHeight
                        )
                            .rotation3DEffect(
                                .degrees(-min(82, rotate * ramp) * (distance < 0 ? -1 : 1)),
                                axis: (x: 0, y: 1, z: 0),
                                perspective: 1 / perspective
                            )
                            .scaleEffect(recession * focus)
                            .offset(x: distance * pitch * recession)
                            .opacity(opacity(for: distance))
                            .zIndex(100 - abs(distance))
                    }
                }
                .frame(width: proxy.size.width, height: cardHeight + 72)
                .contentShape(Rectangle())
                // Sideways only, so the page it sits on still scrolls.
                .gesture(
                    HorizontalPan(
                        onChanged: { value in translation = value.translation },
                        onEnded: { value in release(value, pitch: pitch) },
                        onCancelled: { settle() }
                    )
                )
            }
            .frame(height: deckHeight)

            if !slides.isEmpty, let description = slides[selectedIndex].description {
                Text(description)
                    .font(Theme.sans(19, weight: .semibold))
                    .foregroundStyle(Theme.foreground.opacity(0.86))
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .frame(maxWidth: 360, minHeight: 50)
                    .padding(.horizontal, 24)
                    .id(slides[selectedIndex].id)
                    .transition(.opacity)
            }
        }
        .clipped()
        .animation(reduceMotion ? nil : Theme.Motion.smoothOut(0.28), value: value)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
        .accessibilityAdjustableAction { direction in
            choose(index: selectedIndex + (direction == .increment ? 1 : -1))
        }
    }

    /// Projects the throw the way a scroll view decelerates, then lands on
    /// the nearest card, at most two away.
    private func release(_ value: HorizontalPan.Value, pitch: CGFloat) {
        guard !slides.isEmpty, pitch > 0 else { return settle() }
        let decelerationRate = UIScrollView.DecelerationRate.normal.rawValue
        let projected = value.translation
            + value.velocity * decelerationRate / (1 - decelerationRate) / 1000
        let throwBy = Int((-projected / pitch).rounded())
        withAnimation(releaseAnimation) {
            translation = 0
            choose(index: selectedIndex + max(-2, min(2, throwBy)))
        }
    }

    private func settle() {
        withAnimation(releaseAnimation) { translation = 0 }
    }

    /// A critically damped spring: it carries the finger's motion into the
    /// landing and can be caught again mid-flight.
    private var releaseAnimation: Animation? {
        reduceMotion ? nil : .spring(duration: 0.35, bounce: 0)
    }

    private var deckHeight: CGFloat {
        let screenWidth = DeviceScreen.width
        let width = min(maximumCardWidth, max(minimumCardWidth, screenWidth * widthFraction))
        return width * cardHeightRatio + 72
    }

    private func card(
        _ slide: CoverflowSlide<ID>,
        selected: Bool,
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        Button {
            choose(id: slide.id)
        } label: {
            ZStack(alignment: .bottom) {
                Theme.card
                media(slide)

                LinearGradient(
                    colors: [.clear, .black.opacity(selected ? 0.84 : 0.76)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                Text(slide.title)
                    .font(Theme.sans(15, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
            }
            .frame(width: width, height: height)
            .overlay(alignment: .topTrailing) {
                ProfileCheck(checked: selected)
                    .padding(12)
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(selected ? Theme.primary.opacity(0.72) : .clear, lineWidth: 1)
            )
            .shadow(
                color: .black.opacity(selected ? 0.46 : 0.28),
                radius: selected ? 18 : 11,
                y: selected ? 11 : 7
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(slide.title)
        .accessibilityValue(selected ? "Selected" : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func offset(for index: Int) -> CGFloat {
        var value = CGFloat(index - selectedIndex)
        guard loop, slides.count > 2 else { return value }
        let half = CGFloat(slides.count) / 2
        if value > half { value -= CGFloat(slides.count) }
        if value < -half { value += CGFloat(slides.count) }
        return value
    }

    private func opacity(for distance: CGFloat) -> Double {
        let edge: CGFloat
        if loop, slides.count > 2 {
            edge = min(1, max(0, CGFloat(slides.count) / 2 - abs(distance)))
        } else {
            edge = 1
        }
        return Double(max(0, 1 - fade * abs(distance)) * edge)
    }

    private func choose(id: ID) {
        guard let index = slides.firstIndex(where: { $0.id == id }) else { return }
        choose(index: index)
    }

    private func choose(index: Int) {
        guard !slides.isEmpty else { return }
        let resolved: Int
        if loop, slides.count > 2 {
            resolved = (index % slides.count + slides.count) % slides.count
        } else {
            resolved = max(0, min(slides.count - 1, index))
        }
        guard slides[resolved].id != value else { return }
        Haptics.trigger(.selection)
        onChange(slides[resolved].id)
    }
}
