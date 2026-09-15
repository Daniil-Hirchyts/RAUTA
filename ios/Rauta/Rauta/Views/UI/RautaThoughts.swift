import SwiftUI
import UIKit

// RAUTA's menus, as thought bubbles.
//
// A menu opened from RAUTA is a glass panel with a trail of two glass bubbles
// running back to the character, the way a cartoon thought rises from a head.
// It grows out of RAUTA — the smallest bubble first, the panel last — and folds
// back into it when it closes. Above RAUTA when the character sits low on the
// screen (the tab bar), below it when it sits high (a page's title bar).
//
// The bubble is drawn in a window of its own above the app, so it is never
// clipped by the view it came from and can sit over the tab bar or a modal.

extension View {
    /// Shows `menu` as a thought bubble rising from this view while
    /// `isPresented` is true. `onDismissed` runs once the bubble has folded
    /// away — the moment a picked action can open a page.
    func rautaThoughts<Menu: View>(
        isPresented: Binding<Bool>,
        onDismissed: (() -> Void)? = nil,
        @ViewBuilder menu: @escaping () -> Menu
    ) -> some View {
        modifier(RautaThoughtsAnchor(isPresented: isPresented, onDismissed: onDismissed, menu: menu))
    }
}

private struct RautaThoughtsAnchor<Menu: View>: ViewModifier {
    @Binding var isPresented: Bool
    var onDismissed: (() -> Void)?
    @ViewBuilder var menu: () -> Menu

    @State private var id = UUID()
    @State private var frame: CGRect = .zero

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { next in
                frame = next
                RautaThoughts.shared.move(id, to: next)
            }
            .onChange(of: isPresented) { _, presented in
                if presented {
                    let binding = $isPresented
                    RautaThoughts.shared.present(
                        id: id,
                        anchor: frame,
                        menu: AnyView(menu()),
                        close: { binding.wrappedValue = false },
                        onDismissed: onDismissed
                    )
                } else {
                    RautaThoughts.shared.dismiss(id)
                }
            }
            .onDisappear {
                if isPresented { isPresented = false }
                RautaThoughts.shared.dismiss(id, animated: false)
            }
    }
}

// MARK: - Presenter

@MainActor
final class RautaThoughts: ObservableObject {
    static let shared = RautaThoughts()

    struct Bubble {
        let id: UUID
        var anchor: CGRect
        let menu: AnyView
        let close: () -> Void
        let onDismissed: (() -> Void)?
    }

    @Published private(set) var bubble: Bubble?
    /// Whether the bubble is out, as opposed to on its way in or folding away.
    @Published private(set) var shown = false

    /// How long folding away takes, start to finish.
    static let foldDuration: TimeInterval = 0.32

    private var window: UIWindow?
    private var foldTask: Task<Void, Never>?

    private init() {}

    func present(
        id: UUID,
        anchor: CGRect,
        menu: AnyView,
        close: @escaping () -> Void,
        onDismissed: (() -> Void)?
    ) {
        // Only one thought at a time: another one still out closes first.
        if let current = bubble, current.id != id {
            current.close()
            finish()
        }
        foldTask?.cancel()
        guard let window = installWindow() else {
            close()
            return
        }
        bubble = Bubble(id: id, anchor: anchor, menu: menu, close: close, onDismissed: onDismissed)
        shown = false
        window.isHidden = false
        // One frame collapsed into RAUTA, then out.
        DispatchQueue.main.async { [weak self] in
            guard self?.bubble?.id == id else { return }
            self?.shown = true
        }
    }

    func move(_ id: UUID, to anchor: CGRect) {
        guard bubble?.id == id else { return }
        bubble?.anchor = anchor
    }

