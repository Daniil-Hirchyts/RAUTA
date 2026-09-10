# Workout detail visual QA

Source visual truth:

- Planned state: `/var/folders/2t/p7wv0nhn1zl5qfwk2l9lhx7r0000gn/T/codex-clipboard-f7047fa3-0d98-4fe6-a83b-a6f9c94b839c.png` (940 × 1630 px)
- Completed state: `/var/folders/2t/p7wv0nhn1zl5qfwk2l9lhx7r0000gn/T/codex-clipboard-f9e9a811-f80d-444d-89f5-5ce475035b98.png` (956 × 1650 px)
- Tabs reference: `/var/folders/2t/p7wv0nhn1zl5qfwk2l9lhx7r0000gn/T/codex-clipboard-73862c35-0817-41cf-920f-9291328a72e7.png` (902 × 128 px)
- Companion layout defects: `/var/folders/2t/p7wv0nhn1zl5qfwk2l9lhx7r0000gn/T/codex-clipboard-1c22b487-abf3-4fa3-9877-e31e521ae7b9.png`, `/var/folders/2t/p7wv0nhn1zl5qfwk2l9lhx7r0000gn/T/codex-clipboard-7b17dfdd-2d3a-4fd9-8579-61dce9530c6b.png`, and `/var/folders/2t/p7wv0nhn1zl5qfwk2l9lhx7r0000gn/T/codex-clipboard-2148a29a-4b2d-469f-b867-55ad7a8a885f.png`

Implementation evidence:

- Browser-rendered planned and completed captures were taken from the Codex Desktop in-app browser at `http://localhost:4173/` and emitted in the verification log. The CUA capture is 445 × 768 CSS px at device scale 1; it is not persisted as a workspace file by the browser surface.
- The source screenshots were compared at the same portrait ratio after scale normalization. The implementation capture was inspected as app content only, without browser chrome.

States and interactions checked:

- Planned workout detail with two or more exercise modules and Start workout.
- Completed workout detail with completion summary, completed exercise marks, and Copy to today.
- Next/Past tabs, including switching to Past and opening a completed workout.
- Start workout countdown, active workout entry, exercise completion, finish confirmation, and copy to today.
- Existing exercise demonstration and detail buttons remain present in both states.

**Findings**

- The first implementation had equal weight metric tiles, repeated generic cards, and detached prescription chips. The revised implementation uses one dominant readout, a two-column luminous metric rail, a numbered exercise sequence, and an integrated prescription rail.
- The first implementation used the wrong display face for numeric data. Numeric values now use the existing `Matrix Sans Print` font through the workout detail styles; labels and exercise names remain in the regular app font.
- The status icon no longer sits inside a bordered container. The exercise media background uses the neutral dark card treatment from the reference direction instead of the orange-tinted field introduced during the first pass.
- The Next/Past tabs had no matching `.t-tabs` styles and rendered as loose text. The tab bar now has a working sliding pill, visible selected state, readable count badges, and verified tab switching.
- The latest polish pass removes synthetic bold from the display face, keeps exercise numbers in the normal UI face, makes the tab bar span the content width, increases the shared Next/Past exercise module height, and adds breathing room between prescription fields.
- The RAUTA companion now animates its own measured height when a message appears or clears. Bottom messages use the full panel width above the timer while only the lower controls reserve room for the character, preventing the text from being pushed sideways.
- Shared RAUTA picker actions now measure the active page layer and its header instead of the detached companion host. The Muscles and Equipment actions clear their centered titles and keep the same placement during page transitions.
- Home resume guidance reserves the character footprint before laying out its copy, so the first words remain visible. Active-workout guidance remains centered above the timer, then collapses into the compact timer bar.
- The profile introduction no longer repeats the RAUTA name in its message copy.

**Required fidelity surfaces**

