**Source visual truth**

- `/var/folders/2t/p7wv0nhn1zl5qfwk2l9lhx7r0000gn/T/codex-clipboard-a421909c-efa0-4e41-9398-7249aec96039.png`
- Original source: 1290 × 219 px. Normalized focused comparison: 420 × 71 px.

**Implementation evidence**

- Full browser render: `/Users/hirchytsdaniil/Developer/Hobby/gym-lib/design-qa-implementation.png`
- Focused title bar crop: `/Users/hirchytsdaniil/Developer/Hobby/gym-lib/design-qa-header-fixed.jpg`
- Combined source/implementation comparison: `/Users/hirchytsdaniil/Developer/Hobby/gym-lib/design-qa-comparison.png`
- Browser viewport: 437 × 863 CSS px at 1× capture density.
- Implementation screenshot: 437 × 863 px. Header crop: 420 × 68 px.
- State: active-workout detail, title bar visible, no active scroll transition.

**Full-view comparison evidence**

- The implementation keeps the page-specific content and bottom tools visible while the title bar overlays the scrolling content.
- The title is visually centered independently of the asymmetric page actions. The left and right action slots are equal width.
- The header has no solid fill, divider, shadow, or bottom-corner treatment. A black-to-transparent gradient preserves legibility while allowing content to remain visible beneath it.

**Focused region comparison evidence**

- `design-qa-comparison.png` compares the reference title bar and the implementation at the same 420 px width.
- Both have a compact single-line centered title, one control at each edge, and nearly identical normalized bar height (71 px source, 68 px implementation).
- The implementation intentionally uses the app's dark theme, black fade, page-specific copy, and the existing Home-button control treatment instead of copying the reference's white palette and unrelated plus/heart actions.

**Required fidelity surfaces**

- Fonts and typography: passed. Geist Variable is preserved; all page titles now share a 20 px, 850-weight, compact centered style with controlled truncation.
- Spacing and layout rhythm: passed. Equal 44 px side tracks keep titles mathematically centered; the flow progress indicator sits directly below the title. The overlaid header translates upward on downward scroll and restores on upward scroll without changing content height.
- Colors and visual tokens: passed. The title section uses only a black-to-transparent gradient over the app surface. Theme differences from the white reference are intentional product constraints.
- Image quality and asset fidelity: passed. No image asset is required by the title-bar reference. Header actions use the project's installed Lucide icon library; existing exercise/equipment imagery remains unchanged.
- Copy and content: passed. My workouts, workout date, Muscles, Equipment, Exercises, and Settings use their correct page labels and requested controls.

**Interaction checks**

- Settings opens from My workouts and returns with the left Back control.
- The workout page exposes Back on the left and exactly one Share control on the right.
- The flow exposes Back on the left, Home on the right, and progress below the centered title.
- Muscles exposes Flip and conditional Clear tools at the bottom.
- Equipment exposes conditional Clear and `Show exercises (count)`; the action disables when no valid results can be shown.
- Exercises opens and closes Search entirely within the bottom tools.
- A scrollable exercise list hides the header while scrolling down and shows it while scrolling up. A non-scrollable header remains visible, covered by automated tests.
- Muscle and equipment Clear actions use the same `X` icon as Close.
- Primary cards and panels use a consistent 30 px radius, nested surfaces step down to 25 px or 20 px, drawers retain 35 px, and the outer shell remains the roundest surface at 55 px.
- Browser console errors/warnings checked: none.

**Comparison history**

- First pass P2: the past-workout footer still duplicated Share after Share was moved to the title bar.
- Fix: removed the remaining footer Share instance and retained the single right-side title action.
- Second-pass P2: the title region occupied layout space and could read as a solid band; 20–25 px primary card radii felt too square against the 55 px shell; Clear used an eraser while Close used an X.
- Fix: made the title bar an absolute gradient overlay with content scrolling beneath it, raised primary card/panel radii to 30 px while keeping nested surfaces smaller, and unified Clear with the X icon.
- Post-fix evidence: `design-qa-implementation.png` shows the gradient overlay and updated workout panel hierarchy; browser inspection confirms one Share workout control, 30 px primary cards, and X-icon Clear actions.

**Findings**

- No actionable P0, P1, or P2 differences remain.

**Open Questions**

- None.

**Implementation Checklist**

- Shared centered title bar: complete.
- Gradient-only title backdrop: complete.
- Scroll-aware animated visibility: complete.
- Page action mapping: complete.
- Flow progress and bottom-tool relocation: complete.
- Clear icon consistency: complete.
- Shell-relative radius hierarchy: complete.
- Automated and browser verification: complete.

**Follow-up Polish**

- None required for this pass.

final result: passed

---

# Exercise search dock correction — 2026-09-02

**Source visual truth**

- `/var/folders/2t/p7wv0nhn1zl5qfwk2l9lhx7r0000gn/T/codex-clipboard-2fa4707c-7dc6-4cd4-8627-3a3d784658af.png` shows the incorrect state: opening search replaces the shell command row.

**Implementation evidence**