    func dismiss(_ id: UUID, animated: Bool = true) {
        guard bubble?.id == id else { return }
        guard animated else {
            finish()
            return
        }
        guard foldTask == nil else { return }
        shown = false
        foldTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.foldDuration))
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }

    /// A tap outside the bubble, or on one of its rows.
    func closeCurrent() {
        bubble?.close()
    }

    private func finish() {
        foldTask?.cancel()
        foldTask = nil
        let done = bubble?.onDismissed
        bubble = nil
        shown = false
        window?.isHidden = true
        done?()
    }

    private func installWindow() -> UIWindow? {
        if let window { return window }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        else { return nil }
        let window = UIWindow(windowScene: scene)
        // Over the app and its modals; never the key window, so a keyboard
        // that is up stays up.
        window.windowLevel = .normal + 1
        window.backgroundColor = .clear
        let host = UIHostingController(rootView: RautaThoughtsOverlay())
        host.view.backgroundColor = .clear
        host.safeAreaRegions = []
        window.rootViewController = host
        window.isHidden = true
        self.window = window
        return window
    }
}

// MARK: - Drawing

private struct RautaThoughtsOverlay: View {
    @ObservedObject private var model = RautaThoughts.shared

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                // Tapping anywhere else puts the thought away, and the tap goes
                // no further.
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture { model.closeCurrent() }
                    .accessibilityHidden(true)

                if let bubble = model.bubble {
                    ThoughtBubble(
                        anchor: bubble.anchor,
                        screen: proxy.size,
                        shown: model.shown,
                        menu: bubble.menu,
                        close: model.closeCurrent
                    )
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .tint(Theme.primary)
    }
}

/// Where each part of a thought goes, worked out from where RAUTA is.
private struct ThoughtGeometry {
    static let panelWidth: CGFloat = 272
    static let screenInset: CGFloat = 14
    /// Room between RAUTA and the panel for the trail of bubbles.
    static let trailGap: CGFloat = 38

    /// Above RAUTA when it sits in the lower half of the screen.
    let above: Bool
    let panelWidth: CGFloat
    let panelLeading: CGFloat
    /// The panel's edge nearest RAUTA: its bottom when above, its top when
    /// below.
    let panelEdgeY: CGFloat
    /// Where on that edge the trail joins the panel.
    let tail: CGPoint
    /// Where the trail ends, just off RAUTA's head.
    let origin: CGPoint

    init(anchor: CGRect, screen: CGSize) {
        above = anchor.midY > screen.height * 0.5
        panelWidth = min(Self.panelWidth, screen.width - Self.screenInset * 2)
        let onRight = anchor.midX > screen.width * 0.5
        // The panel leans away from the screen edge RAUTA is nearer to.
        let preferredLeading = onRight ? anchor.maxX - panelWidth + 6 : anchor.minX - 6
        panelLeading = min(
            max(preferredLeading, Self.screenInset),
            screen.width - Self.screenInset - panelWidth
        )
        panelEdgeY = above ? anchor.minY - Self.trailGap : anchor.maxY + Self.trailGap

        let inward: CGFloat = onRight ? -1 : 1
        origin = CGPoint(
            x: anchor.midX + inward * anchor.width * 0.12,
            y: above ? anchor.minY - 2 : anchor.maxY + 2
        )
        let tailX = min(
            max(anchor.midX + inward * 34, panelLeading + 44),
            panelLeading + panelWidth - 44
        )
        tail = CGPoint(x: tailX, y: panelEdgeY)
    }

    /// A point `fraction` of the way from the panel's edge to RAUTA.
    func trail(_ fraction: CGFloat) -> CGPoint {
        CGPoint(
            x: tail.x + (origin.x - tail.x) * fraction,
            y: tail.y + (origin.y - tail.y) * fraction
        )
    }

    /// The panel, out: `height` tall, its near edge on `panelEdgeY`.
    func panelFrame(height: CGFloat) -> CGRect {
        CGRect(
            x: panelLeading,
            y: above ? panelEdgeY - height : panelEdgeY,
            width: panelWidth,
            height: height
        )
    }

