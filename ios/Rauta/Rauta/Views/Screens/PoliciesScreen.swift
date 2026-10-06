import SwiftUI

/// Settings → Policies & credits: what RAUTA does with your data, and whose
/// work it is built on — the model, the exercise library, the open-source
/// packages and the fonts, each with its licence one tap away.
struct PoliciesScreen: View {
    private let store = AppStore.shared
    @State private var shown: OpenSourceNotices.Notice?

    var body: some View {
        RautaScreen(title: "Policies & credits", onBack: store.navigation.pop, right: {
            RautaHeaderBadge(mood: .calm)
        }) {
            ScrollView {
                VStack(spacing: 24) {
                    section("Privacy") {
                        ForEach(Array(PolicyFacts.privacy.enumerated()), id: \.offset) { index, point in
                            paragraph(icon: point.icon, title: point.title, text: point.text,
                                      showsDivider: index < PolicyFacts.privacy.count - 1)
                        }
                    }

                    section("RAUTA's brain") {
                        let model = RautaModelCatalog.qwen35_2b
                        linkRow(title: model.name, detail: "\(PolicyFacts.modelAuthor) · \(model.license)",
                                icon: "brain.head.profile", url: "https://huggingface.co/\(model.repo)",
                                showsDivider: true)
                        paragraph(icon: "cpu", title: nil, text: PolicyFacts.modelNote, showsDivider: false)
                    }

                    section("Exercise library") {
                        ForEach(Array(PolicyFacts.exerciseLibrary.enumerated()), id: \.offset) { index, point in
                            paragraph(icon: point.icon, title: point.title, text: point.text,
                                      showsDivider: index < PolicyFacts.exerciseLibrary.count - 1)
                        }
                    }

                    section("Open-source software") {
                        ForEach(Array(OpenSourceNotices.packages.enumerated()), id: \.element.id) { index, notice in
                            noticeRow(notice, icon: "shippingbox",
                                      showsDivider: index < OpenSourceNotices.packages.count - 1)
                        }
                    }

                    section("Fonts") {
                        ForEach(Array(OpenSourceNotices.fonts.enumerated()), id: \.element.id) { index, notice in
                            noticeRow(notice, icon: "textformat",
                                      showsDivider: index < OpenSourceNotices.fonts.count - 1)
                        }
                    }
                }
                .padding(.horizontal, Theme.Metrics.contentInset)
                .padding(.bottom, 24)
            }
            .pageScroll()
        }
        .sheet(item: $shown) { notice in
            LicenseTextSheet(notice: notice)
        }
    }

    // MARK: Pieces, in the Settings page's own style

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(Theme.sans(12, weight: .bold))
                .kerning(1.9)
                .foregroundStyle(Theme.mutedForeground)
                .padding(.horizontal, 4)
            VStack(spacing: 0) { content() }
                .background { GradientCard(radius: 24, accent: Theme.primary, strength: 0.6) }
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    private func icon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.primary)
            .frame(width: 34, height: 34)
            .background(Circle().fill(Theme.primary.opacity(0.14)))
            .accessibilityHidden(true)
    }

    private func divider(_ shows: Bool) -> some View {
        Rectangle()
            .fill(shows ? Theme.border.opacity(0.6) : .clear)
            .frame(height: 1)
            .padding(.leading, 62)
    }

    private func paragraph(icon name: String, title: String?, text: String, showsDivider: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                icon(name)
                VStack(alignment: .leading, spacing: 3) {
                    if let title {
                        Text(title)
                            .font(Theme.sans(15, weight: .bold))
                            .foregroundStyle(Theme.foreground)
                    }
                    Text(text)
                        .font(Theme.sans(14, weight: .medium))
                        .foregroundStyle(Theme.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            divider(showsDivider)
        }
        .accessibilityElement(children: .combine)
    }

    private func noticeRow(_ notice: OpenSourceNotices.Notice, icon name: String, showsDivider: Bool) -> some View {
        Button { shown = notice } label: {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    icon(name)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(notice.name)
                            .font(Theme.sans(15, weight: .semibold))
                            .foregroundStyle(Theme.foreground)
                        Text("\(notice.license) · \(notice.holder)")
                            .font(Theme.sans(13, weight: .medium))
                            .foregroundStyle(Theme.mutedForeground)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.mutedForeground)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                divider(showsDivider)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows the licence")
    }

    /// A row that opens a page in the browser. An address that does not parse
    /// leaves the row as plain text rather than taking the screen down.
    @ViewBuilder
    private func linkRow(title: String, detail: String, icon name: String, url: String, showsDivider: Bool) -> some View {
        let label = linkLabel(title: title, detail: detail, icon: name, showsDivider: showsDivider)
        if let destination = URL(string: url) {
            Link(destination: destination) { label }
                .buttonStyle(.plain)
        } else {
            label
        }
    }

    private func linkLabel(title: String, detail: String, icon name: String, showsDivider: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                icon(name)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.sans(15, weight: .semibold))
                        .foregroundStyle(Theme.foreground)
                    Text(detail)
                        .font(Theme.sans(13, weight: .medium))
                        .foregroundStyle(Theme.mutedForeground)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.mutedForeground)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            divider(showsDivider)
        }
        .contentShape(Rectangle())
    }
}

