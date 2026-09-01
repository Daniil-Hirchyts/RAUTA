# App shell audit

## Scope

Combined UX and accessibility review of the top-level mobile shell at 390 ×
844, with an additional responsive check at 320 × 568. The reference was
`IMG_9186.PNG`; before-state captures are in `../app-shell-before/`.

## User goal

Keep app content inside a slightly lighter rounded surface, place bottom
controls on the true-black outer shell, avoid harsh clipping while content
scrolls, and make each title area a fully rounded inset element.

## Reviewed steps

1. **Workouts — healthy.** The title is an inset card, the list scrolls in its
   own viewport, and the final visible row fades before the shell curve.
2. **Settings — healthy.** The long form scrolls independently beneath a
   rounded title card; the lower section no longer meets the outer mask with a
   hard crop.
3. **Muscle selection — healthy.** The muscle map stays fully contained while
   the progress/title block follows the same inset header treatment.
4. **Workout detail — healthy.** Stats and exercise rows scroll independently;
   bottom actions remain outside the surface on black.
5. **Equipment selection — healthy.** Grid rows fade smoothly at the scrolling
   edge and can continue beneath a stable inset header.
6. **Exercise results — healthy.** Search and result cards share the same scroll
   behavior; title/count spacing also holds at 320 px width.
7. **Exercise drawer — healthy.** The drawer remains a separate overlay with its
   own scroll and bottom controls; the new app shell does not interfere with it.

## Accessibility notes

- Existing headings, landmarks, labels, pressed states, and button semantics
  remain present in the captured DOM.
- Bottom padding lets the final row move above the visual fade instead of
  becoming permanently obscured.
- The compact-width check found and fixed title/count crowding.

## Evidence limits

Screenshots and DOM inspection do not establish full WCAG compliance. A real
iOS device or Simulator is still the authoritative check for Dynamic Island,
safe-area, VoiceOver, and large Dynamic Type behavior.