    /// The panel, folded: a bubble sitting where the trail meets it.
    func foldedPanelFrame(diameter: CGFloat) -> CGRect {
        CGRect(x: tail.x - diameter / 2, y: tail.y - diameter / 2, width: diameter, height: diameter)
    }
}

/// The thought itself.
///
/// Everything here grows by changing its real size and place, never by scaling
/// a picture of itself: Liquid Glass reshapes a pane whose frame changes, and
/// neighbouring panes in one container melt together as they meet — which is
/// what makes the panel pour out of the trail.
private struct ThoughtBubble: View {
    let anchor: CGRect
    let screen: CGSize
    let shown: Bool
    let menu: AnyView
    let close: () -> Void

    @State private var contentHeight: CGFloat = 60

    /// The trail, from the bubble joined to the panel to the smallest by
    /// RAUTA's head: where each sits along the way, how big it is, and its
    /// place in line leaving RAUTA.
    private static let trail: [(fraction: CGFloat, diameter: CGFloat, order: Int)] = [
        (0.14, 22, 1),
        (0.70, 11, 0),
    ]
    /// Folded, the panel is nothing at all: it pours out of the trail's
    /// largest bubble rather than sitting beside it.
    private static let foldedPanel: CGFloat = 1
    private static let glass = GlassTone.tinted(Theme.card.opacity(0.5))

    private static func spring(delay: Double) -> Animation {
        .spring(response: 0.36, dampingFraction: 0.74).delay(delay)
    }

    var body: some View {
        let geometry = ThoughtGeometry(anchor: anchor, screen: screen)

        GlassMorphContainer(spacing: 16) {
            ZStack(alignment: .topLeading) {
                ForEach(Self.trail, id: \.order) { bubble in
                    // Out of RAUTA smallest first; back in largest first.
                    let delay = shown ? Double(bubble.order) * 0.055 : Double(1 - bubble.order) * 0.06 + 0.08
                    let diameter = shown ? bubble.diameter : 0.5
                    Color.clear
                        .frame(width: diameter, height: diameter)
                        .glassSurface(Self.glass, in: Circle(), legacyFill: Theme.card.opacity(0.9))
                        .position(shown ? geometry.trail(bubble.fraction) : geometry.origin)
                        .animation(Self.spring(delay: delay), value: shown)
                        .allowsHitTesting(false)
                }

                panel(geometry)
            }
            .frame(width: screen.width, height: screen.height, alignment: .topLeading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, close)
    }

    private func panel(_ geometry: ThoughtGeometry) -> some View {
        let frame = shown
            ? geometry.panelFrame(height: contentHeight)
            : geometry.foldedPanelFrame(diameter: Self.foldedPanel)
        let radius = min(26, frame.height / 2)

        return VStack(alignment: .leading, spacing: 2) {
            menu
        }
        .buttonStyle(AppMenuRowButtonStyle())
        .labelStyle(.titleAndIcon)
        .foregroundStyle(Theme.foreground)
        .padding(8)
        .frame(width: geometry.panelWidth, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        // The rows stay their full size and are uncovered as the pane opens
        // around them, from the corner the trail joins.
        .opacity(shown ? 1 : 0)
        // The rows fade in once the pane has mostly opened, and out at once
        // when it starts to fold.
        .animation(shown ? .easeOut(duration: 0.2).delay(0.24) : .easeIn(duration: 0.1), value: shown)
        .frame(
            width: frame.width,
            height: frame.height,
            alignment: geometry.above ? .bottom : .top
        )
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .glassSurface(
            Self.glass,
            in: RoundedRectangle(cornerRadius: radius, style: .continuous),
            legacyFill: Theme.card.opacity(0.9)
        )
        // Picking a row puts the thought away; the row's own action still runs.
        .simultaneousGesture(TapGesture().onEnded { close() })
        .position(x: frame.midX, y: frame.midY)
        .animation(Self.spring(delay: shown ? 0.14 : 0), value: shown)
        .animation(Self.spring(delay: 0), value: contentHeight)
    }
}
