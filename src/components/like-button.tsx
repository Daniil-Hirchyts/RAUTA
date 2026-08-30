import { useState, type ButtonHTMLAttributes, type CSSProperties } from "react"
import { Heart } from "lucide-react"

import { cn } from "@/lib/utils"

const PARTICLES = [
  { x: "0px", y: "-21px", delay: "0ms", duration: "540ms", size: 0.85 },
  { x: "15px", y: "-15px", delay: "18ms", duration: "590ms", size: 1.1 },
  { x: "22px", y: "0px", delay: "5ms", duration: "560ms", size: 0.75 },
  { x: "15px", y: "15px", delay: "24ms", duration: "620ms", size: 1 },
  { x: "0px", y: "21px", delay: "10ms", duration: "570ms", size: 0.8 },
  { x: "-15px", y: "15px", delay: "28ms", duration: "610ms", size: 1.05 },
  { x: "-22px", y: "0px", delay: "8ms", duration: "550ms", size: 0.8 },
  { x: "-15px", y: "-15px", delay: "20ms", duration: "600ms", size: 0.95 },
] as const

type ParticleStyle = CSSProperties & {
  "--px": string
  "--py": string
  "--pdelay": string
  "--pdur": string
  "--psize": number
}

export function LikeButton({
  animated = true,
  className,
  iconClassName,
  liked,
  onClick,
  ...props
}: Omit<ButtonHTMLAttributes<HTMLButtonElement>, "aria-pressed"> & {
  /** Set false to skip the heart-pop + particle-burst animation, e.g. for a
   *  toggle that just opens/filters a view rather than "liking" something. */
  animated?: boolean
  iconClassName?: string
  liked: boolean
}) {
  const [bursting, setBursting] = useState(false)

  return (
    <button
      aria-pressed={liked}
      className={cn(
        "t-like relative",
        bursting && "is-bursting",
        !animated && "t-like-static",
        className
      )}
      data-liked={liked}
      onClick={(event) => {
        if (!liked && animated) setBursting(true)
        onClick?.(event)
      }}
      type="button"
      {...props}
    >
      <span className="t-like-icon grid place-items-center">
        <Heart className={cn("t-like-heart", iconClassName)} />
      </span>
      {animated && bursting && (
        <span aria-hidden="true" className="t-like-particles">
          {PARTICLES.map((particle, index) => (
            <i
              key={index}
              onAnimationEnd={() => {
                if (index === 5) setBursting(false)
              }}
              style={
                {
                  "--px": particle.x,
                  "--py": particle.y,
                  "--pdelay": particle.delay,
                  "--pdur": particle.duration,
                  "--psize": particle.size,
                } as ParticleStyle
              }
            />
          ))}
        </span>
      )}
    </button>
  )
}
