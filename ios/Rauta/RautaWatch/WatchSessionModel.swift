import Foundation
import Observation
import UserNotifications
import WatchConnectivity
import WatchKit

/// The watch's side of the workout link. Its state is the UI's, so it lives on
/// the main actor; WatchConnectivity calls the delegate on a queue of its own,
/// and each callback copies out the `Data` it carries before hopping over.
///
/// The phone owns the workout. The watch shows the phone's last word with what
/// the watch has done since laid over it (see ``RautaWatchSync``): a set
/// logged here counts at once, the next "done" goes on the next set, and the
/// rest starts on the wrist straight away, whether or not the phone is in
/// reach.
@MainActor
@Observable
final class WatchSessionModel: NSObject, WCSessionDelegate {
    static let shared = WatchSessionModel()

    /// The workout as the watch shows it.
    private(set) var snapshot: RautaWatchWorkoutSnapshot?
    /// The load and reps the next "done" logs: the next set's target, until
    /// they are changed by hand.
    private(set) var loadKg: Double = 0
    private(set) var reps: Int = 10
    private(set) var isSaving = false
    private(set) var connectionIssue: String?
    /// Bumped each time a set counts, for the view's haptic.
    private(set) var confirmedSets = 0
    /// Bumped each time a set could not be saved, for the view's haptic.
    private(set) var failedSets = 0
    /// When the rest started here ends, until the phone says when its does.
    private(set) var localRestUntil: Date?

    /// The workout the phone is running, as it arrives; the HealthKit session
    /// follows it.
    @ObservationIgnored var onWorkoutChange: ((String?) -> Void)?
    /// A workout the phone says has ended, and how.
    @ObservationIgnored var onEnded: ((RautaWatchEndedWorkout) -> Void)?
    /// The phone paused or resumed.
    @ObservationIgnored var onPausedChange: ((Bool) -> Void)?

    @ObservationIgnored private var phoneSnapshot: RautaWatchWorkoutSnapshot?
    @ObservationIgnored private var revision: Int64?
    @ObservationIgnored private var pending: [RautaWatchPendingSet] = []
    @ObservationIgnored private var adjusted = false
    @ObservationIgnored private var restTask: Task<Void, Never>?
    @ObservationIgnored private var started = false

    @ObservationIgnored private let encoder = JSONEncoder()
    @ObservationIgnored private let decoder = JSONDecoder()
    private static let pendingSetsKey = "rauta-watch-pending-sets"
    private static let queuedActionsKey = "rauta-watch-pending-actions"
    private static let pendingClaimKey = "rauta-watch-pending-health-claim"
    private static let restNotificationID = "rauta-watch-rest-complete"

    private override init() {
        super.init()
        pending = UserDefaults.standard.data(forKey: Self.pendingSetsKey)
            .flatMap { try? JSONDecoder().decode([RautaWatchPendingSet].self, from: $0) } ?? []
    }

    func start() {
        guard !started, WCSession.isSupported() else { return }
        started = true
        let session = WCSession.default
        session.delegate = self
        session.activate()
        apply(Incoming(session.receivedApplicationContext))
    }

    // MARK: Reading

    func elapsedSeconds(at date: Date = Date()) -> TimeInterval {
        guard let snapshot else { return 0 }
        let live: TimeInterval = snapshot.runningSinceMilliseconds.map {
            Swift.max(0, date.timeIntervalSince1970 - ($0 / 1000))
        } ?? 0
        return Swift.max(0, snapshot.accumulatedSeconds + live)
    }

    /// When the rest on the wrist ends: the phone's deadline once it has one,
    /// the one started here until then.
    var restUntil: Date? {
        if let phone = snapshot?.restUntilMilliseconds { return Date(timeIntervalSince1970: phone / 1000) }
        guard let localRestUntil, localRestUntil > Date() else { return nil }
        return localRestUntil
    }

    var warmupUntil: Date? {
        snapshot?.warmupUntilMilliseconds.map { Date(timeIntervalSince1970: $0 / 1000) }
    }

    // MARK: Doing

    func setLoad(_ value: Double) {
        loadKg = Swift.min(500, Swift.max(0, value))
        adjusted = true
    }

    func setReps(_ value: Int) {
        reps = Swift.min(100, Swift.max(1, value))
        adjusted = true
    }