/// A licence, whole, as its authors wrote it.
private struct LicenseTextSheet: View {
    let notice: OpenSourceNotices.Notice
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(notice.name)
                        .font(Theme.sans(20, weight: .black))
                        .foregroundStyle(Theme.foreground)
                    Text(notice.license)
                        .font(Theme.sans(13, weight: .semibold))
                        .foregroundStyle(Theme.mutedForeground)
                }
                Spacer()
                AppHeaderButton(systemImage: "xmark", label: "Close") { dismiss() }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let url = URL(string: notice.url) {
                        Link(notice.url, destination: url)
                            .font(Theme.sans(13, weight: .semibold))
                            .foregroundStyle(Theme.primary)
                    }
                    Text(Self.reflowed(notice.text))
                        .font(Theme.sans(13, weight: .regular))
                        .lineSpacing(2)
                        .foregroundStyle(Theme.foreground.opacity(0.85))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
        .presentationDetents([.large])
        .presentationBackground { AppPageBackground() }
    }

    /// Licence files are wrapped at 80 columns for a terminal. On a phone each
    /// paragraph reads as one, so the line breaks inside it become spaces.
    static func reflowed(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: #/\n[ \t]*\n/#)
            .map { paragraph in
                // Rules of dashes go; an all-capitals heading keeps its own line.
                var out = ""
                for raw in paragraph.split(separator: "\n") {
                    let line = raw.trimmingCharacters(in: .whitespaces)
                    if line.isEmpty || line.allSatisfy({ "-=_*".contains($0) }) { continue }
                    let heading = line.count <= 70 && line.contains(where: \.isLetter)
                        && line == line.uppercased()
                    if heading {
                        out += (out.isEmpty ? "" : "\n") + line + "\n"
                    } else {
                        out += (out.isEmpty || out.hasSuffix("\n") ? "" : " ") + line
                    }
                }
                return out.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}

/// The page's words, kept together so they are reviewed together.
enum PolicyFacts {
    struct Point {
        var icon: String
        var title: String?
        var text: String
    }

    static let privacy: [Point] = [
        .init(icon: "iphone", title: "Stays on your iPhone",
              text: "RAUTA has no account and no servers. Your profile, plans, workouts and chats with RAUTA are stored on this iPhone and nowhere else of ours."),
        .init(icon: "icloud", title: "iCloud backup",
              text: "When iCloud is on, RAUTA keeps a backup of your training data in your own iCloud account, so it survives reinstalling. Only you can read it."),
        .init(icon: "heart", title: "Apple Health",
              text: "Only with your permission: RAUTA saves finished workouts and their energy, reads your body weight to estimate calories, and — if you allow it — reads sleep, resting heart rate, HRV, exercise time and active energy to plan around your readiness. Health data never leaves your iPhone."),
        .init(icon: "brain.head.profile", title: "Talking to RAUTA",
              text: "RAUTA thinks with a model that runs on your iPhone. The only download is the model itself, fetched once from Hugging Face; your messages are never sent anywhere."),
        .init(icon: "mic", title: "Microphone and speech",
              text: "Dictation is transcribed on your iPhone. The recording is deleted as soon as it has been read."),
        .init(icon: "calendar", title: "Calendar and notifications",
              text: "Used only when you ask: RAUTA reads your calendar to find free times, adds an event after you tap Add, and schedules the reminders you ask for."),
    ]

    static let modelAuthor = "Qwen team, Alibaba Cloud"
    static let modelNote = "A 4-bit MLX conversion of Qwen3.5 2B, published by the MLX Community on Hugging Face and run with Apple's MLX. It is downloaded on request and can be removed in Settings."

    // TODO(owner): confirm where the exercise catalogue, its demonstrations and
    // the body map come from, and under which licences, before release.
    static let exerciseLibrary: [Point] = [
        .init(icon: "figure.strengthtraining.traditional", title: "Exercises and demonstrations",
              text: "Exercise names, instructions and demonstration images come from a third-party exercise dataset, reviewed and reclassified for RAUTA. Source and licence to be confirmed."),
        .init(icon: "figure.stand", title: "Body map",
              text: "Muscle outlines for the body map. Source and licence to be confirmed."),
    ]
}
