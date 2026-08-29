/**
 * Hidden SVG filter defs, mounted once. `feConvolveMatrix` applies a gentle
 * unsharp-mask kernel live in the browser — it never touches the stored GIF
 * files, it just renders them crisper. Referenced via
 * `EXERCISE_ANIMATION_FILTER`
 * in `@/lib/visuals`.
 */
export function SvgFilterDefs() {
  return (
    <svg
      aria-hidden="true"
      className="absolute h-0 w-0 overflow-hidden"
      focusable="false"
    >
      <defs>
        <filter colorInterpolationFilters="sRGB" id="exercise-gif-sharpen">
          <feConvolveMatrix
            kernelMatrix="0 -0.5 0 -0.5 3 -0.5 0 -0.5 0"
            order="3"
            preserveAlpha="true"
          />
        </filter>
      </defs>
    </svg>
  )
}
