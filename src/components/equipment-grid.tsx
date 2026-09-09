import { AnimatedCheck } from "@/components/animated-check"
import { AppImage } from "@/components/app-image"
import { EQUIPMENT_OPTIONS } from "@/lib/exercises"
import { triggerHaptic } from "@/lib/haptics"
import { titleCase } from "@/lib/text"
import { cn } from "@/lib/utils"
import { equipmentImage } from "@/lib/visuals"

/**
 * The app's one equipment picker. It answers two different questions — which
 * equipment to filter this browse by, and which equipment you actually have —
 * from the same list, the same pictures and the same tap, so neither surface
 * has to grow an equipment vocabulary of its own.
 */
export function EquipmentGrid({
  className,
  onToggle,
  selected,
}: {
  className?: string
  onToggle: (equipment: string) => void
  selected: string[]
}) {
  return (
    <div className={cn("grid grid-cols-2 gap-3", className)}>
      {EQUIPMENT_OPTIONS.map((equipment, equipmentIndex) => {
        const checked = selected.includes(equipment)
        return (
          <button
            aria-checked={checked}
            className={`equipment-card interactive-spring group relative overflow-hidden rounded-(--app-card-radius) border bg-card text-left shadow-sm shadow-black/10 transition-[border-color,box-shadow] duration-300 ${
              checked
                ? "border-primary/75 shadow-[0_0_0_1px_color-mix(in_oklch,var(--primary)_30%,transparent)]"
                : "border-border"
            }`}
            key={equipment}
            onClick={() => {
              triggerHaptic("selection")
              onToggle(equipment)
            }}
            role="checkbox"
            type="button"
          >
            <span className="equipment-card-media relative block aspect-square overflow-hidden">
              <AppImage
                alt=""
                className="equipment-card-image h-full w-full object-contain object-center"
                decoding="async"
                draggable={false}
                fetchPriority={equipmentIndex < 4 ? "high" : "low"}
                loading={equipmentIndex < 4 ? "eager" : "lazy"}
                src={equipmentImage(equipment)}
              />
            </span>
            <span className="flex min-h-13 items-center justify-center px-3.5 py-3 text-center text-base leading-tight font-semibold">
              {titleCase(equipment)}
            </span>
            <AnimatedCheck
              checked={checked}
              className="pointer-events-none absolute top-5 right-5 size-8"
            />
          </button>
        )
      })}
    </div>
  )
}