    func markSetDone() {
        guard !isSaving,
              let snapshot,
              let exerciseEntryId = snapshot.exerciseEntryId
        else { return }

        let now = Date()
        let action = RautaWatchSetAction(
            id: UUID().uuidString,
            workoutId: snapshot.workoutId,
            exerciseEntryId: exerciseEntryId,
            setDraftId: snapshot.setDraftId,
            loadKg: loadKg,
            reps: reps,
            restSeconds: snapshot.restSeconds,
            completedAtMilliseconds: now.timeIntervalSince1970 * 1000,
            version: 2
        )
        guard let data = try? encoder.encode(action) else { return }

        // It counts here at once: the set shows done, the next one comes up
        // and the rest starts, whether or not the phone hears of it yet.
        pending.append(RautaWatchPendingSet(
            actionId: action.id,
            workoutId: action.workoutId,
            exerciseEntryId: exerciseEntryId,
            setDraftId: action.setDraftId,
            loadKg: action.loadKg,
            reps: action.reps,
            completedAtMilliseconds: action.completedAtMilliseconds ?? now.timeIntervalSince1970 * 1000
        ))
        persistPending()
        adjusted = false
        refreshView()
        startLocalRest(until: now.addingTimeInterval(snapshot.restSeconds))
        confirmedSets += 1
        connectionIssue = nil

        deliver(data, key: RautaWatchMessageKey.action)
    }

    /// Something other than a set: a pause, the rest cut short or stretched.
    /// It shows here at once and reaches the phone the same way a set does.
    func control(_ kind: RautaWatchControlAction.Kind, seconds: Double? = nil) {
        guard let snapshot else { return }
        let action = RautaWatchControlAction(
            id: UUID().uuidString, workoutId: snapshot.workoutId, kind: kind, seconds: seconds
        )
        guard let data = try? encoder.encode(action) else { return }
        switch kind {
        case .endRest:
            localRestUntil = nil
            restTask?.cancel()
        case .extendRest:
            if let until = restUntil { startLocalRest(until: until.addingTimeInterval(seconds ?? 30)) }
        case .pause, .resume, .endWarmup:
            break
        }
        deliver(data, key: RautaWatchMessageKey.control)
    }

    /// Sends to the phone at once when it is in reach; otherwise queues it, so
    /// it arrives the moment the phone is back.
    private func deliver(_ data: Data, key: String) {
        let session = WCSession.default
        guard session.activationState == .activated else {
            persistQueued([key: data])
            return
        }
        if session.isReachable {
            isSaving = true
            Self.send([key: data], over: session) { [weak self] delivered in
                Task { @MainActor in
                    guard let self else { return }
                    self.isSaving = false
                    if !delivered { self.queue(data, key: key) }
                }
            }
        } else {
            queue(data, key: key)
        }
    }

    /// Kept for the phone: the application context holds the latest, user info
    /// holds every one, in order.
    private func queue(_ data: Data, key: String) {
        let session = WCSession.default
        let message: [String: Any] = [key: data]
        try? session.updateApplicationContext(message)
        session.transferUserInfo(message)
        connectionIssue = "Saved on the watch — iPhone will catch up"
    }

