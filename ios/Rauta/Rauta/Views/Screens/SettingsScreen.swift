import SwiftUI
import UniformTypeIdentifiers

struct SettingsScreen: View {
    private let store = AppStore.shared
    private let agentModel = AgentModelStore.shared
    @State private var clearing = false
    @State private var importing = false
    @State private var connectingHealth = false
    /// A backup the person asked for, which RAUTA reports on when it lands.
    @State private var backupRequested = false

    var body: some View {
        ZStack {
            RautaScreen(title: "Settings", onBack: store.navigation.pop, right: {
                // RAUTA does the connecting, the backing up and the restoring
                // here, and says how each one went.
                RautaHeaderBadge(mood: .focused)
            }) {
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

                        section("RAUTA's brain") {
                            settingsRow(
                                title: RautaModelCatalog.qwen35_2b.name,
                                detail: agentModel.status,
                                icon: "brain.head.profile",
                                showsDivider: agentModel.installed
                            ) {
                                if agentModel.downloading {
                                    ProgressView(value: agentModel.progress)
                                        .frame(width: 64)
                                } else if !agentModel.installed {
                                    #if !targetEnvironment(simulator)
                                    Button("Download") { agentModel.download() }
                                        .font(Theme.sans(13, weight: .semibold))
                                    #endif
                                } else {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Theme.success)
                                }
                            }
                            #if !targetEnvironment(simulator)
                            if agentModel.installed {
                                settingsAction(title: "Remove downloaded model", icon: "trash",
                                               destructive: true, showsDivider: false) {
                                    try? agentModel.delete()
                                }
                            }
                            #endif
                        }

                        section("Apple Health") {
                            settingsRow(title: "Apple Health", detail: healthConnectionDescription, icon: "apple.logo", showsDivider: true) {
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
                            warmupRow
                                .overlay(alignment: .bottom) {
                                    Rectangle().fill(Theme.border).frame(height: 1)
                                }
                            settingsRow(title: "Workout sounds", detail: "Countdowns, rest and logged sets", icon: "speaker.wave.2", showsDivider: true) {
                                AppSwitch(
                                    isOn: Binding(
                                        get: { store.settings.workoutSoundsEnabled },
                                        set: { enabled in store.settings.update { $0.workoutSoundsEnabled = enabled } }
                                    ),
                                    label: "Workout sounds"
                                )
                            }
                            settingsRow(title: "Interface sounds", detail: "RAUTA, favourites and saves", icon: "bell.badge", showsDivider: true) {
                                AppSwitch(
                                    isOn: Binding(
                                        get: { store.settings.soundChimesEnabled },
                                        set: { enabled in store.settings.update { $0.soundChimesEnabled = enabled } }
                                    ),
                                    label: "Interface sounds"
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

                        section("Appearance") {
                            appearanceRow
                                .overlay(alignment: .bottom) {
                                    Rectangle().fill(Theme.border).frame(height: 1)
                                }
                            accentRow
                        }

                        section("Data & Storage") {
                            settingsRow(title: "iCloud backup", detail: iCloudDescription, icon: "icloud", showsDivider: true) {
                                switch store.iCloud.status {
                                case .checking, .syncing, .unavailable:
                                    EmptyView()
                                case .synced, .error:
                                    Button(action: syncICloud) {
                                        Image(systemName: "arrow.clockwise")
                                            .font(.system(size: 17, weight: .semibold))
                                            .foregroundStyle(Theme.primary)
                                    }
                                    .buttonStyle(.glassControl(.clear, .circle(diameter: 40)))
                                    .accessibilityLabel("Sync iCloud backup now")
                                }
                            }

                            // The backup is written when the share sheet asks for
                            // it, not every time Settings opens.
                            ShareLink(item: BackupExport(), preview: SharePreview("RAUTA backup")) {
                                settingsActionLabel(
                                    title: "Export data",
                                    detail: "Save one backup file",
                                    icon: "arrow.down.to.line",
                                    showsDivider: true
                                )
                            }
                            .buttonStyle(.plain)

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
                            settingsAction(title: "Policies & credits",
                                           detail: "Privacy, the model, exercise data and licences",
                                           icon: "doc.text", showsDivider: true) {
                                store.navigation.push(.policies)
                            }
                            settingsRow(title: "App version", icon: "info.circle", showsDivider: false) {
                                Text(appVersion)
                                    .font(Theme.sans(14, weight: .medium))
                                    .foregroundStyle(Theme.mutedForeground)
                                    .monospacedDigit()
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Metrics.contentInset)
                    .padding(.bottom, 24)
                }
                .pageScroll()
                .onChange(of: store.iCloud.status) { _, status in reportBackup(status) }
            }

            ConfirmModal(kind: clearing ? .clearData : nil, onCancel: { clearing = false }, onConfirm: clearData)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            importBackup(result)
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
            let saved = Date(epochMillis: millis)
            return "Saved · \(saved.formatted(date: .omitted, time: .shortened))"
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        return build.map { "\(version) (\($0))" } ?? version
    }

    /// How long the warm-up that opens every workout runs, or none at all.
    private var warmupRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                rowIcon("figure.cooldown")
                rowLabel(
                    title: "Warm-up",
                    detail: store.settings.warmupLength == .off
                        ? "Workouts start straight away"
                        : "Guided moves before every workout"
                )
            }
            GlassSegmentedPicker(
                title: "Warm-up",
                options: WarmupLength.allCases,
                selection: Binding(
                    get: { store.settings.warmupLength },
                    set: { length in store.settings.update { $0.warmupSeconds = length.seconds } }
                ),
                label: \.label
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    /// The theme: the iPhone's own, or light or dark for good. The change
    /// cross-fades the whole app in place, so the choice is seen as it is made.
    ///
    /// A compact glass segment control, its selection tinted in the brand's
    /// orange.
    private var appearanceRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                rowIcon("circle.lefthalf.filled")
                rowLabel(title: "Theme", detail: store.settings.appearance.summary)
            }
            GlassSegmentedPicker(
                title: "Theme",
                options: AppAppearance.allCases,
                selection: Binding(
                    get: { store.settings.appearance },
                    set: { appearance in store.settings.update { $0.appearance = appearance } }
                ),
                label: \.label
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    /// The colour the whole app is drawn in: nine presets across the wheel, or
    /// any colour from the system picker. Everything follows at once — buttons,
    /// glass, glows, the muscle maps and the exercise demonstrations.
    private var accentRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                rowIcon("paintpalette")
                rowLabel(title: "Accent color", detail: store.settings.accent.name)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 5), spacing: 10) {
                ForEach(AccentPreset.allCases) { preset in
                    AccentSwatch(
                        fill: preset.swatch,
                        selected: store.settings.accent == .preset(preset)
                    ) {
                        chooseAccent(.preset(preset))
                    }
                    .accessibilityLabel("\(preset.name) accent")
                }
                CustomAccentWell(
                    color: Binding(
                        get: { Theme.primary },
                        set: { color in
                            chooseAccent(.custom(HSB(UIColor(color)).hex), haptic: false)
                        }
                    ),
                    selected: { if case .custom = store.settings.accent { return true }; return false }()
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func chooseAccent(_ accent: AppAccent, haptic: Bool = true) {
        guard accent != store.settings.accent else { return }
        if haptic { Haptics.trigger(.selection) }
        store.settings.update { $0.accent = accent.storage }
    }

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
        RautaSpeech.shared.working("Asking Apple Health for access…")
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
                    RautaSpeech.shared.say(
                        "Apple Health is connected. I'll use \(Resistance.formatKg(bodyWeightKg)) kg for energy estimates.",
                        reaction: .celebrate
                    )
                } else {
                    RautaSpeech.shared.say(
                        "Apple Health is connected. Without your weight I'll use a standard energy estimate.",
                        reaction: .celebrate
                    )
                }
                Haptics.trigger(.success)
            case .unavailable:
                store.settings.update {
                    $0.appleHealthEnabled = false
                    $0.healthStatus = .unavailable
                    $0.healthBodyWeightKg = nil
                }
                RautaSpeech.shared.say("Apple Health only works in the iPhone app.", reaction: .frustrated)
                Haptics.trigger(.warning)
            }
        }
    }

