import SwiftUI

/// A titled group on a warm card — the grouping Settings uses — for pages that
/// explain or review something: backups, the week ahead, the week behind.
struct PageSection<Content: View>: View {
    var title: String?
    var accent: Color = Theme.primary
    var strength: Double = 0.6
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title.uppercased())
                    .font(Theme.sans(12, weight: .bold))
                    .kerning(1.9)
                    .foregroundStyle(Theme.mutedForeground)
                    .padding(.horizontal, 4)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(alignment: .leading, spacing: 0) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background { GradientCard(radius: 24, accent: accent, strength: strength) }
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: .black.opacity(0.10), radius: 3, y: 1)
        }
    }
}

/// One line of a ``PageSection``: an icon, what it is, a sentence about it,
/// and whatever belongs at its end. Text wraps rather than truncates, so it
/// reads whole at every text size.
struct PageRow<Trailing: View>: View {
    var icon: String
    var tint: Color = Theme.primary
    var title: String
    var detail: String?
    var showsDivider = true
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.14), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(Theme.sans(13, weight: .medium))
                        .foregroundStyle(Theme.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 60)
        .overlay(alignment: .bottom) {
            if showsDivider { Rectangle().fill(Theme.border).frame(height: 1) }
        }
        .accessibilityElement(children: .combine)
    }
}

extension PageRow where Trailing == EmptyView {
    init(icon: String, tint: Color = Theme.primary, title: String, detail: String? = nil, showsDivider: Bool = true) {
        self.init(icon: icon, tint: tint, title: title, detail: detail, showsDivider: showsDivider) { EmptyView() }
    }
}

/// A tappable ``PageRow`` with a chevron.
struct PageActionRow: View {
    var icon: String
    var tint: Color = Theme.primary
    var title: String
    var detail: String?
    var showsDivider = true
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.trigger(.light)
            action()
        } label: {
            PageRow(icon: icon, tint: tint, title: title, detail: detail, showsDivider: showsDivider) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.mutedForeground)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A paragraph inside a ``PageSection``.
struct PageNote: View {
    var text: String
    var tint: Color?

    var body: some View {
        Text(text)
            .font(Theme.sans(13, weight: .medium))
            .foregroundStyle(tint ?? Theme.mutedForeground)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// When something happened, the way a person says it: "today at 14:32",
/// "yesterday at 09:10", "Sat 3 Oct at 18:05".
enum RelativeMoment {
    static func text(_ iso: String?, now: Date = Date()) -> String? {
        guard let iso, let millis = ISOTime.parse(iso) else { return nil }
        let date = Date(epochMillis: millis)
        let time = date.formatted(date: .omitted, time: .shortened)
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return "today at \(time)" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "yesterday at \(time)"
        }
        return "\(CalendarDate.string(from: date, template: "EEEdMMM")) at \(time)"
    }
}
