import CoreGraphics
import Foundation
import Testing
@testable import Rauta

/// RAUTA's personality as rules: who gets the floor, what a finger means,
/// where the eyes go and which mood shows. All of it is pure, so it is pinned
/// here rather than watched for in a frame loop.

@Suite("RAUTA scheduler")
struct RautaSchedulerTests {
    /// The app saying something — a finished week — is never cut off by the
    /// character having a thought of its own.
    @Test func idleNeverTalksOverTheApp() {
        let celebrated = RautaScheduler.request(RautaActivity(now: 0), source: .explicit, reaction: .celebrate, now: 1_000)
        #expect(celebrated.play == .celebrate)
        let idle = RautaScheduler.request(celebrated.activity, source: .ambient, reaction: .peek, now: 1_200)
        #expect(idle.play == nil)
        // Once the celebration has played out, idle may speak again.
        let later = RautaScheduler.request(celebrated.activity, source: .ambient, reaction: .peek, now: 2_600)
        #expect(later.play == .peek)
    }

    /// Blinks live on their own layer: they answer only to their own source's
    /// cooldown, whoever holds the floor.
    @Test func aBlinkIgnoresTheFloorButNotItsCooldown() {
        let held = RautaScheduler.request(RautaActivity(now: 0), source: .explicit, reaction: .celebrate, now: 1_000)
        let blink = RautaScheduler.request(held.activity, source: .ambient, reaction: .blink, now: 1_100)
        #expect(blink.play == .blink)
        let again = RautaScheduler.request(blink.activity, source: .ambient, reaction: .blink, now: 1_500)
        #expect(again.play == nil)
    }

    /// A source never blocks itself, only its cooldown does: a finger tapping
    /// again expects an answer again.
    @Test func aSourceWaitsOutOnlyItsOwnCooldown() {
        let first = RautaScheduler.request(RautaActivity(now: 0), source: .interaction, reaction: .tapped, now: 0)
        #expect(first.play == .tapped)
        #expect(RautaScheduler.request(first.activity, source: .interaction, reaction: .tapped, now: 100).play == nil)
        #expect(RautaScheduler.request(first.activity, source: .interaction, reaction: .laugh, now: 300).play == .laugh)
    }

    /// A knock straight after a startle lands at once, cooldown or not.
    @Test func anImpactCutsThroughAStartle() {
        let startled = RautaScheduler.request(RautaActivity(now: 0), source: .interaction, reaction: .surprise, now: 0)
        let knocked = RautaScheduler.request(startled.activity, source: .interaction, reaction: .recoil, now: 100)
        #expect(knocked.play == .recoil)
    }

    /// Anything happening pushes the character's own next thought back.
    @Test func eventsPutIdleOff() {
        let start = RautaActivity(now: 0)
        let saved = RautaScheduler.request(start, source: .explicit, reaction: .acknowledge, now: 5_000)
        #expect(saved.activity.ambientDueAt >= saved.activity.holdUntil + RAUTA_QUIET_AFTER_MS * 0.5)
        #expect(saved.activity.ambientDueAt > start.ambientDueAt)
    }
}

@Suite("RAUTA touch and gaze")
struct RautaTouchTests {
    /// Spun once too often in a row, it is dizzy rather than spinning again.
    @Test func spinningTooOftenMakesItDizzy() {
        #expect(RautaTouch.spin(1, rightward: true) == .spinRight)
        #expect(RautaTouch.spin(2, rightward: false) == .spinLeft)
        #expect(RautaTouch.spin(3, rightward: true) == .dizzy)
    }

    @Test func pokingEscalatesUntilItSulks() {
        let answers = (1...6).map(RautaTouch.reaction(forTap:))
        #expect(answers == [.tapped, .laugh, .surprise, .wobble, .frustrated, .frustrated])
        #expect(!RautaTouch.sulks(afterTap: 4))
        #expect(RautaTouch.sulks(afterTap: 5))
    }

    /// A long press let go is a spring released, but only where there is room
    /// to jump.
    @Test func aLongHoldJumpsOnlyAsAHero() {
        #expect(RautaTouch.release(afterHolding: 1.2, placement: .hero) == .celebrate)
        #expect(RautaTouch.release(afterHolding: 1.2, placement: .badge) == .gearUp)
        #expect(RautaTouch.release(afterHolding: 0.5, placement: .hero) == .gearUp)
    }

    /// Pulled, it stretches toward the finger and never leaves its place.
    @Test func theLeashGivesButNeverLetsGo() {
        let hero = RautaTouch.leash(CGSize(width: 2_000, height: -2_000), placement: .hero)
        #expect(hero.width > 15 && hero.width < 18)
        #expect(hero.height < -15 && hero.height > -18)
        let badge = RautaTouch.leash(CGSize(width: 2_000, height: 0), placement: .badge)
        #expect(badge.width < 7)
        #expect(RautaTouch.leash(.zero, placement: .hero) == .zero)
    }

