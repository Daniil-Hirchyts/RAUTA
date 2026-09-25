import Combine
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
//
// What RAUTA says rises the same way, from the same presenter, so a line and a
// menu can never be out at once: opening the menu puts the line away, and a
// line never interrupts an open menu. A line is only to be read — the window
// lets every touch through to the app while one is out.

extension View {
    /// Shows `menu` as a thought bubble rising from this view while
    /// `isPresented` is true. `onDismissed` runs once the bubble has folded
    /// away — the moment a picked action can open a page.
    ///
    /// `lift` moves the bubble further from RAUTA, clear of something sitting
    /// between them — the exercise bar over the tabs.
    func rautaThoughts<Menu: View>(
        isPresented: Binding<Bool>,
        lift: CGFloat = 0,
        onDismissed: (() -> Void)? = nil,
        @ViewBuilder menu: @escaping () -> Menu
    ) -> some View {
        modifier(RautaThoughtsAnchor(isPresented: isPresented, lift: lift, onDismissed: onDismissed, menu: menu))
    }
}

private struct RautaThoughtsAnchor<Menu: View>: ViewModifier {
    @Binding var isPresented: Bool
    var lift: CGFloat
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
                        lift: lift,
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
        enum Content {
            case menu(AnyView)
            case line(String)
        }

        let id: UUID
        var anchor: CGRect
        var lift: CGFloat
        var content: Content
        let close: () -> Void
        let onDismissed: (() -> Void)?

