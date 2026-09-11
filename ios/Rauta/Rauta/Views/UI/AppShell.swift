import SwiftUI
import UIKit

/// The frame owns the rounded app surface and its command row. Content remains
/// visually stable while compact controls can use Liquid Glass above it.
struct AppShell<Content: View, Controls: View>: View {
    var commandsVisible: Bool
    @ViewBuilder var content: () -> Content
    @ViewBuilder var controls: () -> Controls

    var body: some View {
        GeometryReader { proxy in
            let safeBottom = proxy.safeAreaInsets.bottom
            let controlsGap = Swift.max(safeBottom, Theme.Metrics.controlsInset)
            let controlsSpace = Theme.Metrics.controlsHeight + 16 + controlsGap
                - Theme.Metrics.surfaceGutter

            ZStack(alignment: .bottom) {
                Theme.shell.ignoresSafeArea()

                surface()
                    .padding(.horizontal, Theme.Metrics.surfaceGutter)
                    .padding(.top, Theme.Metrics.surfaceGutter)
                    .padding(
                        .bottom,
                        Theme.Metrics.surfaceGutter
                            + (commandsVisible ? controlsSpace : 0)
                    )
                    .animation(Theme.Motion.smoothOut(0.32), value: commandsVisible)

                if commandsVisible {
                    controls()
                        .frame(height: Theme.Metrics.controlsHeight)
                        .padding(.horizontal, Theme.Metrics.controlsInset)
                        .padding(.bottom, controlsGap)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
        }
    }

    private func surface() -> some View {
        content()
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(surfaceBackground)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: Theme.Metrics.surfaceRadius, style: .continuous
                )
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: Theme.Metrics.surfaceRadius, style: .continuous
                )
                .strokeBorder(Theme.border, lineWidth: 1)
            )
            .overlay(AppGrain())
    }

    private var surfaceBackground: some View {
        ZStack {
            Theme.background
            RadialGradient(
                colors: [Theme.oxblood.opacity(0.22), .clear],
                center: UnitPoint(x: -0.08, y: 0.18),
                startRadius: 0,
                endRadius: 420
            )
            RadialGradient(
                colors: [Theme.primary.opacity(0.10), .clear],
                center: UnitPoint(x: 0.78, y: 1.12),
                startRadius: 0,
                endRadius: 480
            )
        }
    }
}

/// One shell-sized raster keeps the texture organic without a repeating tile
/// boundary. The image lives beside the other bundled media.
struct AppGrain: View {
    var body: some View {
        if let image = MediaLibrary.grainImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .opacity(0.22)
                .blendMode(.overlay)
                .allowsHitTesting(false)
        }
    }
}

