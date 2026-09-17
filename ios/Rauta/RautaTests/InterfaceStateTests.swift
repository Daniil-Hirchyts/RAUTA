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

    /// SwiftUI's asynchronous renderer resolves colours off the main thread;
    /// a provider isolated to the main actor traps there. Resolving the theme
    /// colours from a concurrent function is that render path in miniature.
    @Test func themeColoursResolveOffTheMainActor() async {
        let adaptive = UIColor(light: .white, dark: .black)
        let mixed = UIColor(Theme.mix(Theme.primary, Theme.card, 0.5))
        let (dark, blend) = await Self.resolveOffMain(adaptive, mixed)
        #expect(dark == UIColor.black.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)))
        #expect(blend.cgColor.alpha > 0)
    }

    @concurrent
    private static func resolveOffMain(_ adaptive: UIColor, _ mixed: UIColor) async -> (UIColor, UIColor) {
        let traits = UITraitCollection(userInterfaceStyle: .dark)
        return (adaptive.resolvedColor(with: traits), mixed.resolvedColor(with: traits))
    }
}
