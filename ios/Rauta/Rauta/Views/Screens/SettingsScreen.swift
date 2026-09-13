import SwiftUI
import UniformTypeIdentifiers

struct SettingsScreen: View {
    @ObservedObject private var store = AppStore.shared
    @State private var clearing = false
    @State private var importing = false
    @State private var exportURL: URL?
    @State private var notice: String?
    @State private var connectingHealth = false

    var body: some View {
        ZStack {
            RautaScreen(title: "Settings", onBack: store.navigation.pop) {
                ScrollView {
                    VStack(spacing: 24) {
                        section("Training profile") {
                            settingsAction(title: "Profile", detail: profileDescription, icon: "person", value: profileValue, showsDivider: true) {
                                store.navigation.push(.profileBasics)
                            }
                            settingsAction(title: "Training", detail: trainingSummary, icon: "scope", showsDivider: true) {
                                store.navigation.push(.profileTraining)
                            }
                            settingsAction(title: "Priority muscles", icon: "figure.strengthtraining.traditional", value: prioritySummary, showsDivider: false) {
                                store.navigation.push(.profilePriorities)
                            }
                        }

                        section("Apple Health") {
                            settingsRow(title: "Apple Health", detail: healthConnectionDescription, icon: "apple.logo", showsDivider: true) {
                                if connectingHealth {
                                    MatrixLoader(variant: .pulse, label: "Connecting to Apple Health")
                                        .frame(width: 20, height: 20)
                                }
                                AppSwitch(
                                    // Holds on while the permission sheet is up, so the
                                    // system switch does not flick back off under it.
                                    isOn: Binding(get: { store.settings.appleHealthEnabled || connectingHealth }, set: connectHealth),
                                    isDisabled: connectingHealth,
                                    label: "Apple Health integration"
                                )
                            }
                            settingsRow(title: "Sync workouts", detail: "Save completed workouts", icon: "heart.text.square", showsDivider: true) {
                                AppSwitch(
                                    isOn: Binding(
                                        get: { store.settings.autoSyncWorkouts },
                                        set: { enabled in store.settings.update { $0.autoSyncWorkouts = enabled } }
                                    ),
                                    isDisabled: !store.settings.appleHealthEnabled,
                                    label: "Sync completed workouts"
                                )
                            }
                            settingsRow(
                                title: "Active calories",
                                detail: "Workout time + Health weight",
                                icon: "waveform.path.ecg",
                                showsDivider: store.settings.healthStatus == .connected
                            ) {
                                AppSwitch(
                                    isOn: Binding(
                                        get: { store.settings.syncActiveCalories },
                                        set: { enabled in store.settings.update { $0.syncActiveCalories = enabled } }
                                    ),
                                    isDisabled: !store.settings.appleHealthEnabled || !store.settings.autoSyncWorkouts,
                                    label: "Sync active calories"
                                )
                            }
                            if store.settings.healthStatus == .connected {
                                settingsAction(title: "Manage Health permissions", icon: "heart.text.square", showsDivider: false) {
                                    HealthService.shared.openAppleHealthSettings()
                                }
                            }
                        }

                        section("Workout & Gym") {
                            settingsAction(
                                title: "Available equipment",
                                detail: "For generated plans",
                                icon: "dumbbell",
                                value: equipmentSummary,
                                showsDivider: true
                            ) {
                                store.navigation.push(.profileEquipment)
                            }
                            settingsRow(title: "Haptic feedback", icon: "iphone.radiowaves.left.and.right", showsDivider: true) {
                                AppSwitch(
                                    isOn: Binding(
                                        get: { store.settings.hapticsEnabled },
                                        set: { enabled in store.settings.update { $0.hapticsEnabled = enabled } }
                                    ),
                                    label: "Haptic feedback"
                                )
                            }
                            settingsRow(title: "Sound chimes", detail: "Cue after key actions", icon: "bell.badge", showsDivider: true) {
                                AppSwitch(
                                    isOn: Binding(
                                        get: { store.settings.soundChimesEnabled },
                                        set: { enabled in store.settings.update { $0.soundChimesEnabled = enabled } }
                                    ),
                                    label: "Sound chimes"
                                )
                            }
                            settingsRow(title: "Keep screen awake", detail: "Prevent auto-lock in workouts", icon: "iphone", showsDivider: false) {
                                AppSwitch(
                                    isOn: Binding(
                                        get: { store.settings.keepAwake },
                                        set: { enabled in store.settings.update { $0.keepAwake = enabled } }
                                    ),
                                    label: "Keep screen awake"
                                )
                            }
                        }

                        section("Data & Storage") {
                            settingsRow(title: "iCloud backup", detail: iCloudDescription, icon: "icloud", showsDivider: true) {
                                switch store.iCloud.status {
                                case .checking, .syncing:
                                    MatrixLoader(variant: .pulse, label: "Syncing iCloud backup")
                                        .frame(width: 20, height: 20)
                                case .unavailable:
                                    EmptyView()
                                case .synced, .error:
                                    Button(action: syncICloud) {
                                        Image(systemName: "arrow.clockwise")
                                            .font(.system(size: 17, weight: .semibold))
                                            .foregroundStyle(Theme.primary)
                                    }
                                    .buttonStyle(.glassControl(.clear, .circle(diameter: 40), legacyFill: Theme.card))
                                    .accessibilityLabel("Sync iCloud backup now")
                                }
                            }

                            if let exportURL {
                                ShareLink(item: exportURL) {
                                    settingsActionLabel(
                                        title: "Export data",
                                        detail: "Save one backup file",
                                        icon: "arrow.down.to.line",
                                        showsDivider: true
                                    )
                                }
                                .buttonStyle(.plain)
                            } else {
                                Button(action: prepareExport) {
                                    settingsActionLabel(
                                        title: "Export data",
                                        detail: "Save one backup file",
                                        icon: "arrow.down.to.line",
                                        showsDivider: true
                                    )
                                }
                                .buttonStyle(.plain)
                            }

                            Button { importing = true } label: {
                                settingsActionLabel(
                                    title: "Import data",
                                    detail: "Restore a RAUTA backup",
                                    icon: "doc.badge.arrow.up",
                                    showsDivider: true
                                )
                            }
                            .buttonStyle(.plain)

                            settingsAction(title: "Clear all data", icon: "trash", destructive: true, showsDivider: false) {
                                clearing = true
                            }
                        }

                        section("About") {
                            settingsRow(title: "App version", icon: "info.circle", showsDivider: false) {
                                Text(appVersion)
                                    .font(Theme.sans(14, weight: .medium))
                                    .foregroundStyle(Theme.mutedForeground)
                                    .monospacedDigit()
                            }
                        }

                        if let notice {
                            Text(notice)
                                .font(Theme.sans(14))
                                .foregroundStyle(Theme.mutedForeground)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 8)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, Theme.Metrics.contentInset)
                    .padding(.bottom, 24)
                }
                .pageScroll()
            }

            ConfirmModal(kind: clearing ? .clearData : nil, onCancel: { clearing = false }, onConfirm: clearData)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            importBackup(result)
        }
        .task {
            if exportURL == nil { exportURL = try? AppBackup.exportFileURL() }
        }
    }

