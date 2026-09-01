# Design QA — compact workout date header

## Visual truth and evidence

- Source visual truth: `design-reference-compact-workout-header.png`
  (872 × 608 px, user-provided screenshot).
- Additional source direction: remove the edit icon, move Share to the bottom
  actions, and restyle the date as a smaller `September 1` label.
- Baseline implementation: `design-qa-compact-date-before.png`
  (437 × 863 px).
- Revised implementation: `design-qa-compact-date-after.png`
  (437 × 863 px).
- Full comparison: `design-qa-compact-date-comparison.png`
  (874 × 863 px).
- Focused header comparison: `design-qa-compact-date-focus.png`
  (872 × 304 px).
- Before/after comparison: `design-qa-compact-date-before-after.png`
  (874 × 863 px).
- CSS viewport: 437 × 863; device scale factor: 1. The source was a 2×
  partial-screen capture and was normalized from 872 × 608 to 436 × 304 for
  the focused comparison.
- Browser and route: Codex in-app browser at `http://127.0.0.1:5174/`, current
  workout detail with one exercise.

## Comparison history

### Iteration 1 — blocked findings

- P1, workout header: `Tuesday, September 1` used the primary display style and
  occupied most of the navigation row.
- P1, workout header: the pencil and Share actions remained in the header,
  contrary to the requested simplified hierarchy.
- P2, action placement: Share was separated from the other workout actions even
  though it belongs with Delete, Add, and Start.

Fixes applied:

- Added a month-and-day formatter and changed the visible heading to
  `September 1`.
- Restyled the date to 20px semibold Geist with restrained tracking; the full
  long date remains in the accessible edit label and the date itself remains
  tappable.
- Removed the pencil icon and the header Share button.
- Added the same orange Share icon button to the bottom row for upcoming, empty,
  active, and past workout states.

### Iteration 2 — passed

- The focused comparison shows a compact back/date header with no pencil or
  Share icon.
- The full and before/after comparisons show Share next to the other bottom
  actions without crowding or clipping the Start button.
- `September 1`, the exercise count, and the exercise card remain fully readable
  at 437px.

## Required fidelity surfaces

- Fonts and typography: passed. The compact 20px semibold date is visibly
  distinct from the previous display heading while preserving Geist and text
  rendering quality.
- Spacing and layout rhythm: passed. Removing the right header action creates
  more breathing room; four bottom actions fit within the safe action row.
- Colors and visual tokens: passed. Back, Share, Add, Delete, and reorder icons
  continue to use the orange primary token with sufficient contrast.
- Image quality and asset fidelity: passed. The exercise image and its crop are
  unchanged and remain sharp; no placeholder assets were introduced.
- Copy and content: passed. The visible title is `September 1`; the full date is
  retained for accessibility and the exercise metadata is unchanged.

## Interaction and runtime checks

- Tapping the compact date opened the Change date drawer.
- Share is present once in the bottom footer and absent from the header.
- Existing Share loading behavior is covered by the workout-detail test.
- Browser console checked after the revised capture.

final result: passed
