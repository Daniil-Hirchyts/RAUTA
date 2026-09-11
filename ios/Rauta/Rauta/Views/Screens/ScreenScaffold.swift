import SwiftUI

struct RautaScreen<Content: View, Controls: View, Right: View>: View {
    let title: String
    var subtitle: String?
    var subtitleProgress: [HeaderProgressState]? = nil
    var onTitleTap: (() -> Void)? = nil
    var backLabel: String?
    var onBack: (() -> Void)?
    var progressStage: Int?
    var titleMultiline: Bool = false
    var hidden: Bool = false
    @ViewBuilder var right: () -> Right
    @ViewBuilder var content: () -> Content
    @ViewBuilder var controls: () -> Controls

    var body: some View {
        AppShell(commandsVisible: Controls.self != EmptyView.self) {
            ZStack(alignment: .top) {
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // React's `.app-shell-header + .app-scroll-region` puts
                    // this space inside the scroller. That keeps the first
                    // item clear at rest while later content can pass behind
                    // the fixed translucent title treatment.
                    .contentMargins(
                        .top,
                        Theme.Metrics.headerHeight + DeviceScreen.safeAreaInsets.top,
                        for: .scrollContent
                    )

                AppTopScrim()
                    .zIndex(20)

                AppShellHeader(
                    title: title,
                    subtitle: subtitle,
                    subtitleProgress: subtitleProgress,
                    onTitleTap: onTitleTap,
                    titleMultiline: titleMultiline,
                    hidden: hidden,
                    left: {
                        if let onBack {
                            AppHeaderButton(
                                systemImage: "chevron.left",
                                label: backLabel ?? "Back",
                                action: onBack
                            )
                        } else {
                            Color.clear.frame(width: 44, height: 44)
                        }
                    },
                    right: { right() },
                    above: {
                        if let progressStage {
                            FlowProgress(stage: progressStage)
                        }
                    },
                    below: { EmptyView() }
                )
                .zIndex(30)
            }
        } controls: {
            controls()
        }
    }
}

extension RautaScreen where Right == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        subtitleProgress: [HeaderProgressState]? = nil,
        onTitleTap: (() -> Void)? = nil,
        backLabel: String? = nil,
        onBack: (() -> Void)? = nil,
        progressStage: Int? = nil,
        titleMultiline: Bool = false,
        hidden: Bool = false,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder controls: @escaping () -> Controls
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            subtitleProgress: subtitleProgress,
            onTitleTap: onTitleTap,
            backLabel: backLabel,
            onBack: onBack,
            progressStage: progressStage,
            titleMultiline: titleMultiline,
            hidden: hidden,
            right: { EmptyView() },
            content: content,
            controls: controls
        )
    }
}

extension RautaScreen where Controls == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        subtitleProgress: [HeaderProgressState]? = nil,
        onTitleTap: (() -> Void)? = nil,
        backLabel: String? = nil,
        onBack: (() -> Void)? = nil,
        progressStage: Int? = nil,
        titleMultiline: Bool = false,
        hidden: Bool = false,
        @ViewBuilder right: @escaping () -> Right,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            subtitleProgress: subtitleProgress,
            onTitleTap: onTitleTap,
            backLabel: backLabel,
            onBack: onBack,
            progressStage: progressStage,
            titleMultiline: titleMultiline,
            hidden: hidden,
            right: right,
            content: content,
            controls: { EmptyView() }
        )
    }
}

extension RautaScreen where Controls == EmptyView, Right == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        subtitleProgress: [HeaderProgressState]? = nil,
        onTitleTap: (() -> Void)? = nil,
        backLabel: String? = nil,
        onBack: (() -> Void)? = nil,
        progressStage: Int? = nil,
        titleMultiline: Bool = false,
        hidden: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            subtitleProgress: subtitleProgress,
            onTitleTap: onTitleTap,
            backLabel: backLabel,
            onBack: onBack,
            progressStage: progressStage,
            titleMultiline: titleMultiline,
            hidden: hidden,
            right: { EmptyView() },
            content: content,
            controls: { EmptyView() }
        )
    }
}

struct SurfaceCard<Content: View>: View {
    var padding: CGFloat = 14
    var cornerRadius: CGFloat = Theme.Radius.xl
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card.opacity(0.88))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
    }
}

struct ChoiceRow: View {
    let title: String
    var detail: String?
    var systemImage: String?
    var selected = false
    var destructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(destructive ? Theme.destructive : Theme.primary)
                        .frame(width: 28)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(Theme.sans(16, weight: .semibold))
                        .foregroundStyle(destructive ? Theme.destructive : Theme.foreground)
                    if let detail {
                        Text(detail)
                            .font(Theme.sans(12))
                            .foregroundStyle(Theme.mutedForeground)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "chevron.right")
                    .foregroundStyle(selected ? Theme.primary : Theme.mutedForeground)
            }
            .padding(.vertical, 13)
            .padding(.horizontal, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(selected ? Theme.primary.opacity(0.08) : .clear)
    }
}

struct SelectionChip: View {
    let title: String
    var selected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.sans(13, weight: .semibold))
                .foregroundStyle(selected ? Theme.primaryForeground : Theme.secondaryForeground)
                .padding(.horizontal, 13)
                .frame(height: 34)
                .glassSurface(
                    selected ? .tinted(Theme.primary) : .clear,
                    in: Capsule(),
                    interactive: true,
                    border: selected ? Theme.Glassware.brightEdge : Theme.Glassware.edge,
                    legacyFill: selected ? Theme.primary.opacity(0.76) : Theme.card.opacity(0.72)
                )
                .overlay {
                    if selected {
                        Capsule()
                            .fill(Theme.primaryGradient)
                            .opacity(Theme.Glassware.primaryWash)
                            .allowsHitTesting(false)
                    }
                }
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct InlineNotice: View {
    let message: String
    var isError = false

    var body: some View {
        Text(message)
            .font(Theme.sans(14, weight: .medium))
            .foregroundStyle(isError ? Theme.destructive : Theme.mutedForeground)
            .multilineTextAlignment(.center)
            .padding(14)
            .frame(maxWidth: .infinity)
            .background((isError ? Theme.destructive : Theme.primary).opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .strokeBorder((isError ? Theme.destructive : Theme.primary).opacity(0.35))
            )
    }
}

struct RautaCompanion: View {
    var speech: String
    var size: CGFloat = 104

    private static let artwork = VectorArtworkLoader.load(contentsOf: MediaLibrary.rautaArtworkURL)

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let artwork = Self.artwork {
                    VectorArtworkView(artwork: artwork)
                } else {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: size * 0.46, weight: .bold))
                        .foregroundStyle(Theme.primary)
                }
            }
            .frame(width: size, height: size)

            Text(speech)
                .font(Theme.sans(14, weight: .semibold))
                .foregroundStyle(Theme.foreground)
                .lineSpacing(3)
                .padding(12)
                .background(Theme.popover.opacity(0.94))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
                        .strokeBorder(Theme.border)
                )
        }
        .accessibilityElement(children: .combine)
    }
}

@MainActor
struct ErrorState {
    var message: String?

    mutating func capture(_ error: Error) {
        message = (error as? TrainingPersistenceError)?.message
            ?? (error as? TrainingPersistenceValidationError)?.localizedDescription
            ?? error.localizedDescription
        Haptics.trigger(.warning)
    }
}