- Corrected search-open capture: `/Users/hirchytsdaniil/Developer/Hobby/gym-lib/design-qa-exercise-search.jpg`.
- Side-by-side comparison: `/Users/hirchytsdaniil/Developer/Hobby/gym-lib/design-qa-search-comparison.jpg`.

**Focused verification**

- The search field now opens inside the rounded content surface, anchored over its own bottom gradient.
- Search, Favorites, and Select remain mounted in the gray shell command band.
- The Search control toggles the field and exposes its expanded state without replacing the command set.
- Content receives extra bottom clearance while search is open, so exercise cards remain scrollable above the field.
- The in-app browser interaction and focused App integration test both passed.

**Findings**

- No actionable P0, P1, or P2 differences remain for the requested placement correction.

final result: passed

---

# Picker controls and exercise favorite pass — 2026-09-02

**Source visual truth**

- Equipment: `/var/folders/2t/p7wv0nhn1zl5qfwk2l9lhx7r0000gn/T/codex-clipboard-c53af5a5-97ac-42d2-bbb6-16743a3dd160.png` (878 × 1724 px, approximately 2× density).
- Exercises: `/var/folders/2t/p7wv0nhn1zl5qfwk2l9lhx7r0000gn/T/codex-clipboard-49eb9bb8-2bf9-4354-a403-02efd8d5090d.png` (874 × 1728 px, approximately 2× density).
- Exercise detail: `/var/folders/2t/p7wv0nhn1zl5qfwk2l9lhx7r0000gn/T/codex-clipboard-12d69372-107a-42b3-af78-5c516ee7a30c.png` (872 × 1722 px, approximately 2× density).
- The screenshots define the existing visual system. The user's written deltas define the new control placement and states.

**Implementation evidence**

- Equipment editor: `/Users/hirchytsdaniil/Developer/Hobby/gym-lib/design-qa-equipment-editor.jpg`.
- Exercise selection dock: `/Users/hirchytsdaniil/Developer/Hobby/gym-lib/design-qa-exercise-selection.jpg`.
- Exercise detail: `/Users/hirchytsdaniil/Developer/Hobby/gym-lib/design-qa-exercise-detail.jpg`.
- Combined focused comparison: `/Users/hirchytsdaniil/Developer/Hobby/gym-lib/design-qa-controls-comparison.jpg`.
- Browser viewport and implementation captures: 441 × 863 CSS px at 1× density. The source screenshots were normalized by the comparison page to the same visible slots before review.

**States and interaction checks**

- Equipment: Body Weight selected, inline preset editor open. The plus control is in the gray command band, while the name field and confirm icon replace the preset chips inside the rounded surface.
- Exercises: selection mode open with one selected exercise. `Add to workout (1)` is inside the rounded surface over the bottom fade; Cancel, Search, and Favorites remain in the gray command band.
- Exercise detail: selectable detail page open. The favorite control uses the same 44 px bordered card surface, circular radius, and orange icon treatment as the back/header icon button.
- Preset input focus, save, preset restoration, selection-mode entry, exercise selection, detail navigation, and back/cancel behavior were exercised in the in-app browser.
- A hard reload at 2026-09-02T16:19:30Z produced only Vite connection and React DevTools informational messages; no subsequent runtime errors or warnings appeared.

**Full-view comparison evidence**

- The shell, surface radius, card grid, typography, exercise/equipment imagery, and bottom safe-area geometry remain unchanged from the references.
- The equipment and exercises actions move between the surface dock and command band without changing the stationary shell geometry.

**Focused region comparison evidence**

- `design-qa-controls-comparison.jpg` places each reference and implementation side by side, focused on the bottom control regions and exercise-detail header.
- Equipment shows the requested swap: presets are replaced by the input/confirm row, and plus moves beside the lower tools.
- Exercises shows the requested separation: the save action is over the content fade rather than in the gray command band.
- Exercise detail shows the favorite control matching the bordered header-button container instead of appearing as an uncontained glyph.

**Required fidelity surfaces**

- Fonts and typography: passed. Existing Geist sizes, weights, capitalization, and wrapping are unchanged; new labels use the existing button/input variants.
- Spacing and layout rhythm: passed. The new editor and selection action reuse the established surface dock insets, control heights, radii, and safe-area-aware command spacing.
- Colors and visual tokens: passed. New controls use the existing card, border, primary, muted, and shell tokens. The exercise action uses the same bottom surface fade as the presets.
- Image quality and asset fidelity: passed. Existing equipment and animated exercise media remain unchanged and continue to reserve their boxes before loading.
- Copy and content: passed. `Preset name`, `Save preset`, `Add to workout (count)`, and accessible control labels describe the new states accurately.

**Comparison history**

- Initial implementation comparison found no actionable P0, P1, or P2 mismatch. No post-capture visual correction was required.

**Findings**

- No actionable P0, P1, or P2 differences remain.

**Open Questions**

- None.

**Implementation Checklist**

- Move equipment plus into the command band: complete.
- Replace presets with inline name and confirm controls while creating: complete.
- Move exercise selection save action into the surface dock with a fade: complete.
- Match the detail favorite button to other header icon buttons: complete.
- Verify interactions, accessibility labels, console, automated tests, and production build: complete.

**Follow-up Polish**

- None required for this pass.

final result: passed