        var isMenu: Bool {
            if case .menu = content { return true }
            return false
        }
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
        lift: CGFloat = 0,
        menu: AnyView,
        close: @escaping () -> Void,
        onDismissed: (() -> Void)?
    ) {
        open(Bubble(id: id, anchor: anchor, lift: lift, content: .menu(menu), close: close, onDismissed: onDismissed))
    }

    /// RAUTA saying `text` from the character at `anchor`. A line from the same
    /// character changes in place; a line never goes over an open menu.
    func say(id: UUID, anchor: CGRect, lift: CGFloat, text: String, close: @escaping () -> Void) {
        if let current = bubble {
            if current.isMenu { return }
            if current.id == id, foldTask == nil {
                bubble?.content = .line(text)
                bubble?.anchor = anchor
                bubble?.lift = lift
                return
            }
        }
        open(Bubble(id: id, anchor: anchor, lift: lift, content: .line(text), close: close, onDismissed: nil))
    }

    private func open(_ next: Bubble) {
        // Only one thought at a time: another one still out closes first.
        if let current = bubble, current.id != next.id || current.isMenu != next.isMenu {
            current.close()
            finish()
        }
        foldTask?.cancel()
        foldTask = nil
        guard let window = installWindow() else {
            next.close()
            return
        }
        bubble = next
        shown = false
        // A line is only read: every touch goes through to the app.
        window.isUserInteractionEnabled = next.isMenu
        window.isHidden = false
        // One frame collapsed into RAUTA, then out.
        let id = next.id
        DispatchQueue.main.async { [weak self] in
            guard self?.bubble?.id == id else { return }
            self?.shown = true
        }
    }

    func move(_ id: UUID, to anchor: CGRect, lift: CGFloat? = nil) {
        guard bubble?.id == id else { return }
        bubble?.anchor = anchor
        if let lift { bubble?.lift = lift }
    }

    /// Puts away whatever `id` is saying, if it is saying anything.
    func hush(_ id: UUID? = nil) {
        guard let bubble, !bubble.isMenu, id == nil || bubble.id == id else { return }
        dismiss(bubble.id)
    }

    var menuIsOpen: Bool { bubble?.isMenu == true }

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
                // Tapping anywhere else puts a menu away, and the tap goes no
                // further. A line takes no touches at all.
                if model.bubble?.isMenu == true {
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .onTapGesture { model.closeCurrent() }
                        .accessibilityHidden(true)
                }

                if let bubble = model.bubble {
                    ThoughtBubble(
                        anchor: bubble.anchor,
                        lift: bubble.lift,
                        screen: proxy.size,
                        shown: model.shown,
                        content: bubble.content,
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
    /// Room between RAUTA and the panel.
    static let trailGap: CGFloat = 26
    /// The small bubble sits where it would with this much room, whatever the
    /// panel's own gap: it is RAUTA's, and stays put by the head.
    private static let smallBubbleGap: CGFloat = 36
    private static let smallBubbleFraction: CGFloat = 0.70
    /// How far the large bubble's centre sits out past the panel's edge: most
    /// of it inside the panel, a round bump outside.
    private static let largeBubbleOverhang: CGFloat = 3

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
    /// The small bubble, by RAUTA's head.
    let smallBubble: CGPoint
    /// The large bubble, set into the panel's edge.
    let largeBubble: CGPoint

    init(anchor: CGRect, screen: CGSize, width: CGFloat = ThoughtGeometry.panelWidth, lift: CGFloat = 0) {
        above = anchor.midY > screen.height * 0.5
        panelWidth = min(width, screen.width - Self.screenInset * 2)
        let onRight = anchor.midX > screen.width * 0.5
        // The panel leans away from the screen edge RAUTA is nearer to.
        let preferredLeading = onRight ? anchor.maxX - panelWidth + 6 : anchor.minX - 6
        panelLeading = min(
            max(preferredLeading, Self.screenInset),
            screen.width - Self.screenInset - panelWidth
        )
        let gap = Self.trailGap + lift
        panelEdgeY = above ? anchor.minY - gap : anchor.maxY + gap

        let inward: CGFloat = onRight ? -1 : 1
        origin = CGPoint(
            x: anchor.midX + inward * anchor.width * 0.12,
            y: above ? anchor.minY - 2 : anchor.maxY + 2
        )
        let tailX = min(
            max(anchor.midX + inward * 40, panelLeading + 44),
            panelLeading + panelWidth - 44
        )
        tail = CGPoint(x: tailX, y: panelEdgeY)

        let smallGap = Self.smallBubbleGap + lift * 0.6
        let smallTailY = above ? anchor.minY - smallGap : anchor.maxY + smallGap
        smallBubble = CGPoint(
            x: tailX + (origin.x - tailX) * Self.smallBubbleFraction,
            y: smallTailY + (origin.y - smallTailY) * Self.smallBubbleFraction
        )
        let dx = smallBubble.x - tail.x
        let dy = smallBubble.y - tail.y
        let length = max(1, (dx * dx + dy * dy).squareRoot())
        largeBubble = CGPoint(
            x: tail.x + dx / length * Self.largeBubbleOverhang,
            y: tail.y + dy / length * Self.largeBubbleOverhang
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
    var lift: CGFloat = 0
    let screen: CGSize
    let shown: Bool
    let content: RautaThoughts.Bubble.Content
    let close: () -> Void

    @State private var contentHeight: CGFloat = 60
    /// The content's width on one row, so a short line or a short menu gets a
    /// narrow bubble.
    @State private var lineWidth: CGFloat = ThoughtGeometry.panelWidth
    @State private var menuWidth: CGFloat = ThoughtGeometry.panelWidth

    private var isMenu: Bool {
        if case .menu = content { return true }
        return false
    }

    private var width: CGFloat {
        isMenu
            ? min(ThoughtGeometry.panelWidth, max(Self.narrowestMenu, menuWidth + 1))
            : min(ThoughtGeometry.panelWidth, lineWidth + 1)
    }

    private static let narrowestMenu: CGFloat = 176

    /// A menu opens tight against RAUTA even over the exercise bar: it is out
    /// only while someone is choosing, and a tap anywhere puts it away. A
    /// line, which stays while you carry on, rises clear of the bar.
    private var effectiveLift: CGFloat {
        isMenu ? 0 : lift
    }
    /// Reduce Motion: the thought fades in and out where it rests, with no
    /// travel out of RAUTA and no growing pane.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var laidOut: Bool { shown || reduceMotion }
    private static let fade = Animation.easeOut(duration: 0.2)

    /// The trail: the bubble set into the panel and the small one by RAUTA's
    /// head — how big each is, and its place in line leaving RAUTA.
    private static let trail: [(large: Bool, diameter: CGFloat, order: Int)] = [
        (true, 22, 1),
        (false, 11, 0),
    ]
    /// Folded, the panel is nothing at all: it pours out of the trail's
    /// largest bubble rather than sitting beside it.
    private static let foldedPanel: CGFloat = 1
    private static let glass = GlassTone.tinted(Theme.card.opacity(0.5))

    private static func spring(delay: Double) -> Animation {
        .spring(response: 0.36, dampingFraction: 0.74).delay(delay)
    }

    var body: some View {
        let geometry = ThoughtGeometry(anchor: anchor, screen: screen, width: width, lift: effectiveLift)

        // Tight, so only the bubble touching the panel melts into it: glass
        // that merely comes near other glass bulges toward it and magnifies.
        GlassMorphContainer(spacing: 4) {
            ZStack(alignment: .topLeading) {
                ForEach(Self.trail, id: \.order) { bubble in
                    // Out of RAUTA smallest first; back in largest first.
                    let delay = shown ? Double(bubble.order) * 0.055 : Double(1 - bubble.order) * 0.06 + 0.08
                    // Lifted over the exercise bar, the loose bubble would sit
                    // on the bar itself; only the one set into the panel stays.
                    let hidden = effectiveLift > 0 && !bubble.large
                    let diameter = laidOut && !hidden ? bubble.diameter : 0.5
                    Color.clear
                        .frame(width: diameter, height: diameter)
                        .glassSurface(Self.glass, in: Circle())
                        .opacity((reduceMotion && !shown) || hidden ? 0 : 1)
                        .position(laidOut ? (bubble.large ? geometry.largeBubble : geometry.smallBubble) : geometry.origin)
                        .animation(reduceMotion ? Self.fade : Self.spring(delay: delay), value: shown)
                        .allowsHitTesting(false)
                }

                panel(geometry)
            }
            .frame(width: screen.width, height: screen.height, alignment: .topLeading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isMenu ? .isModal : [])
        .accessibilityAction(.escape, close)
        // A line is already announced when it is said; left in the tree it
        // would pull VoiceOver's focus off the page for words that are gone.
        .accessibilityHidden(!isMenu)
        .background { lineMeasure }
    }

    /// The content laid out at its natural width, off screen, to size the
    /// bubble around it.
    @ViewBuilder private var lineMeasure: some View {
        switch content {
        case .line(let text):
            Self.lineText(text)
                .fixedSize()
                .hidden()
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { lineWidth = $0 }
                .accessibilityHidden(true)
        case .menu(let menu):
            VStack(alignment: .leading, spacing: 2) { menu }
                .buttonStyle(AppMenuRowButtonStyle())
                .labelStyle(.titleAndIcon)
                .padding(8)
                .fixedSize()
                .hidden()
                .allowsHitTesting(false)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { menuWidth = $0 }
                .accessibilityHidden(true)
        }
    }

    private static func lineText(_ text: String) -> some View {
        Text(text)
            .font(Theme.sans(16, weight: .medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
    }

    @ViewBuilder private var panelContent: some View {
        switch content {
        case .menu(let menu):
            VStack(alignment: .leading, spacing: 2) { menu }
                .padding(8)
        case .line(let text):
            Self.lineText(text)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
                .accessibilityAddTraits(.isStaticText)
        }
    }

    private func panel(_ geometry: ThoughtGeometry) -> some View {
        let frame = laidOut
            ? geometry.panelFrame(height: contentHeight)
            : geometry.foldedPanelFrame(diameter: Self.foldedPanel)
        let radius = min(26, frame.height / 2)

        return panelContent
        .buttonStyle(AppMenuRowButtonStyle())
        .labelStyle(.titleAndIcon)
        .foregroundStyle(Theme.foreground)
        .frame(width: geometry.panelWidth, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        // The rows stay their full size and are uncovered as the pane opens
        // around them, from the corner the trail joins.
        .opacity(shown ? 1 : 0)
        // The rows fade in once the pane has mostly opened, and out at once
        // when it starts to fold.
        .animation(
            reduceMotion ? Self.fade
                : (shown ? .easeOut(duration: 0.16).delay(0.1) : .easeOut(duration: 0.1)),
            value: shown
        )
        .frame(
            width: frame.width,
            height: frame.height,
            alignment: geometry.above ? .bottom : .top
        )
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .glassSurface(
            Self.glass,
            in: RoundedRectangle(cornerRadius: radius, style: .continuous)
        )
        .opacity(reduceMotion && !shown ? 0 : 1)
        // Picking a row puts the thought away; the row's own action still runs.
        .simultaneousGesture(TapGesture().onEnded { if isMenu { close() } })
        .position(x: frame.midX, y: frame.midY)
        .animation(reduceMotion ? Self.fade : Self.spring(delay: shown ? 0.06 : 0), value: shown)
        .animation(Self.spring(delay: 0), value: contentHeight)
        .animation(Self.spring(delay: 0), value: width)
        .animation(Self.spring(delay: 0), value: effectiveLift)
    }
}
