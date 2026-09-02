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