    private var profileValue: String {
        let name = store.trainingProfile.profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Not set" : name
    }

    private var profileDescription: String {
        let profile = store.trainingProfile.profile
        var parts = ["\(Int(profile.age))", ProfileVocabulary.experienceLabel(profile.trainingExperience)]
        if profile.health.status != .healthy { parts.append("Manual only") }
        return parts.joined(separator: " · ")
    }

    private var trainingSummary: String {
        let profile = store.trainingProfile.profile
        return "\(ProfileVocabulary.goalLabel(profile.goal)) · \(Int(profile.preferredSessionDurationMinutes)) min"
    }

    private var equipmentSummary: String {
        let count = store.filters.gymEquipment.count
        return count > 0 ? Wording.countLabel(count, "item") : "Not set"
    }

    private var prioritySummary: String {
        let count = store.trainingProfile.profile.priorityMuscles.count
        return count > 0 ? Wording.countLabel(count, "muscle") : "None"
    }

    private var healthConnectionDescription: String {
        guard store.settings.healthStatus == .connected else { return "Save workouts to Health" }
        if let weight = store.settings.healthBodyWeightKg {
            return "Connected · \(Resistance.formatKg(weight)) kg"
        }
        return "Connected · workouts sync"
    }

    private var iCloudDescription: String {
        switch store.iCloud.status {
        case .checking:
            return "Checking iCloud…"
        case .syncing:
            return "Saving backup…"
        case .unavailable:
            return "Sign in to iCloud"
        case .error:
            return store.iCloud.error ?? "Backup failed"
        case .synced:
            guard let value = store.iCloud.lastSyncedAt, let millis = ISOTime.parse(value) else {
                return "Backed up automatically"
            }
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            formatter.dateStyle = .none
            return "Saved · \(formatter.string(from: Date(timeIntervalSince1970: millis / 1000)))"
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        return build.map { "\(version) (\($0))" } ?? version
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(Theme.sans(12, weight: .bold))
                .kerning(1.9)
                .foregroundStyle(Theme.mutedForeground)
                .padding(.horizontal, 4)

            VStack(spacing: 0) { content() }
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
                .shadow(color: .black.opacity(0.10), radius: 3, y: 1)
        }
    }