    // MARK: Health

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
            UserDefaults.standard.set(data, forKey: Self.pendingClaimKey)
            return
        }
        WCSession.default.transferUserInfo([RautaWatchMessageKey.healthClaim: data])
    }

    private func flushPendingClaim() {
        guard let data = UserDefaults.standard.data(forKey: Self.pendingClaimKey) else { return }
        WCSession.default.transferUserInfo([RautaWatchMessageKey.healthClaim: data])
        UserDefaults.standard.removeObject(forKey: Self.pendingClaimKey)
    }

    // MARK: Rest

    /// The rest on the wrist: a tap when it is over. The workout session keeps
    /// the app running with the wrist down, so the tap comes from here; a
    /// notification stands in only when no session is running.
    private func startLocalRest(until: Date) {
        localRestUntil = until
        armRestTap()
    }

    private func armRestTap() {
        restTask?.cancel()
        guard let until = restUntil else { return }
        restTask = Task { @MainActor [weak self] in
            let wait = until.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled, let self else { return }
            self.localRestUntil = nil
            WKInterfaceDevice.current().play(.stop)
        }
        scheduleFallbackNotification(at: until)
    }

    /// For a watch app the system has stopped: the tap from a notification.
    /// Withdrawn while the app is alive to tap itself.
    private func scheduleFallbackNotification(at date: Date) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.restNotificationID])
        guard !WatchWorkoutManager.shared.isTracking else { return }
        let interval = date.timeIntervalSinceNow
        guard interval > 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Rest complete"
        content.body = "Ready for your next set."
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let request = UNNotificationRequest(
            identifier: Self.restNotificationID,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        )
        Task {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            try? await center.add(request)
        }
    }

    // MARK: Applying the phone's word

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
           let result = try? decoder.decode(RautaWatchActionResult.self, from: data) {
            if result.ok {
                pending.removeAll { $0.actionId == result.actionId }
                persistPending()
            } else if pending.contains(where: { $0.actionId == result.actionId }) {
                // The phone could not take it: it no longer counts here either.
                pending.removeAll { $0.actionId == result.actionId }
                persistPending()
                failedSets += 1
                connectionIssue = "iPhone couldn't save that set"
            }
        }
        if let data = incoming.snapshot,
           let envelope = try? decoder.decode(RautaWatchSnapshotEnvelope.self, from: data) {
            applyEnvelope(envelope)
        } else {
            refreshView()
        }
    }

    private func applyEnvelope(_ envelope: RautaWatchSnapshotEnvelope) {
        if let accent = envelope.accent { WatchAccentStore.shared.apply(accent) }
        guard RautaWatchSync.isNewer(envelope.revision, than: revision) else { return }
        if let revision = envelope.revision { self.revision = revision }

        let previousWorkout = phoneSnapshot?.workoutId
        let wasPaused = phoneSnapshot?.isPaused
        phoneSnapshot = envelope.snapshot
        pending = RautaWatchSync.stillPending(
            pending,
            applied: envelope.appliedActionIds ?? [],
            runningWorkoutId: envelope.snapshot?.workoutId
        )
        persistPending()
        // The phone's rest, once it has one, is the rest.
        if envelope.snapshot?.restUntilMilliseconds != nil { localRestUntil = nil }
        refreshView()
        armRestTap()
        connectionIssue = nil

        if let ended = envelope.ended { onEnded?(ended) }
        if envelope.snapshot?.workoutId != previousWorkout { onWorkoutChange?(envelope.snapshot?.workoutId) }
        if let paused = envelope.snapshot?.isPaused, paused != wasPaused { onPausedChange?(paused) }
    }

    /// Lays the waiting sets over the phone's snapshot, and puts the next
    /// set's target in the controls unless they were changed by hand.
    private func refreshView() {
        let previousSet = snapshot?.setDraftId
        snapshot = phoneSnapshot.map { RautaWatchSync.merged($0, pending: pending) }
        guard let snapshot else { return }
        if snapshot.setDraftId != previousSet || !adjusted {
            loadKg = snapshot.loadKg
            reps = snapshot.reps
            adjusted = false
        }
    }

    private func persistPending() {
        if let data = try? encoder.encode(pending) {
            UserDefaults.standard.set(data, forKey: Self.pendingSetsKey)
        }
    }

    private func persistQueued(_ message: [String: Data]) {
        var queued = UserDefaults.standard.array(forKey: Self.queuedActionsKey) as? [[String: Data]] ?? []
        queued.append(message)
        UserDefaults.standard.set(Array(queued.suffix(32)), forKey: Self.queuedActionsKey)
    }

    private func flushQueued() {
        let session = WCSession.default
        let queued = UserDefaults.standard.array(forKey: Self.queuedActionsKey) as? [[String: Data]] ?? []
        guard !queued.isEmpty else { return }
        for message in queued { session.transferUserInfo(message) }
        UserDefaults.standard.removeObject(forKey: Self.queuedActionsKey)
    }

    private func requestSnapshot() {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        // The phone answers with a snapshot message of its own.
        Self.send([RautaWatchMessageKey.requestSnapshot: true], over: session) { _ in }
    }

    /// `nonisolated`: WatchConnectivity answers on a queue of its own, so the
    /// reply and error handlers are written where they cannot inherit the
    /// main actor — a main-actor closure called off the main thread traps.
    private nonisolated static func send(
        _ message: [String: Any],
        over session: WCSession,
        delivered: @escaping @Sendable (Bool) -> Void
    ) {
        session.sendMessage(
            message,
            replyHandler: { _ in delivered(true) },
            errorHandler: { _ in delivered(false) }
        )
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
            self.flushQueued()
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

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let incoming = Incoming(userInfo)
        Task { @MainActor [weak self] in self?.apply(incoming) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in self?.requestSnapshot() }
    }
}