    /// A tap elsewhere mostly earns a look and nothing more; close by, now and
    /// then a proper look over.
    @Test func aTouchElsewhereRarelyStartlesIt() {
        #expect(RautaTouch.noticeReaction(distance: 100, random: { 0.05 }) == .surprise)
        #expect(RautaTouch.noticeReaction(distance: 100, random: { 0.15 }) == .peek)
        #expect(RautaTouch.noticeReaction(distance: 100, random: { 0.30 }) == .blink)
        #expect(RautaTouch.noticeReaction(distance: 100, random: { 0.90 }) == nil)
        #expect(RautaTouch.noticeReaction(distance: 400, random: { 0.03 }) == .peek)
        #expect(RautaTouch.noticeReaction(distance: 400, random: { 0.20 }) == .blink)
        #expect(RautaTouch.noticeReaction(distance: 400, random: { 0.50 }) == nil)
        #expect(RautaTouch.noticeHold(distance: 100) > RautaTouch.noticeHold(distance: 400))
    }

    /// Soft saturation: beside it the eyes move a little, across the screen
    /// they reach the edge, and nothing in between jumps.
    @Test func theEyesFollowWithoutJumping() {
        let frame = CGRect(x: 100, y: 100, width: 100, height: 100)
        let centre = RautaGaze.toward(CGPoint(x: 150, y: 150), from: frame)
        #expect(centre.x == 0 && centre.y == 0)
        let near = RautaGaze.toward(CGPoint(x: 200, y: 150), from: frame)
        let far = RautaGaze.toward(CGPoint(x: 2_000, y: 150), from: frame)
        #expect(near.x > 0 && near.x < far.x && far.x < 1)
        let up = RautaGaze.toward(CGPoint(x: 150, y: -2_000), from: frame)
        #expect(up.y < 0 && up.y > -1)
    }

    @Test func restingEyesStayCloseToCentre() {
        for roll in [0.0, 0.5, 0.999] {
            let rest = RautaGaze.rest(random: { roll })
            #expect(abs(rest.x) <= 0.12 && abs(rest.y) <= 0.07)
        }
    }
}

@Suite("RAUTA mood and cues")
struct RautaMoodTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// Only a resting expression gives way to what is going on; a mood a
    /// screen chose on purpose is kept.
    @Test func aChosenMoodIsKept() {
        let context = RautaContext(workout: .paused, drift: .sleepy)
        #expect(context.mood(for: .excited, now: now) == .excited)
    }

    @Test func theWorkoutColoursARestingFace() {
        #expect(RautaContext(workout: .working).mood(for: .calm, now: now) == .focused)
        #expect(RautaContext(workout: .paused).mood(for: .calm, now: now) == .listening)
        #expect(RautaContext(workout: .resting(until: now.addingTimeInterval(30))).mood(for: .focused, now: now) == .recovering)
        // A rest that has run out is back to work.
        #expect(RautaContext(workout: .resting(until: now.addingTimeInterval(-1))).mood(for: .calm, now: now) == .focused)
        #expect(RautaContext(drift: .bored).mood(for: .calm, now: now) == .bored)
    }

    /// Proud for a while after a finished session, then back to normal.
    @Test func anAfterglowFades() {
        let glowing = RautaContext(workout: .working, afterglow: .proud, afterglowUntil: now.addingTimeInterval(60))
        #expect(glowing.mood(for: .calm, now: now) == .proud)
        #expect(glowing.mood(for: .calm, now: now.addingTimeInterval(61)) == .focused)
    }

    /// Bored, then sleepy, sooner at night, and never during a workout.
    @Test func leftAloneItDrifts() {
        #expect(RautaContext.drift(idleFor: 59, hour: 14, workout: .none) == nil)
        #expect(RautaContext.drift(idleFor: 60, hour: 14, workout: .none) == .bored)
        #expect(RautaContext.drift(idleFor: 180, hour: 14, workout: .none) == .sleepy)
        #expect(RautaContext.drift(idleFor: 30, hour: 23, workout: .none) == .bored)
        #expect(RautaContext.drift(idleFor: 90, hour: 2, workout: .none) == .sleepy)
        #expect(RautaContext.drift(idleFor: 600, hour: 14, workout: .working) == nil)
    }

    /// The rig numbers its moods in this order; the four added in rig 2.1
    /// come after the original sixteen, which keep their numbers.
    @Test func moodsKeepTheRigsNumbers() {
        #expect(RautaMood.calm.status == 0)
        #expect(RautaMood.listening.status == 15)
        #expect([RautaMood.determined, .exhausted, .recovering, .cheeky].map(\.status) == [16, 17, 18, 19])
    }

    /// The same cue twice in a row never gets the same answer twice.
    @MainActor
    @Test func aCueIsNotAnsweredTheSameWayTwice() {
        let first = RautaCues.pick(.setSaved, previous: 2, random: { 0 })
        let second = RautaCues.pick(.setSaved, previous: 0, random: { 0 })
        #expect(first.line != second.line)
    }
}
