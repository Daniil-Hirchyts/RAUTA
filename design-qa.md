# Design QA

- Source visual truth: `/var/folders/2t/p7wv0nhn1zl5qfwk2l9lhx7r0000gn/T/codex-clipboard-151ac58e-d6ae-44fd-9a1a-7a7ead592732.png` (312 × 404) and `conversation://browser-comments/1-4` (441 × 863 annotated mobile viewport).
- Web implementation: `cua://iab/tab/2` (430 px app frame).
- Native implementation: `/tmp/gym-lib-native-final.png` and `/tmp/gym-lib-native-exercises-qa.png` (iPhone 16 Simulator, 393 × 852 points at 3×).
- Comparison method: source and implementation captures were inspected together; browser chrome and canvas outside the app shell were excluded.

## Findings and fixes

- P1: iOS exercise media rendered black because `mix-blend-mode` depended on a WKWebView backdrop. Replaced it with a deterministic white-to-alpha SVG key. The native captures now show continuous card surfaces without black rectangles.
- P2: the Hammer artwork's authored dark field differed from the equipment-card footer. Both regions now use the sampled equipment surface token, eliminating the visible seam while preserving centered cover framing.
- P2: the favorites control could receive a stronger active border. It now inherits the shared icon-button variant and keeps the same border in active and inactive states; only its fill changes.
- P2: conditional footer controls snapped between layouts. Optional buttons now animate through a persistent width/opacity slot: the primary action shrinks before cancel appears and cancel disappears before the action expands. Label/count changes keep the same primary button node and do not restart the layout animation.
- P2: the New workout add icon used rounded-square geometry. It is now circular.
- Typography, shell geometry, touch-target sizing, copy, card alignment, image cropping, and reduced-motion behavior were checked at the final pass.
- No P0, P1, or P2 discrepancies remain in the requested areas.

final result: passed
