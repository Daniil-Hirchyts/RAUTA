/** Hidden SVG filter defs shared by every exercise animation. */
export function SvgFilterDefs() {
  return (
    <svg
      aria-hidden="true"
      className="absolute h-0 w-0 overflow-hidden"
      focusable="false"
    >
      <defs>
        {/* The source animations have a white canvas. Converting that canvas
            to alpha is self-contained and does not ask WKWebView to blend
            every animated card with the scrolling surface behind it. */}
        <filter colorInterpolationFilters="sRGB" id="exercise-background-key">
          <feColorMatrix
            type="matrix"
            values="
              1 0 0 0 0
              0 1 0 0 0
              0 0 1 0 0
              -5 -5 -5 14.7 0
            "
          />
        </filter>
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