- Fonts and typography: Matrix Sans Print is limited to numeric readouts and exercise ordering; Geist remains the primary UI face. The large status values, compact prescription values, labels, and exercise names keep the intended hierarchy.
- Spacing and layout rhythm: The overview is a single framed instrument with a lower data rail. Exercise rows use a consistent shared radius, image field, content area, and prescription divider. Persistent controls remain visible at the bottom of the phone viewport.
- Colors and tokens: Planned state keeps the orange primary signal; completed state uses the existing success token for its readout and marks. The implementation uses the existing warm black, card, border, and gradient tokens.
- Image quality and asset fidelity: Existing exercise demonstration assets are retained and remain interactive. No reference artwork was replaced with placeholder imagery or custom drawings.
- Copy and content: Existing labels and actions are preserved. The redesign adds visual hierarchy and grouping without introducing explanatory paragraphs.

**Comparison history**

1. Initial pass: the page still read as a generic card stack with flat metrics and a Doto-based display treatment.
2. Fixes: introduced the instrument overview, prescription rails, numbered exercise modules, status-aware completed styling, and the tab component styling.
3. Final pass: switched display values to the existing Matrix Sans Print face without synthetic bold, kept exercise numbers in the regular UI font, removed the bordered icon wrapper, restored neutral exercise media, expanded the shared exercise modules, widened the tabs, increased prescription spacing, and verified planned/completed captures plus Next/Past switching. No actionable P0, P1, or P2 findings remain.
4. Companion pass: added morphing panel height transitions for message appearance and disappearance, centered bottom messages above the timer, and rechecked the top onboarding message and active workout states in the local preview. No actionable P0, P1, or P2 findings remain.
5. Companion layout correction: resolved the detached-host measurement bug, rechecked the home resume card and Muscles picker, and captured both expanded and compact active-workout states. Equipment uses the same verified picker placement path. No actionable P0, P1, or P2 findings remain.
6. Home companion scale: reduced the resume-card RAUTA artboard from 140 px to 104 px, matching the compact companion scale used in the rest of the app while preserving the corrected copy clearance and panel animation.
7. Companion alignment: standardized top-panel RAUTA instances at 72 px, retained the larger context-specific bottom-panel sizes, lifted both resting positions, centered message copy with symmetric character clearance, added a 12 px gap before bottom controls, and changed the picker home action to a full-width ghost treatment.
8. Expanded bottom panel: actions grow above the fixed character-and-dialog row, preserving their closed-state position while giving every control the full panel width.
9. Running-workout controls and card legibility: the persistent CTA becomes Resume workout during a running session, RAUTA no longer duplicates that action, and workout-card body maps use a larger, higher-contrast treatment.
10. Stable transient dialog: removed the parent layout transform so a temporary message expands above the active timer without translating RAUTA, elapsed time, or playback controls.
11. Bottom-edge pinning: the active timer footer is fixed to the panel's bottom edge with reserved flow space above it, keeping RAUTA, elapsed time, and playback controls at the same coordinates before, during, and after a transient message.
12. RAUTA behavior pass: confirmed the bundled Rive asset matches the current private `kettlebell-bot` main commit and kept its full 16-mood/17-trigger contract. Idle behavior now draws from a broader weighted set without consecutive repeats; mouse hover and mood-sensitive intensity reach the rig; taps, gentle returns, directional throws, and collisions rotate through distinct reactions and short remarks. Workout set, exercise, timer, start, finish, and blocked actions emit semantic cues, so RAUTA answers the action that occurred rather than playing one generic acknowledgement. Static layout is unchanged by this pass.

**Open Questions**

- The reference and implementation use different exercise content, so image pose and name wrapping are expected to vary while the asset treatment and layout remain aligned.

**Follow-up Polish**

- Motion behavior is covered through the rig-input and timing tests because a still capture cannot prove a Rive sequence. Live visual inspection was unavailable for this final pass while the host Mac was locked; the local preview remained healthy at `http://localhost:4173/`, the production build completed, and all 654 repository tests passed.

final result: passed