/// The top edge fade belongs to the page, not to the title. It stays put when
/// the title slides away.
///
/// Seven blur bands rather than one blurred pane: a single large blur moves
/// every pixel by the same amount, so the boundary where it stops is a visible
/// seam. Stepping the radius down band by band means each band is only slightly
/// sharper than the one above it, and detail dissolves on the way up.
struct AppTopScrim: View {
    var body: some View {
        ZStack(alignment: .top) {
            AppGradientBlur(edge: .top)

            // Match the web scrim: the page remains visible through the blur,
            // with only a warm background-colour fade at the very top. The
            // blur view itself is deliberately colourless below.
            LinearGradient(
                stops: [
                    .init(color: Theme.background.opacity(0.55), location: 0),
                    .init(color: Theme.background.opacity(0.25), location: 0.5),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(height: 72 + DeviceScreen.safeAreaInsets.top)
        .frame(maxWidth: .infinity, alignment: .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .ignoresSafeArea(edges: .top)
    }
}

/// The colourless, progressively fading backdrop blur shared by the fixed
/// edges of the app. Reversing the edge gives the bottom RAUTA treatment the
/// same dissolve as the shell header.
struct AppGradientBlur: View {
    var edge: VerticalEdge
    var radiusScale: CGFloat = 1
    private static let radii: [CGFloat] = [48, 32, 16, 8, 4, 2, 1]

    var body: some View {
        ZStack {
            ForEach(Array(Self.radii.enumerated()), id: \.offset) { index, radius in
                ProgressiveBlur(radius: radius * max(0, radiusScale))
                    .mask(bandMask(for: index))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Each band is fully opaque across the middle eighth of its own range and
    /// fades out over the eighth on either side, so no two steps ever meet at an
    /// edge.
    private func bandMask(for index: Int) -> some View {
        let step = 0.125
        let start = Double(index) * step
        return LinearGradient(
            stops: [
                .init(color: .clear, location: Swift.max(0, start - step)),
                .init(color: .black, location: start),
                .init(color: .black, location: start + step),
                .init(color: .clear, location: Swift.min(1, start + 2 * step)),
            ],
            startPoint: edge == .top ? .top : .bottom,
            endPoint: edge == .top ? .bottom : .top
        )
    }
}

/// A variable blur of the content behind, in the one radius a band asks for.
struct ProgressiveBlur: UIViewRepresentable {
    var radius: CGFloat

    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        view.isUserInteractionEnabled = false
        applyRadius(to: view)
        return view
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        applyRadius(to: uiView)
    }

    /// `UIBlurEffect` has no radius of its own, so the backdrop layer's own
    /// Gaussian filter is retuned instead. Failing to find it leaves the system
    /// blur, which is still the right kind of treatment.
    private func applyRadius(to view: UIVisualEffectView) {
        guard let backdrop = view.subviews.first else { return }
        view.backgroundColor = .clear
        view.contentView.backgroundColor = .clear
        backdrop.backgroundColor = .clear
        guard let filters = backdrop.layer.filters else { return }
        // UIBlurEffect material styles normally add colour/saturation filters
        // around the Gaussian backdrop. React's backdrop-filter is only a
        // Gaussian blur, so retain that filter alone and let AppTopScrim's
        // explicit gradient provide the opacity treatment.
        var gaussianFilters: [Any] = []
        for filter in filters {
            let object = filter as AnyObject
            if let name = object.value(forKey: "name") as? String,
               name == "gaussianBlur" {
                object.setValue(radius, forKey: "inputRadius")
                gaussianFilters.append(filter)
            }
        }
        if !gaussianFilters.isEmpty {
            backdrop.layer.filters = gaussianFilters
        }
    }
}

/// The title floats independently above the page scroller. Only its controls
/// animate away; the compact edge fade is owned by ``AppTopScrim``.
enum HeaderProgressState: Hashable {
    case completed, current, pending
}

struct AppShellHeader<Left: View, Right: View, Above: View, Below: View>: View {
    enum TitleSize { case standard, medium, small, extraSmall }

    var title: String
    var subtitle: String?
    var subtitleProgress: [HeaderProgressState]? = nil
    var onTitleTap: (() -> Void)? = nil
    var titleMultiline: Bool = false
    var titleSize: TitleSize?
    /// Driven by the page's own scroll offset; see ``ScrollHideTracker``.
    var hidden: Bool = false
    @ViewBuilder var left: () -> Left
    @ViewBuilder var right: () -> Right
    @ViewBuilder var above: () -> Above
    @ViewBuilder var below: () -> Below

    private var effectiveSize: TitleSize {
        if let titleSize { return titleSize }
        guard titleMultiline else { return .standard }
        if title.count > 50 { return .extraSmall }
        if title.count > 34 { return .small }
        if title.count > 22 { return .medium }
        return .standard
    }

    private var titleFont: Font {
        switch effectiveSize {
        case .standard: return Theme.sans(20, weight: .heavy)
        case .medium: return Theme.sans(18, weight: .heavy)
        case .small: return Theme.sans(17, weight: .heavy)
        case .extraSmall: return Theme.sans(16, weight: .heavy)
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                ZStack {
                    Group {
                        if let onTitleTap {
                            Button(action: onTitleTap) { titleLabel }
                                .buttonStyle(.plain)
                        } else {
                            titleLabel
                        }
                    }

                    above()
                        .offset(y: -24)

                    if let subtitle {
                        HStack(spacing: 8) {
                            Text(subtitle)
                                .lineLimit(1)
                            if let subtitleProgress, !subtitleProgress.isEmpty {
                                HStack(spacing: 4) {
                                    ForEach(Array(subtitleProgress.enumerated()), id: \.offset) { _, state in
                                        Capsule()
                                            .fill(progressFill(state))
                                            .frame(
                                                width: state == .current ? 16 : 10,
                                                height: 4
                                            )
                                    }
                                }
                                .frame(maxWidth: 96)
                                .accessibilityHidden(true)
                            }
                        }
                        .font(Theme.sans(12, weight: .semibold))
                        .foregroundStyle(Theme.mutedForeground)
                        .transition(.digitPop)
                        .id(subtitle + "-\(subtitleProgress?.count ?? 0)")
                        .offset(y: 24)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 56)

                HStack(spacing: 0) {
                    left()
                        .frame(width: 44, height: 44, alignment: .leading)
                    Spacer(minLength: 0)
                    right()
                        .frame(width: 44, height: 44, alignment: .trailing)
                }
            }
            .frame(minHeight: 44)
            below()
        }
        .padding(.horizontal, Theme.Metrics.contentInset)
        .padding(.top, 12 + DeviceScreen.safeAreaInsets.top)
        .padding(.bottom, 12)
        .opacity(hidden ? 0 : 1)
        .offset(y: hidden ? -80 : 0)
        .animation(Theme.Motion.smoothOut(0.52), value: hidden)
        .allowsHitTesting(!hidden)
    }

    private var titleLabel: some View {
        Text(title)
            .font(titleFont)
            .kerning(-0.5)
            .foregroundStyle(Theme.foreground)
            .lineLimit(titleMultiline ? 2 : 1)
            .multilineTextAlignment(.center)
            .truncationMode(.tail)
    }

    private func progressFill(_ state: HeaderProgressState) -> AnyShapeStyle {
        switch state {
        case .completed:
            return AnyShapeStyle(Theme.primaryGradient)
        case .current:
            return AnyShapeStyle(Theme.primary.opacity(0.55))
        case .pending:
            return AnyShapeStyle(Color.white.opacity(0.12))
        }
    }
}

extension AppShellHeader where Above == EmptyView, Below == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        subtitleProgress: [HeaderProgressState]? = nil,
        titleMultiline: Bool = false,
        titleSize: TitleSize? = nil,
        hidden: Bool = false,
        @ViewBuilder left: @escaping () -> Left,
        @ViewBuilder right: @escaping () -> Right
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            subtitleProgress: subtitleProgress,
            titleMultiline: titleMultiline,
            titleSize: titleSize,
            hidden: hidden,
            left: left,
            right: right,
            above: { EmptyView() },
            below: { EmptyView() }
        )
    }
}

/// How far the scroller has to travel in one direction before the title slides
/// away, and the shorter distance back that brings it in again.
private let hideTravel: CGFloat = 72
private let showTravel: CGFloat = 44

/// Accumulates scroll travel in one direction — the accumulator zeroes the
/// moment the finger reverses — so the title only moves once the scroll is
/// clearly a deliberate one.
@MainActor
final class ScrollHideTracker: ObservableObject {
    @Published private(set) var hidden = false
    private var lastOffset: CGFloat = 0
    private var travel: CGFloat = 0

    func update(offset: CGFloat, isScrollable: Bool) {
        if !isScrollable || offset <= 8 {
            travel = 0
            if hidden { hidden = false }
        } else {
            let delta = offset - lastOffset
            if delta != 0, (delta > 0) != (travel > 0) { travel = 0 }
            travel = Swift.max(-2 * showTravel, Swift.min(2 * hideTravel, travel + delta))
            if travel > hideTravel, !hidden { hidden = true }
            else if travel < -showTravel, hidden { hidden = false }
        }
        lastOffset = offset
    }

    func reset() {
        travel = 0
        lastOffset = 0
        hidden = false
    }
}

/// Reports a scroll view's content offset upward.
struct ScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

extension View {
    /// Marks the top of a scroll view's content so its offset can be read.
    func tracksScrollOffset(in space: String) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ScrollOffsetKey.self,
                    value: -proxy.frame(in: .named(space)).minY
                )
            }
        )
    }
}

