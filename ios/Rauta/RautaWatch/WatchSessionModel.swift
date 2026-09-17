import Combine
import Foundation
import UserNotifications
import WatchConnectivity

/// The watch's side of the workout link. Its state is the UI's, so it lives on
/// the main actor; WatchConnectivity calls the delegate on a queue of its own,
/// and each callback copies out the `Data` it carries before hopping over.
@MainActor
final class WatchSessionModel: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchSessionModel()

    @Published private(set) var snapshot: RautaWatchWorkoutSnapshot?
    @Published var loadKg: Double = 0
    @Published var reps: Int = 10
    @Published private(set) var isSaving = false
    @Published private(set) var connectionIssue: String?

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let pendingActionsKey = "rauta-watch-pending-actions"
    private let pendingClaimKey = "rauta-watch-pending-health-claim"
    private var started = false
    /// The set last sent, until the phone says what became of it.
    private var awaitingResult: String?
    /// Bumped each time the phone confirms a set, for the view's haptic.
    @Published private(set) var confirmedSets = 0
    /// Bumped each time a set could not be saved, for the view's haptic.
    @Published private(set) var failedSets = 0

    private override init() {
        super.init()
    }

    func start() {
        guard !started, WCSession.isSupported() else { return }
        started = true
        let session = WCSession.default
        session.delegate = self
        session.activate()
        apply(Incoming(session.receivedApplicationContext))
    }

    func elapsedSeconds(at date: Date = Date()) -> TimeInterval {
        guard let snapshot else { return 0 }
        let live: TimeInterval = snapshot.runningSinceMilliseconds.map {
            Swift.max(0, date.timeIntervalSince1970 - ($0 / 1000))
        } ?? 0
        return Swift.max(0, snapshot.accumulatedSeconds + live)
    }

    func markSetDone() {
        guard !isSaving,
              let snapshot,
              let exerciseEntryId = snapshot.exerciseEntryId
        else { return }

        let action = RautaWatchSetAction(
            id: UUID().uuidString,
            workoutId: snapshot.workoutId,
            exerciseEntryId: exerciseEntryId,
            setDraftId: snapshot.setDraftId,
            loadKg: loadKg,
            reps: reps,
            restSeconds: snapshot.restSeconds,
            completedAtMilliseconds: Date().timeIntervalSince1970 * 1000
        )
        guard let data = try? encoder.encode(action) else { return }

        isSaving = true
        connectionIssue = nil
        awaitingResult = action.id
        let restSeconds = snapshot.restSeconds
        let session = WCSession.default

        guard session.activationState == .activated else {
            persistPending(data)
            scheduleLocalRest(seconds: restSeconds)
            markQueued()
            return
        }

        if session.isReachable {
            // The reply only confirms delivery; the phone sends what became of
            // the set as a message of its own (see `apply(_:)`).
            session.sendMessage(
                [RautaWatchMessageKey.action: data],
                replyHandler: { [weak self] _ in
                    Task { @MainActor in self?.isSaving = false }
                },
                errorHandler: { [weak self] _ in
                    Task { @MainActor in
                        guard let self else { return }
                        self.queue(data, restSeconds: restSeconds)
                        self.markQueued()
                    }
                }
            )
        } else {
            queue(data, restSeconds: restSeconds)
            markQueued()
        }
    }

    /// The set is kept for the phone and will reach it; for the person that is
    /// a logged set, with a note that the phone has not seen it yet.
    private func markQueued() {
        awaitingResult = nil
        isSaving = false
        confirmedSets += 1
        connectionIssue = "Set queued for iPhone"
    }

    /// Tells the phone the watch is recording `workoutId` in HealthKit and will
    /// save it. User info is queued and delivered even if the phone is away.
    func claimHealthWorkout(_ workoutId: String) {
        let claim = RautaWatchHealthClaim(
            workoutId: workoutId,
            claimedAtMilliseconds: Date().timeIntervalSince1970 * 1000
        )
        guard WCSession.isSupported(), let data = try? encoder.encode(claim) else { return }
        guard WCSession.default.activationState == .activated else {
            // Sent once the session activates.
            UserDefaults.standard.set(data, forKey: pendingClaimKey)
            return
        }
        WCSession.default.transferUserInfo([RautaWatchMessageKey.healthClaim: data])
    }

    private func flushPendingClaim() {
        guard let data = UserDefaults.standard.data(forKey: pendingClaimKey) else { return }
        WCSession.default.transferUserInfo([RautaWatchMessageKey.healthClaim: data])
        UserDefaults.standard.removeObject(forKey: pendingClaimKey)
    }

    private func queue(_ data: Data, restSeconds: Double) {
        let session = WCSession.default
        let message: [String: Any] = [RautaWatchMessageKey.action: data]
        try? session.updateApplicationContext(message)
        session.transferUserInfo(message)
        scheduleLocalRest(seconds: restSeconds)
    }

    private func persistPending(_ data: Data) {
        var pending = UserDefaults.standard.array(forKey: pendingActionsKey) as? [Data] ?? []
        pending.append(data)
        UserDefaults.standard.set(Array(pending.suffix(32)), forKey: pendingActionsKey)
    }

    private func flushPendingActions() {
        let session = WCSession.default
        let pending = UserDefaults.standard.array(forKey: pendingActionsKey) as? [Data] ?? []
        guard !pending.isEmpty else { return }

        for data in pending {
            session.transferUserInfo([RautaWatchMessageKey.action: data])
        }
        if let latest = pending.last {
            try? session.updateApplicationContext([RautaWatchMessageKey.action: latest])
        }
        UserDefaults.standard.removeObject(forKey: pendingActionsKey)
    }

    private func scheduleLocalRest(seconds: Double) {
        let center = UNUserNotificationCenter.current()
        Task {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            let content = UNMutableNotificationContent()
            content.title = "Rest complete"
            content.body = "Ready for your next set."
            content.sound = .default
            content.interruptionLevel = .timeSensitive
            let request = UNNotificationRequest(
                identifier: "rauta-watch-rest-complete",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(
                    timeInterval: Swift.max(1, seconds.rounded()),
                    repeats: false
                )
            )
            try? await center.add(request)
        }
    }

    private func requestSnapshot() {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(
            [RautaWatchMessageKey.requestSnapshot: true],
            // The phone answers with a snapshot message of its own.
            replyHandler: nil,
            errorHandler: { _ in }
        )
    }

    /// The parts of a WatchConnectivity dictionary the watch reads, as values
    /// that can cross to the main actor.
    private struct Incoming: Sendable {
        var snapshot: Data?
        var actionResult: Data?

        nonisolated init(_ dictionary: [String: Any]) {
            snapshot = dictionary[RautaWatchMessageKey.snapshot] as? Data
            actionResult = dictionary[RautaWatchMessageKey.actionResult] as? Data
        }
    }

    private func apply(_ incoming: Incoming) {
        if let data = incoming.actionResult,
           let result = try? decoder.decode(RautaWatchActionResult.self, from: data),
           result.actionId == awaitingResult {
            awaitingResult = nil
            isSaving = false
            applySnapshot(incoming.snapshot)
            if result.ok {
                confirmedSets += 1
            } else {
                failedSets += 1
                connectionIssue = "Could not save set"
            }
            return
        }
        applySnapshot(incoming.snapshot)
    }

    private func applySnapshot(_ data: Data?) {
        guard let data,
              let envelope = try? decoder.decode(RautaWatchSnapshotEnvelope.self, from: data)
        else { return }

        if let accent = envelope.accent { WatchAccentStore.shared.apply(accent) }
        let previousSet = snapshot?.setDraftId
        snapshot = envelope.snapshot
        if previousSet != envelope.snapshot?.setDraftId || envelope.snapshot == nil {
            loadKg = envelope.snapshot?.loadKg ?? 0
            reps = envelope.snapshot?.reps ?? 10
        }
        connectionIssue = nil
    }

    // MARK: WCSessionDelegate

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated else { return }
        let incoming = Incoming(session.receivedApplicationContext)
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.flushPendingActions()
            self.flushPendingClaim()
            self.apply(incoming)
            self.requestSnapshot()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let incoming = Incoming(applicationContext)
        Task { @MainActor [weak self] in self?.apply(incoming) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let incoming = Incoming(message)
        Task { @MainActor [weak self] in self?.apply(incoming) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in self?.requestSnapshot() }
    }
}
