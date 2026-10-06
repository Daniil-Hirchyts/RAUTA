import Foundation
import Testing
@testable import Rauta

/// Who is heard when sounds want the same moment, and when the person's music
/// comes back up — worked out without a speaker.
@Suite("Sound arbiter")
struct SoundArbiterTests {
    private let start = Date(timeIntervalSince1970: 1_780_000_000)
    private func at(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }

    // MARK: When the music comes back

    /// Ticks a second apart and the sound at the end hold the music down once
    /// for the whole countdown; it comes back shortly after the end.
    @Test func aCountdownDipsTheMusicOnce() {
        var timeline = AudioTimeline()
        timeline.enter(.ducking)
        let restOver = 1.64
        timeline.hold(until: at(3 + restOver + AudioSessionStyle.ducking.linger))
        for (time, length) in [(0.0, 0.33), (1.0, 0.33), (2.0, 0.33), (3.0, restOver)] {
            timeline.schedule(length, on: AudioOutput.Player.cue, interrupting: true, at: at(time))
            #expect(!timeline.releaseIsDue(at: at(time + 0.9)))
        }
        #expect(!timeline.releaseIsDue(at: at(4.9)))
        #expect(timeline.releaseIsDue(at: at(3 + restOver + 0.41)))
    }

    /// The session is let go by the clock: no player has to report back.
    @Test func theSessionIsLetGoWithoutAnyCallback() {
        var timeline = AudioTimeline()
        timeline.enter(.mixed)
        let end = timeline.schedule(0.4, on: AudioOutput.Player.moment, interrupting: true, at: start)
        #expect(end == at(0.4))
        #expect(!timeline.releaseIsDue(at: at(1.3)))
        #expect(timeline.releaseIsDue(at: at(1.41)))
        timeline.released()
        #expect(!timeline.releaseIsDue(at: at(100)))
    }

    @Test func soundsQueuedOnOnePlayerHoldUntilTheLastEnds() {
        var timeline = AudioTimeline()
        timeline.enter(.ambient)
        timeline.schedule(0.5, on: 2, interrupting: false, at: start)
        #expect(timeline.schedule(0.5, on: 2, interrupting: false, at: at(0.1)) == at(1.0))
        #expect(timeline.schedule(0.5, on: 2, interrupting: true, at: at(0.2)) == at(0.7))
    }

    /// A rest skipped mid-countdown lets the music up once what is sounding
    /// is done, not at the end of the countdown it called off.
    @Test func aCalledOffCountdownLetsTheMusicBackUpSoon() {
        var timeline = AudioTimeline()
        timeline.enter(.ducking)
        timeline.hold(until: at(10))
        timeline.schedule(0.33, on: AudioOutput.Player.cue, interrupting: true, at: start)
        timeline.shortenHold(at: at(0.5))
        #expect(timeline.releaseIsDue(at: at(0.5 + AudioSessionStyle.ducking.linger + 0.01)))
    }

    @Test func onlyTheCountdownDucksTheMusic() {
        for sound in RautaSound.allCases {
            switch sound.channel {
            case .cue: #expect(sound.sessionStyle == .ducking)
            case .workout: #expect(sound.sessionStyle == .mixed)
            case .interface: #expect(sound.sessionStyle == .ambient)
            }
        }
        #expect(AudioTimeline().styleFor(.mixed) == .mixed)
        var held = AudioTimeline()
        held.enter(.ducking)
        #expect(held.styleFor(.ambient) == .ducking)
    }

    // MARK: Who is heard

    @Test func overACountdownOnlyItAndTheWorkoutsMomentsAreHeard() {
        var arbiter = SoundArbiter()
        arbiter.beginCountdown(until: at(5))
        #expect(arbiter.decide(.init(priority: .phrase, duration: 0.5), at: at(1)) == .drop)
        #expect(arbiter.decide(.init(priority: .touch, duration: 0.1), at: at(1.5)) == .drop)
        #expect(arbiter.decide(.init(priority: .cue, duration: 0.33), at: at(2)) == .play(silencing: nil))
        #expect(arbiter.decide(.init(priority: .moment, rank: 2, duration: 0.4), at: at(2.5)) == .play(silencing: nil))
        arbiter.endCountdown()
        #expect(arbiter.decide(.init(priority: .touch, duration: 0.1), at: at(6)) == .play(silencing: nil))
    }

    @Test func aCueSilencesWhatIsSoundingUnderIt() {
        var arbiter = SoundArbiter()
        #expect(arbiter.decide(.init(priority: .phrase, duration: 1), at: start) == .play(silencing: nil))
        #expect(arbiter.decide(.init(priority: .cue, duration: 0.33), at: at(0.2)) == .play(silencing: .cue))
        #expect(arbiter.decide(.init(priority: .touch, duration: 0.1), at: at(0.6)) == .play(silencing: nil))
    }

    @Test func aLesserSoundNeverTalksOverAGreaterOne() {
        var arbiter = SoundArbiter()
        _ = arbiter.decide(.init(priority: .moment, rank: 2, duration: 0.4), at: start)
        #expect(arbiter.decide(.init(priority: .phrase, duration: 0.5), at: at(0.1)) == .drop)
        #expect(arbiter.decide(.init(priority: .touch, duration: 0.1), at: at(0.2)) == .drop)
        #expect(arbiter.decide(.init(priority: .phrase, duration: 0.5), at: at(0.5)) == .play(silencing: nil))
    }

    /// A set logged that also finishes the exercise is heard as the exercise
    /// done; a rest starting with the set is folded into the set.
    @Test func twoMomentsInOneBreathAreHeardAsTheOneThatSaysMore() {
        var arbiter = SoundArbiter()
        func moment(_ sound: RautaSound) -> SoundArbiter.Request {
            .init(priority: sound.priority, rank: sound.momentRank, duration: 0.4)
        }
        #expect(arbiter.decide(moment(.setLogged), at: start) == .play(silencing: nil))
        #expect(arbiter.decide(moment(.restStart), at: at(0.05)) == .drop)
        #expect(arbiter.decide(moment(.exerciseDone), at: at(0.1)) == .play(silencing: .moment))
        #expect(arbiter.decide(moment(.setLogged), at: at(2)) == .play(silencing: nil))
    }

    @Test func aPhraseThatWaitsIsDroppedOverAnother() {
        var arbiter = SoundArbiter()
        _ = arbiter.decide(.init(priority: .phrase, duration: 0.6), at: start)
        #expect(arbiter.decide(.init(priority: .phrase, duration: 0.4, waitsForSilence: true), at: at(0.2)) == .drop)
        #expect(arbiter.decide(.init(priority: .phrase, duration: 0.4), at: at(0.3)) == .play(silencing: nil))
    }
}
