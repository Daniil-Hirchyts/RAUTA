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
    var fullScreen: Bool = false
    @ViewBuilder var right: () -> Right
    @ViewBuilder var content: () -> Content
    @ViewBuilder var controls: () -> Controls

    var body: some View {
        AppShell(commandsVisible: Controls.self != EmptyView.self, fullScreen: fullScreen) {
            AppTitledPage {
                AppShellHeader(
                    title: title,
                    subtitle: subtitle,
                    subtitleProgress: subtitleProgress,
                    onTitleTap: onTitleTap,
                    titleMultiline: titleMultiline,
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
            } content: {
                content()
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
        fullScreen: Bool = false,
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
            fullScreen: fullScreen,
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
        fullScreen: Bool = false,
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
            fullScreen: fullScreen,
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
        fullScreen: Bool = false,
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
            fullScreen: fullScreen,
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
        }
        .buttonStyle(
            .glassControl(
                selected ? .tinted(Theme.primary) : .clear,
                .capsule(height: 34),
                legacyFill: selected ? Theme.primary.opacity(0.76) : Theme.card.opacity(0.72)
            )
        )
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