    private func settingsRow<Trailing: View>(
        title: String,
        detail: String? = nil,
        icon: String,
        showsDivider: Bool,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 12) {
            rowIcon(icon)
            rowLabel(title: title, detail: detail)
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 64)
        .overlay(alignment: .bottom) {
            if showsDivider { Rectangle().fill(Theme.border).frame(height: 1) }
        }
    }

    private func settingsAction(
        title: String,
        detail: String? = nil,
        icon: String,
        value: String? = nil,
        destructive: Bool = false,
        showsDivider: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.trigger(destructive ? .warning : .light)
            action()
        } label: {
            settingsActionLabel(
                title: title,
                detail: detail,
                icon: icon,
                value: value,
                destructive: destructive,
                showsDivider: showsDivider
            )
        }
        .buttonStyle(.plain)
    }

    private func settingsActionLabel(
        title: String,
        detail: String? = nil,
        icon: String,
        value: String? = nil,
        destructive: Bool = false,
        showsDivider: Bool
    ) -> some View {
        HStack(spacing: 12) {
            rowIcon(icon)
            rowLabel(title: title, detail: detail, destructive: destructive)
            if let value {
                Text(value)
                    .font(Theme.sans(14, weight: .medium))
                    .foregroundStyle(Theme.mutedForeground)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 150, alignment: .trailing)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(destructive ? Theme.primary : Theme.mutedForeground)
                .frame(width: 20)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 64)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if showsDivider { Rectangle().fill(Theme.border).frame(height: 1) }
        }
    }

    private func rowIcon(_ icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(Theme.primary)
            .frame(width: 20, height: 20)
    }

    private func rowLabel(title: String, detail: String?, destructive: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Theme.sans(16, weight: .semibold))
                .foregroundStyle(destructive ? Theme.primary : Theme.foreground)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let detail {
                Text(detail)
                    .font(Theme.sans(14))
                    .foregroundStyle(Theme.mutedForeground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func connectHealth(_ enabled: Bool) {
        guard !connectingHealth else { return }
        guard enabled else {
            store.settings.update { $0.appleHealthEnabled = false }
            return
        }

        connectingHealth = true
        notice = nil
        Task { @MainActor in
            let result = await HealthService.shared.requestAccess()
            connectingHealth = false
            switch result {
            case .connected(let bodyWeightKg):
                store.settings.update {
                    $0.appleHealthEnabled = true
                    $0.healthStatus = .connected
                    $0.healthBodyWeightKg = bodyWeightKg
                    $0.healthLastConnectedAt = ISOTime.now()
                }
                if let bodyWeightKg {
                    notice = "Apple Health connected. Using \(Resistance.formatKg(bodyWeightKg)) kg for energy estimates."
                } else {
                    notice = "Apple Health connected. Weight access is optional; energy uses a standard estimate."
                }
                Haptics.trigger(.success)
            case .unavailable:
                store.settings.update {
                    $0.appleHealthEnabled = false
                    $0.healthStatus = .unavailable
                    $0.healthBodyWeightKg = nil
                }
                notice = "Apple Health is available in the iPhone app."
                Haptics.trigger(.warning)
            }
        }
    }

    private func syncICloud() {
        Haptics.trigger(.light)
        if store.iCloud.syncNow() { Haptics.trigger(.success) }
    }

    private func prepareExport() {
        Haptics.trigger(.light)
        do {
            exportURL = try AppBackup.exportFileURL()
            notice = "Backup ready to save or share."
            Haptics.trigger(.success)
        } catch {
            notice = "The backup could not be written. Check the space left on this device, or leave iCloud backup on instead."
        }
    }

    private func importBackup(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            try AppBackup.importBackup(String(contentsOf: url, encoding: .utf8))
            notice = "Backup restored. Your workouts, favorites and presets are back."
            Haptics.trigger(.success)
        } catch {
            notice = (error as? TrainingPersistenceError)?.message
                ?? "That file is not a RAUTA backup. Pick the .json file this app exported."
            Haptics.trigger(.warning)
        }
    }

    private func clearData() {
        AppBackup.clearAllData()
        _ = store.iCloud.syncNow()
        clearing = false
        store.navigation.reset([.workouts])
    }
}
