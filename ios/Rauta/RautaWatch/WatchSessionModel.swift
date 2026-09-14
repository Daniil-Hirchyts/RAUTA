import Combine
import Foundation
import UserNotifications
import WatchConnectivity

final class WatchSessionModel: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var snapshot: RautaWatchWorkoutSnapshot?
    @Published var loadKg: Double = 0
    @Published var reps: Int = 10
    @Published private(set) var isSaving = false
    @Published private(set) var connectionIssue: String?

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let pendingActionsKey = "rauta-watch-pending-actions"
    private var started = false

    override init() {
        super.init()
        start()
    }

    func start() {
        guard !started, WCSession.isSupported() else { return }
        started = true
        let session = WCSession.default
        session.delegate = self
        session.activate()
        applyContext(session.receivedApplicationContext)
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
        let message: [String: Any] = [RautaWatchMessageKey.action: data]
        let session = WCSession.default

        guard session.activationState == .activated else {
            persistPending(data)
            isSaving = false
            connectionIssue = "Set queued for iPhone"
            scheduleLocalRest(seconds: snapshot.restSeconds)
            return
        }

        if session.isReachable {
            session.sendMessage(message, replyHandler: { [weak self] reply in
                DispatchQueue.main.async {
                    self?.applyContext(reply)
                    self?.isSaving = false
                    if reply[RautaWatchMessageKey.ok] as? Bool != true {
                        self?.connectionIssue = "Could not save set"
                    }
                }
            }, errorHandler: { [weak self] _ in
                self?.queue(message, on: session, restSeconds: snapshot.restSeconds)
                DispatchQueue.main.async {
                    self?.isSaving = false
                    self?.connectionIssue = "Set queued for iPhone"
                }
            })
        } else {
            queue(message, on: session, restSeconds: snapshot.restSeconds)
            isSaving = false
            connectionIssue = "Set queued for iPhone"
        }
    }

    private func queue(_ message: [String: Any], on session: WCSession, restSeconds: Double) {
        try? session.updateApplicationContext(message)
        session.transferUserInfo(message)
        scheduleLocalRest(seconds: restSeconds)
    }

    private func persistPending(_ data: Data) {
        var pending = UserDefaults.standard.array(forKey: pendingActionsKey) as? [Data] ?? []
        pending.append(data)
        UserDefaults.standard.set(Array(pending.suffix(32)), forKey: pendingActionsKey)
    }

    private func flushPendingActions(on session: WCSession) {
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
            replyHandler: { [weak self] reply in
                DispatchQueue.main.async { self?.applyContext(reply) }
            },
            errorHandler: { _ in }
        )
    }

    private func applyContext(_ context: [String: Any]) {
        guard let data = context[RautaWatchMessageKey.snapshot] as? Data,
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

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated else { return }
        DispatchQueue.main.async { [weak self] in
            self?.flushPendingActions(on: session)
            self?.applyContext(session.receivedApplicationContext)
            self?.requestSnapshot()
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        DispatchQueue.main.async { [weak self] in self?.applyContext(applicationContext) }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        DispatchQueue.main.async { [weak self] in self?.applyContext(message) }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { [weak self] in self?.requestSnapshot() }
    }
}
