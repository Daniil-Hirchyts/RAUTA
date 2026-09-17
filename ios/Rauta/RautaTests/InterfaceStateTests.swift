import SwiftUI
import Testing
@testable import Rauta

@Suite("Interface state")
struct InterfaceStateTests {
    @Test(arguments: [
        (CGFloat(9), Font.TextStyle.caption2),
        (12, .caption),
        (13, .footnote),
        (14, .subheadline),
        (16, .callout),
        (17, .body),
        (20, .title3),
        (22, .title2),
        (28, .title),
        (58, .largeTitle),
    ])
    func designSizesGrowWithTheNearestTextStyle(size: CGFloat, style: Font.TextStyle) {
        #expect(Theme.textStyle(for: size) == style)
    }

    @Test func titleBarHidesOnlyAfterADeliberateScroll() {
        let tracker = ScrollHideTracker()
        tracker.update(offset: 10, isScrollable: true)
        tracker.update(offset: 50, isScrollable: true)
        #expect(tracker.hidden == false)
        tracker.update(offset: 120, isScrollable: true)
        #expect(tracker.hidden)
    }

    @Test func titleBarReturnsOnAShortScrollBack() {
        let tracker = ScrollHideTracker()
        for offset in stride(from: 10.0, through: 300, by: 20) {
            tracker.update(offset: offset, isScrollable: true)
        }
        #expect(tracker.hidden)
        // The last offset was 290: 20 points back is not yet a decision…
        tracker.update(offset: 270, isScrollable: true)
        #expect(tracker.hidden)
        // …50 points back is.
        tracker.update(offset: 240, isScrollable: true)
        #expect(tracker.hidden == false)
    }

    @Test func titleBarIsAlwaysShownAtTheTopOrWithoutScrolling() {
        let tracker = ScrollHideTracker()
        for offset in stride(from: 10.0, through: 300, by: 20) {
            tracker.update(offset: offset, isScrollable: true)
        }
        tracker.update(offset: 300, isScrollable: false)
        #expect(tracker.hidden == false)
    }
}
