import SwiftUI

struct RautaScreen<Content: View, Controls: View, Right: View>: View {
    let title: String
    var subtitle: String?
    var subtitleProgress: [HeaderProgressState]? = nil
    var onTitleTap: (() -> Void)? = nil
    var backLabel: String?
    var onBack: (() -> Void)?
    var titleMultiline: Bool = false
    @ViewBuilder var right: () -> Right
    @ViewBuilder var content: () -> Content
    @ViewBuilder var controls: () -> Controls

    var body: some View {
        AppShell(commandsVisible: Controls.self != EmptyView.self) {
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
                    above: { EmptyView() },
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
        titleMultiline: Bool = false,
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
            titleMultiline: titleMultiline,
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
        titleMultiline: Bool = false,
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
            titleMultiline: titleMultiline,
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
        titleMultiline: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            subtitleProgress: subtitleProgress,
            onTitleTap: onTitleTap,
            backLabel: backLabel,
            onBack: onBack,
            titleMultiline: titleMultiline,
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
    }
}

struct SelectionChip: View {
    let title: String
    var selected = false
    let action: () -> Void

    var body: some View {
        Button {
            WorkoutAudio.touch(.tick)
            action()
        } label: {
            Text(title)
                .font(Theme.sans(13, weight: .semibold))
                .foregroundStyle(selected ? Theme.primaryForeground : Theme.secondaryForeground)
                .padding(.horizontal, 13)
        }
        .buttonStyle(
            .glassControl(
                selected ? .tinted(Theme.primary) : .clear,
                .capsule(height: 34)
            )
        )
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// What a page shows when it has nothing to list: RAUTA, looking the way the
/// situation feels, a title that says what is missing, a line on how to get
/// some, and optionally the one action that fixes it. Every empty list in the
/// app uses this, so they all read the same way.
///
/// On a page where RAUTA is already in view, a `symbol` stands in for it, so
/// the page does not show two of it.
struct EmptyStatePlaceholder: View {
    var mood: RautaMood = .curious
    var symbol: String? = nil
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: () -> Void = {}

    var body: some View {
        VStack(spacing: 12) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Theme.mutedForeground)
                    .frame(width: 64, height: 64)
                    .background(Theme.muted.opacity(0.7), in: Circle())
                    .padding(.bottom, 4)
                    .accessibilityHidden(true)
            } else {
                RautaCharacter(mood: mood, reactionKey: title, reaction: .peek)
                    .frame(width: 96, height: 96)
                    .accessibilityHidden(true)
            }

            Text(title)
                .font(Theme.sans(18, weight: .bold))
                .foregroundStyle(Theme.foreground)
                .multilineTextAlignment(.center)

            Text(message)
                .font(Theme.sans(14))
                .foregroundStyle(Theme.mutedForeground)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 286)

            if let actionTitle {
                AppButton(actionTitle, variant: .secondary, action: action)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: 320)
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

