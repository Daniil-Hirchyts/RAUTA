# Summary Dashboard QA — 2026-09-12

**Comparison Target**

- Source visual truth: `/var/folders/2t/p7wv0nhn1zl5qfwk2l9lhx7r0000gn/T/codex-clipboard-3627d0a1-03e1-411f-a31f-251645548d6c.png`, with the latest muscle-widget edit targets in `/var/folders/2t/p7wv0nhn1zl5qfwk2l9lhx7r0000gn/T/codex-clipboard-f0199a42-ce3e-415f-b38c-96b44f46d981.png` and `/var/folders/2t/p7wv0nhn1zl5qfwk2l9lhx7r0000gn/T/codex-clipboard-f1968f19-2578-42f2-8e04-76a0c0340b19.png`.
- Implementation screenshots: `/tmp/rauta-summary-uniform.jpg`, `/tmp/rauta-summary-bottom-clearance.jpg`, and `/tmp/rauta-summary-heatmap-red.jpg`.
- Latest focused comparison: `/tmp/rauta-summary-heatmap-red-comparison.png`.
- Viewport: iPhone 18 Pro simulator, portrait, iOS 27.0; native capture is 368 × 800 pixels.
- Source dimensions: the dashboard reference is 1290 × 2796 pixels; the latest widget captures are 490 × 440 and 282 × 96 pixels. The simulator implementation is 368 × 800 pixels. The focused comparison normalizes both widget crops to 490 pixels wide on a 1000 × 464 AppKit canvas.
- State: Summary tab with five September completions, a three-day streak, month statistics, set-driven muscle intensity, and the existing completed-workout accessory visible.
- Scope note: the Apple Fitness screenshot is a directional reference for hierarchy, square cards, and dashboard density. Product-specific content, typography, colors, anatomy artwork, and navigation intentionally remain Rauta-native.

**Full-view comparison evidence**

- The source's large lead card followed by a two-column square-card grid is preserved: Rauta's streak card leads, then monthly workout and duration cards use the same compact dashboard rhythm.
- The implementation extends the source pattern with a full-width anatomy card immediately below the grid, keeping the requested monthly muscle map in the same visual system.
- The persistent bottom navigation and completed-workout accessory remain inside the safe area; the Summary content scrolls far enough to reveal the complete heatmap and intensity key.

**Focused region comparison evidence**

- `/tmp/rauta-summary-heatmap-red-comparison.png` verifies that the widget no longer shows the `WORKING SETS`, `FRONT`, or `BACK` captions; the body regions no longer glow; and the intensity key now contains five evenly spaced red levels.
- `/tmp/rauta-summary-bottom-clearance.jpg` verifies the complete anatomy figures, four strongest-muscle rows, values, and low-to-high key after scrolling above the persistent bottom controls.
- The metric grid was inspected at native capture size. Both cards remain equal and square, long duration values scale without clipping, and the weekly marks stay centered and legible.

**Findings**

- No actionable P0, P1, or P2 differences remain.
- Fonts and typography: the app's Geist and Matrix readout fonts preserve Rauta's hierarchy while echoing the reference's bold labels and colorful numeric emphasis. Values and supporting copy fit without truncation at the tested viewport.
- Spacing and layout rhythm: 12-point section spacing, 10-point grid gutters, equal square cards, and 30–36-point continuous radii create a consistent compact dashboard. No content overlaps or clips when the page is scrolled.
- Colors and visual tokens: every summary panel uses the same opaque `Theme.card` surface with no panel border. The muscle widget now uses `Theme.ember`—the existing “MUSCLES TRAINED” red—for anatomy intensity, row bars, values, and the five-step key; no orange accent or selection glow remains in that widget.
- Image quality and asset fidelity: the heatmap reuses the app's bundled vector anatomy paths, so front/back figures remain sharp and correctly masked at simulator density; no placeholder imagery was introduced.
- Copy and content: “Workouts,” “Training time,” “Muscles trained,” month name, average duration, strongest-muscle values, and the intensity key are concise and understandable. Redundant `WORKING SETS`, `FRONT`, and `BACK` captions were removed as requested.
- Icons and behavior: SF Symbols match the existing icon family. The screen scrolls correctly, the existing Settings and tab actions remain available, and the summary values update from persisted workout/history publishers.
- Accessibility: metric cards combine their child labels for VoiceOver, chart decoration is hidden, and the body map has a useful trained-muscle summary label. The empty map includes an explanatory state.

**Open Questions**

- No blocking questions. The active simulator's unusually long stored workout makes the duration card show 24h 16m; this is real persisted data and the card handles it without layout failure.

**Comparison History**

- Initial P2 polish: weekly activity marks expanded to round dots, and a long average duration rendered as “364 min average.”
- Fixes: constrained weekly marks to six-point vertical capsules and reused the compact hours/minutes formatter for averages.
- Post-fix evidence: `/tmp/rauta-summary-top.jpg` and `/tmp/rauta-summary-comparison.png` show slender weekly bars and the readable “6h 4m average” value with no clipping.
- Follow-up direction: the user requested simple panel backgrounds and more of Rauta's established colors instead of Liquid Glass.
- Fixes: removed glass effects, glass containers, radial sheen, and top specular highlights from the streak, metric, and muscle panels; replaced them with opaque theme-card fills and semantic orange, gold, lime, rust, and ember accents.
- Post-fix evidence: `/tmp/rauta-summary-solid.jpg` and `/tmp/rauta-summary-solid-comparison.png` show the flatter card treatment and distinct metric colors without changing layout or readability.
- Final direction: the user requested one identical background color across all panels, no panel borders, and more room to reach the bottom of the page.
- Fixes: unified the streak, metric, and muscle panels on `Theme.card`, removed their strokes, and increased the Summary scroll tail from 112 to 220 points.
- Final evidence: `/tmp/rauta-summary-uniform.jpg` shows the unified surfaces, and `/tmp/rauta-summary-bottom-clearance.jpg` shows the full muscle card and legend comfortably above the persistent bottom controls.
- Latest direction: remove the muscle highlight glow and redundant labels, correct the incomplete intensity scale, and replace orange inside the widget with the title's red accent.
- Fixes: added a summary-only no-glow anatomy configuration, switched the widget's selected regions and quantitative accents to `Theme.ember`, removed `WORKING SETS` plus front/back captions, and expanded the key from four fixed-width blocks to five flexible levels.
- Post-fix evidence: `/tmp/rauta-summary-heatmap-red-comparison.png` shows the requested labels absent, five complete intensity steps, and one consistent red highlight family with no muscle glow.

