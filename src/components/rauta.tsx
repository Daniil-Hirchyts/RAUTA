import { lazy, Suspense } from "react"
import { motion, useReducedMotion } from "motion/react"
import { usePageLayer } from "@/hooks/use-app-shell"
import { triggerHaptic } from "@/lib/haptics"

const AnimatedRauta = lazy(() => import("./rauta-runtime"))
export type RautaMood =
  | "calm"
  | "curious"
  | "listening"
  | "focused"
  | "happy"
  | "proud"
  | "working"
  | "blocked"
export type RautaProps = {
  mood?: RautaMood
  size?: number
  onActivate?: () => void
  label?: string
  reactionKey?: string
}

export function RautaStill() {
  return (
    <img
      src="/rauta/rauta.svg"
      alt=""
      className="h-full w-full object-contain"
    />
  )
}

/** Character rendering is optional; every action also works without WebAssembly. */
export function Rauta({
  size = 104,
  label = "Interact with RAUTA",
  onActivate,
  ...props
}: RautaProps) {
  const reduced = useReducedMotion()
  const { active } = usePageLayer()
  const activate = () => {
    triggerHaptic("selection")
    onActivate?.()
  }
  return (
    <motion.div
      animate={
        reduced || !active
          ? undefined
          : { y: [0, -5, 0, -2, 0], rotate: [0, -1.8, 0.8, 0, 0] }
      }
      className="relative z-10 shrink-0 touch-none"
      drag={reduced || !active ? false : true}
      dragConstraints={{ bottom: 24, left: -38, right: 38, top: -24 }}
      dragElastic={0.16}
      dragMomentum={false}
      dragSnapToOrigin
      onDragEnd={() => triggerHaptic("selection")}
      style={{ width: size, height: size }}
      transition={
        reduced || !active
          ? undefined
          : {
              duration: 4.2,
              ease: "easeInOut",
              repeat: Infinity,
              repeatDelay: 0.7,
            }
      }
      whileDrag={{ rotate: 4, scale: 1.07 }}
      whileTap={{ scale: 0.92 }}
    >
      {reduced || !active ? (
        <button
          type="button"
          data-haptics="off"
          aria-label={label}
          className="h-full w-full rounded-full focus-visible:ring-2 focus-visible:ring-primary"
          onClick={activate}
        >
          <RautaStill />
        </button>
      ) : (
        <Suspense
          fallback={
            <button
              type="button"
              data-haptics="off"
              aria-label={label}
              className="h-full w-full"
              onClick={activate}
            >
              <RautaStill />
            </button>
          }
        >
          <AnimatedRauta {...props} label={label} onActivate={activate} />
        </Suspense>
      )}
    </motion.div>
  )
}
