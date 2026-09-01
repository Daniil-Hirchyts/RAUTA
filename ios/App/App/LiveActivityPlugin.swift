import Capacitor
import Foundation

/// Bridges the workout store's ActivityKit lifecycle — start, update, end —
/// into the web layer. The contract on the JavaScript side is
/// `src/lib/live-activity.ts`; the payload it sends is documented there.
///
/// Nothing here throws back into the web view for reasons the user cannot act
/// on: an unsupported OS version and disabled Live Activities both resolve,
/// because a missing Lock Screen card must never interrupt a workout.
@objc(LiveActivityPlugin)
public class LiveActivityPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "LiveActivityPlugin"
    public let jsName = "LiveActivity"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "isSupported", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "start", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "update", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "end", returnType: CAPPluginReturnPromise)
    ]

    @objc func isSupported(_ call: CAPPluginCall) {
        guard #available(iOS 16.2, *) else {
            call.resolve(["supported": false])
            return
        }
        call.resolve(["supported": WorkoutLiveActivity.isEnabled])
    }

    @objc func start(_ call: CAPPluginCall) {
        guard #available(iOS 16.2, *), WorkoutLiveActivity.isEnabled else {
            call.resolve()
            return
        }

        do {
            try WorkoutLiveActivity.start(
                attributes: attributes(from: call),
                state: contentState(from: call)
            )
            call.resolve()
        } catch {
            call.reject("Could not start the workout Live Activity", nil, error)
        }
    }

    @objc func update(_ call: CAPPluginCall) {
        guard #available(iOS 16.2, *) else {
            call.resolve()
            return
        }

        WorkoutLiveActivity.update(state: contentState(from: call))
        call.resolve()
    }

    @objc func end(_ call: CAPPluginCall) {
        guard #available(iOS 16.2, *) else {
            call.resolve()
            return
        }

        WorkoutLiveActivity.end(
            state: contentState(from: call),
            dismissImmediately: call.getBool("dismissImmediately", true)
        )
        call.resolve()
    }

    // MARK: - Payload

    @available(iOS 16.1, *)
    private func attributes(from call: CAPPluginCall) -> WorkoutActivityAttributes {
        WorkoutActivityAttributes(
            workoutId: call.getString("workoutId", ""),
            workoutName: call.getString("workoutName", "Workout"),
            workoutDate: call.getString("workoutDate", "")
        )
    }

    @available(iOS 16.1, *)
    private func contentState(from call: CAPPluginCall) -> WorkoutActivityAttributes.ContentState {
        let timerStart = call.getDouble("timerStartEpochMs", 0)

        return WorkoutActivityAttributes.ContentState(
            exerciseName: call.getString("exerciseName", ""),
            // Preparing the stills is a few milliseconds of pixel work that
            // only happens the first time an exercise appears; afterwards the
            // PNGs are already in the shared container and this just picks the
            // one this update of the card steps to.
            exerciseFrame: ExerciseFrameRenderer.prepareFrame(
                exerciseId: call.getString("exerciseId", ""),
                frameIndex: call.getInt("frameIndex", 0)
            ) ?? "",
            muscleMapFrame: MuscleMapStore.prepareMap(
                key: call.getString("muscleMapKey", ""),
                base64Png: call.getString("muscleMapPng", "")
            ) ?? "",
            completedCount: call.getInt("completedCount", 0),
            totalCount: call.getInt("totalCount", 0),
            timerStart: timerStart > 0
                ? Date(timeIntervalSince1970: timerStart / 1000)
                : nil,
            elapsed: call.getDouble("elapsedMs", 0) / 1000,
            isPaused: call.getBool("isPaused", false)
        )
    }
}
