import SwiftUI
import UIKit

/// The frame owns the rounded app surface and its command row. Content remains
/// visually stable while compact controls can use Liquid Glass above it.
struct AppShell<Content: View, Controls: View>: View {
    var commandsVisible: Bool
    var fullScreen = false
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
                    .padding(.horizontal, fullScreen ? 0 : Theme.Metrics.surfaceGutter)
                    .padding(.top, fullScreen ? 0 : Theme.Metrics.surfaceGutter)
                    .padding(
                        .bottom,
                        (fullScreen ? 0 : Theme.Metrics.surfaceGutter)
                            + (commandsVisible ? controlsSpace : 0)
                    )
                    .animation(Theme.Motion.smoothOut(0.32), value: commandsVisible)

                if commandsVisible {
                    controls()
                        // A command may morph from the compact CTA into a taller
                        // chooser. Keep both anchored to the same bottom edge so
                        // the expanded surface grows into the page, never below
                        // the device safe area.
                        .frame(height: Theme.Metrics.controlsHeight, alignment: .bottom)
                        .padding(.horizontal, Theme.Metrics.controlsInset)
                        .padding(.bottom, controlsGap)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private func surface() -> some View {
        let base = content()
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(surfaceBackground)

        if fullScreen {
            base
                .overlay(AppGrain())
        } else {
            base
                .clipShape(surfaceShape)
                .overlay(
                    surfaceShape
                        .strokeBorder(Theme.border, lineWidth: 1)
                )
                .overlay(AppGrain())
        }
    }

    private var surfaceShape: UnevenRoundedRectangle {
        let bottomRadius = commandsVisible
            ? Theme.Metrics.cardRadius
            : Theme.Metrics.surfaceRadius

        return UnevenRoundedRectangle(
            cornerRadii: RectangleCornerRadii(
                topLeading: Theme.Metrics.surfaceRadius,
                bottomLeading: bottomRadius,
                bottomTrailing: bottomRadius,
                topTrailing: Theme.Metrics.surfaceRadius
            ),
            style: .continuous
        )
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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let image = MediaLibrary.grainImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                // Overlay grain darkens a light ground far more than it lightens
                // a dark one, so paper carries less of it.
                .opacity(colorScheme == .dark ? 0.22 : 0.10)
                .blendMode(.overlay)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Titled page

/// Every page with a title is laid out by this one view, so the four things a
/// title brings are the same on all of them:
///
/// - the title bar itself, an ``AppShellHeader`` floating over the page;
/// - where the page starts: its first row sits a fixed gap under the bar,
///   however many rows this page's bar carries;
/// - the progressive blur that dissolves content scrolling up behind the bar;
/// - getting out of the way: scrolling down the page's ``View/pageScroll()``
///   scroller slides the bar away, scrolling back brings it in.
struct AppTitledPage<Header: View, Content: View>: View {
    @Environment(\.appSafeAreaInsets) private var safeAreaInsets
    /// From the bottom of the bar to the page's first row.
    var contentGap: CGFloat = Theme.Metrics.headerContentGap
    @ViewBuilder var header: () -> Header
    @ViewBuilder var content: () -> Content

    @StateObject private var scroll = ScrollHideTracker()
    @State private var measuredHeaderHeight: CGFloat?

    /// A bar with nothing under its title row, for the frames before this
    /// page's own bar has been measured.
    private var standardHeaderHeight: CGFloat {
        safeAreaInsets.top + Theme.Metrics.headerHeight
    }

    private var headerHeight: CGFloat {
        measuredHeaderHeight ?? standardHeaderHeight
    }

    private var contentTop: CGFloat {
        headerHeight + contentGap
    }

    /// Once the bar has gone, a tall one leaves no more blur behind than a
    /// plain title would.
    private var scrimHeight: CGFloat {
        (scroll.hidden ? standardHeaderHeight : headerHeight) + Theme.Metrics.headerScrimOverhang
    }

    var body: some View {
        ZStack(alignment: .top) {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // The margin sits inside the scroller, so content starts clear
                // of the bar at rest and still passes behind it on the way up.
                .contentMargins(.top, contentTop, for: .scrollContent)
                .environment(\.appPageContentTop, contentTop)
                .environment(\.appPageScrollTracker, scroll)

            AppTopScrim(height: scrimHeight)
                .animation(Theme.Motion.smoothOut(0.52), value: scroll.hidden)
                .zIndex(20)

            header()
                .environment(\.appPageHeaderHidden, scroll.hidden)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    measuredHeaderHeight = height
                }
                .zIndex(30)
        }
    }
}

extension View {
    /// Marks the scroller that moves a titled page.
    ///
    /// Put it on the page's main vertical `ScrollView`, never on a carousel
    /// inside it: scrolling this one down slides the page's title bar away and
    /// scrolling back brings it in. When the scroller leaves — a stage without
    /// one, an empty state — the bar comes back.
    func pageScroll() -> some View {
        modifier(PageScrollReporting())
    }

    /// Holds the content of a page that does not scroll where a scrolling page's
    /// first row would start, just under the title bar.
    func belowPageHeader() -> some View {
        modifier(BelowPageHeader())
    }
}

private struct PageScrollState: Equatable {
    var offset: CGFloat
    var isScrollable: Bool
}

private struct PageScrollReporting: ViewModifier {
    @Environment(\.appPageScrollTracker) private var tracker

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: PageScrollState.self) { geometry in
                let insets = geometry.contentInsets
                return PageScrollState(
                    offset: Swift.max(0, geometry.contentOffset.y + insets.top),
                    isScrollable: geometry.contentSize.height + insets.top + insets.bottom
                        > geometry.containerSize.height + 1
                )
            } action: { _, state in
                tracker?.update(offset: state.offset, isScrollable: state.isScrollable)
            }
            .onDisappear { tracker?.reset() }
    }
}

