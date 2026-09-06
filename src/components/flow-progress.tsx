/** How far through a short sequence of pages you are. Shared by the exercise
 *  picker and by first-run setup, so a multi-step flow always reports itself
 *  the same way. */
export function FlowProgress({
  stage,
  steps = 3,
}: {
  stage: number
  steps?: number
}) {
  return (
    <div
      aria-label={`Step ${stage} of ${steps}`}
      aria-valuemax={steps}
      aria-valuemin={1}
      aria-valuenow={stage}
      className="flex items-center justify-center gap-1.5"
      role="progressbar"
    >
      {Array.from({ length: steps }, (_, index) => index + 1).map((step) => (
        <span
          aria-hidden="true"
          className={`h-1 rounded-full transition-[width,background-color] duration-250 ${
            step === stage
              ? "w-7 bg-primary-gradient"
              : step < stage
                ? "w-3.5 bg-primary/35"
                : "w-3.5 bg-white/10"
          }`}
          key={step}
        />
      ))}
    </div>
  )
}