    private func syncICloud() {
        Haptics.trigger(.light)
        guard store.iCloud.syncNow() else { return }
        backupRequested = true
        RautaSpeech.shared.working("Backing everything up to iCloud…")
    }

    /// How the backup the person asked for went, once it has.
    private func reportBackup(_ status: ICloudSync.Status) {
        guard backupRequested else { return }
        switch status {
        case .synced:
            backupRequested = false
            Haptics.trigger(.success)
            RautaSpeech.shared.say("All backed up to iCloud.", reaction: .celebrate)
        case .error, .unavailable:
            backupRequested = false
            RautaSpeech.shared.say(
                "The backup didn't go through. \(store.iCloud.error ?? "Check that you're signed in to iCloud.")",
                reaction: .frustrated
            )
        case .checking, .syncing:
            break
        }
    }

    private func importBackup(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            try AppBackup.importBackup(String(contentsOf: url, encoding: .utf8))
            RautaSpeech.shared.say("Backup restored. Your workouts, favorites and presets are back.", reaction: .celebrate)
            Haptics.trigger(.success)
        } catch {
            RautaSpeech.shared.say(
                (error as? TrainingPersistenceError)?.message
                    ?? "That file isn't a RAUTA backup. Pick the .json file this app exported.",
                reaction: .frustrated
            )
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

/// One preset accent: its own button gradient in a circle, ringed and checked
/// when it is the one in use.
private struct AccentSwatch: View {
    var fill: LinearGradient
    var selected: Bool
    var action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(fill)
                    .frame(width: 32, height: 32)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.primaryForeground)
                        .transition(.motion(.scale.combined(with: .opacity), reduced: reduceMotion))
                }
            }
            .frame(width: 42, height: 42)
            .overlay(
                Circle().strokeBorder(selected ? Theme.foreground.opacity(0.9) : .clear, lineWidth: 2)
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .animation(Theme.Motion.spring, value: selected)
    }
}

/// Any colour at all, through the system colour picker. The well shows the
/// accent in use inside its rainbow ring, and is ringed like a preset when the
/// accent is a picked colour.
private struct CustomAccentWell: View {
    @Binding var color: Color
    var selected: Bool

    var body: some View {
        ColorPicker("Custom accent color", selection: $color, supportsOpacity: false)
            .labelsHidden()
            .scaleEffect(1.12)
            .frame(width: 42, height: 42)
            .overlay(
                Circle()
                    .strokeBorder(selected ? Theme.foreground.opacity(0.9) : .clear, lineWidth: 2)
                    .allowsHitTesting(false)
            )
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A backup that exists only once something asks for its file.
private struct BackupExport: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { _ in
            SentTransferredFile(try await AppBackup.exportFileURL())
        }
    }
}