private struct BelowPageHeader: ViewModifier {
    @Environment(\.appPageContentTop) private var contentTop

    func body(content: Content) -> some View {
        content.padding(.top, contentTop)
    }
}

private struct AppPageContentTopKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

private struct AppPageHeaderHiddenKey: EnvironmentKey {
    static let defaultValue = false
}

private struct AppPageScrollTrackerKey: EnvironmentKey {
    static let defaultValue: ScrollHideTracker? = nil
}

extension EnvironmentValues {
    /// How far down a titled page its content starts.
    var appPageContentTop: CGFloat {
        get { self[AppPageContentTopKey.self] }
        set { self[AppPageContentTopKey.self] = newValue }
    }

    fileprivate var appPageHeaderHidden: Bool {
        get { self[AppPageHeaderHiddenKey.self] }
        set { self[AppPageHeaderHiddenKey.self] = newValue }
    }

    fileprivate var appPageScrollTracker: ScrollHideTracker? {
        get { self[AppPageScrollTrackerKey.self] }
        set { self[AppPageScrollTrackerKey.self] = newValue }
    }
}

/// The top edge fade belongs to the page, not to the title. It stays put when
/// the title slides away.
///
/// Seven blur bands rather than one blurred pane: a single large blur moves
/// every pixel by the same amount, so the boundary where it stops is a visible
/// seam. Stepping the radius down band by band means each band is only slightly
/// sharper than the one above it, and detail dissolves on the way up.
private struct AppTopScrim: View {
    var height: CGFloat

    var body: some View {
        AppGradientBlur(edge: .top, radiusScale: 1.05)
        .frame(height: height)
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
final class PureBackdropBlurView: UIVisualEffectView {
    var blurRadius: CGFloat = 0 {
        didSet { scheduleRetune() }
    }

    private var retuneScheduled = false

    override func didMoveToWindow() {
        super.didMoveToWindow()
        scheduleRetune()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scheduleRetune()
    }

    private func scheduleRetune() {
        guard !retuneScheduled else { return }
        retuneScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.retuneScheduled = false
            self.retuneBackdrop()
        }
    }

    private func retuneBackdrop() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        guard let backdrop = subviews.first(where: {
            String(describing: type(of: $0)).contains("Backdrop")
        }) ?? subviews.first else { return }

        backdrop.backgroundColor = .clear
        backdrop.layer.backgroundColor = UIColor.clear.cgColor

        guard let filters = backdrop.layer.filters else { return }
        var gaussianFilters: [Any] = []
        for filter in filters {
            let object = filter as AnyObject
            guard let name = object.value(forKey: "name") as? String,
                  name == "gaussianBlur"
            else { continue }
            object.setValue(blurRadius, forKey: "inputRadius")
            gaussianFilters.append(filter)
        }
        if !gaussianFilters.isEmpty {
            // Removing the material colour/saturation filters leaves only the
            // backdrop Gaussian blur, so the header no longer paints a dark
            // slab over the page.
            backdrop.layer.filters = gaussianFilters
        }
    }
}

struct ProgressiveBlur: UIViewRepresentable {
    var radius: CGFloat

    func makeUIView(context: Context) -> PureBackdropBlurView {
        let view = PureBackdropBlurView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        view.isUserInteractionEnabled = false
        view.blurRadius = radius
        return view
    }

    func updateUIView(_ uiView: PureBackdropBlurView, context: Context) {
        uiView.blurRadius = radius
    }
}

enum HeaderProgressState: Hashable {
    case completed, current, pending
}

/// The title bar of a titled page. It floats above the page's scroller and is
/// only ever placed by ``AppTitledPage``, which decides when it slides away; the
/// edge fade under it stays with the page.
struct AppShellHeader<Left: View, Right: View, Above: View, Below: View>: View {
    @Environment(\.appSafeAreaInsets) private var safeAreaInsets
    @Environment(\.appPageHeaderHidden) private var hidden

    enum TitleSize { case standard, medium, small, extraSmall }

    var title: String
    var subtitle: String?
    var subtitleProgress: [HeaderProgressState]? = nil
    var onTitleTap: (() -> Void)? = nil
    var titleMultiline: Bool = false
    var titleSize: TitleSize?
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
        .padding(.top, 12 + safeAreaInsets.top)
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
            return AnyShapeStyle(Theme.foreground.opacity(0.12))
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
        @ViewBuilder left: @escaping () -> Left,
        @ViewBuilder right: @escaping () -> Right
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            subtitleProgress: subtitleProgress,
            titleMultiline: titleMultiline,
            titleSize: titleSize,
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