/// Reads the enclosing SwiftUI `ScrollView` through its backing `UIScrollView`.
/// Geometry preferences are unreliable for zero-sized sentinels inside lazy
/// content on iOS 17; the backing scroll view gives us the same `scrollTop`
/// semantics the React shell uses.
struct ScrollOffsetObserver: UIViewRepresentable {
    var onChange: (CGFloat, Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        DispatchQueue.main.async { context.coordinator.attach(from: view) }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onChange = onChange
        DispatchQueue.main.async {
            context.coordinator.attach(from: uiView)
            context.coordinator.publish()
        }
    }

    final class Coordinator: NSObject {
        var onChange: (CGFloat, Bool) -> Void
        private weak var scrollView: UIScrollView?
        private var offsetObservation: NSKeyValueObservation?
        private var sizeObservation: NSKeyValueObservation?

        init(onChange: @escaping (CGFloat, Bool) -> Void) {
            self.onChange = onChange
        }

        deinit {
            offsetObservation?.invalidate()
            sizeObservation?.invalidate()
        }

        func attach(from view: UIView) {
            var ancestor = view.superview
            while let current = ancestor, !(current is UIScrollView) {
                ancestor = current.superview
            }
            guard let candidate = ancestor as? UIScrollView,
                  candidate !== scrollView else { return }

            offsetObservation?.invalidate()
            sizeObservation?.invalidate()
            scrollView = candidate
            offsetObservation = candidate.observe(\.contentOffset, options: [.initial, .new]) {
                [weak self] _, _ in self?.publish()
            }
            sizeObservation = candidate.observe(\.contentSize, options: [.new]) {
                [weak self] _, _ in self?.publish()
            }
            publish()
        }

        func publish() {
            guard let scrollView else { return }
            let offset = Swift.max(
                0,
                scrollView.contentOffset.y + scrollView.adjustedContentInset.top
            )
            let isScrollable = scrollView.contentSize.height > scrollView.bounds.height + 1
            onChange(offset, isScrollable)
        }
    }
}

extension AnyTransition {
    static func page(_ direction: NavigationDirection) -> AnyTransition {
        switch direction {
        case .forward:
            return .asymmetric(
                insertion: .opacity.combined(with: .offset(x: 16, y: 0)),
                removal: .opacity.combined(with: .offset(x: -8, y: 0))
            )
        case .back:
            return .asymmetric(
                insertion: .opacity.combined(with: .offset(x: -12, y: 0)),
                removal: .opacity.combined(with: .offset(x: 14, y: 0))
            )
        }
    }

    /// The arrival the subtitle and every animated readout share.
    static var digitPop: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 8)).combined(with: .scale(scale: 0.96)),
            removal: .opacity.combined(with: .offset(y: -8))
        )
    }
}