**Implementation Checklist**

- [x] Keep the existing streak card as the lead summary surface.
- [x] Add equal square workout-count and training-time cards.
- [x] Filter metrics to the current calendar month.
- [x] Render weekly activity bars for both metrics.
- [x] Shade front and back anatomy from effective working-set volume.
- [x] Fall back to completed-exercise involvement for legacy, set-less workouts.
- [x] Include strongest-muscle values, intensity legend, empty state, and accessibility labels.
- [x] Use a five-level red-only intensity scale without anatomy glow or redundant orientation captions.
- [x] Verify scrolling and the persistent bottom controls on an iPhone simulator.

**Follow-up Polish**

- No blocking visual polish remains. A future detail view could let users tap a muscle to inspect its contributing workouts, but that is outside this request.

---

## Previous Active Workout QA Report

**Comparison Target**

- Source visual truth:
  - `/var/folders/2t/p7wv0nhn1zl5qfwk2l9lhx7r0000gn/T/codex-clipboard-aa4f7ad8-92fe-4f30-b60b-5c66fa8da032.png`
  - `/var/folders/2t/p7wv0nhn1zl5qfwk2l9lhx7r0000gn/T/codex-clipboard-f87c7951-5a2f-4c8f-98c1-f8b944dcfdb3.png`
  - `/var/folders/2t/p7wv0nhn1zl5qfwk2l9lhx7r0000gn/T/codex-clipboard-a5a0a34d-595d-4163-b9db-fb50264bd3ce.png`
- Implementation screenshots:
  - `/tmp/rauta-active-redesign-closed.png`
  - `/tmp/rauta-active-redesign-drawer.png`
- Combined comparison: `/tmp/rauta-active-qa-comparison.png`
- Viewport: iPhone 18 Pro simulator, portrait, iOS 27.0.
- Source dimensions: 696 × 1368, 694 × 1394, and 696 × 1392 pixels.
- Implementation dimensions: 1206 × 2622 pixels at simulator capture density.
- Density normalization: source and implementation were fit proportionally into equal comparison columns. Device-frame and capture-density differences were excluded from layout findings.
- States: active workout with drawer closed; active exercise drawer open.

**Full-view comparison evidence**

- The closed state preserves the source hierarchy: workout header, running summary, exercise list, current-exercise accessory, native navigation, and separate Rauta control.
- The open state follows the source drawer composition: grabber, exercise media and title, set log, controls, and the completion action in a bottom-origin full-height surface.
- The implementation uses the product's existing warm dark palette, orange emphasis, exercise imagery, typography hierarchy, radii, and glass surfaces.

**Focused region comparison evidence**

- Bottom controls were inspected separately in the combined comparison. The current-exercise accessory sits directly above the native tab bar in its expanded placement and adapts when the tab bar minimizes.
- The drawer header and closed accessory use a shared matched-geometry identity, creating a continuous visual link during opening and closing.
- Exercise media and Rauta use existing app assets; no placeholder or approximated artwork was introduced.

**Findings**

- No actionable P0, P1, or P2 differences remain.
- Fonts and typography: existing app fonts, weights, truncation, and hierarchy remain consistent with the supplied mockups.
- Spacing and layout rhythm: persistent controls remain inside safe areas; cards, accessory, navigation, and drawer retain clear separation and consistent radii.
- Colors and visual tokens: existing brown-black surfaces, glass treatment, orange accent, and secondary text colors match the established app language.
- Image quality and asset fidelity: existing exercise and Rauta assets remain sharp and correctly masked at simulator density.
- Copy and content: labels reflect the live workout model. Differences in duration, exercise name, and set values are expected because the simulator uses current stored workout data.

**Open Questions**

- Native tab-bar minimization could not be gesture-tested while the Mac session was locked. The implementation uses the official iOS 27 `tabBarMinimizeBehavior(.onScrollDown)` and `tabViewBottomAccessory` APIs, and both static placements compile and render.

**Comparison History**

- Initial implementation issue: the active workout used a separate page flow and hid the persistent bottom navigation.
- Fix: replaced the iOS 27 active-workout path with a single scrolling overview inside the native tab shell, added a native bottom accessory for the current exercise, and moved the current-exercise controls into a linked drawer.
- Post-fix evidence: `/tmp/rauta-active-redesign-closed.png`, `/tmp/rauta-active-redesign-drawer.png`, and `/tmp/rauta-active-qa-comparison.png` show the corrected closed and open states.

**Implementation Checklist**

- [x] Keep the native bottom navigation visible during a running workout.
- [x] Keep the workout overview and exercise list on one page.
- [x] Open the current exercise from the bottom exercise accessory.
- [x] Morph navigation between full and minimized native states.
- [x] Animate accessory-to-drawer movement and bottom-origin opening/closing.
- [x] Preserve the separate Rauta control and menu.

**Follow-up Polish**

- No blocking visual polish remains.

previous final result: passed

final result: passed
