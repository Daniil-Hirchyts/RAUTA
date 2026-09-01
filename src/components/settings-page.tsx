import {
  useEffect,
  useRef,
  useState,
  type ChangeEvent,
  type ReactNode,
} from "react"
import { App as CapacitorApp } from "@capacitor/app"
import {
  Activity,
  Apple,
  BellRing,
  ChevronLeft,
  ChevronRight,
  Download,
  FileUp,
  HeartPulse,
  Info,
  Smartphone,
  Trash2,
  Vibrate,
} from "lucide-react"

import packageJson from "../../package.json"
import { ClearDataConfirmation } from "@/components/clear-data-confirmation"
import { Button } from "@/components/ui/button"
import { MatrixLoader } from "@/components/ui/matrix-loader"
import { Switch } from "@/components/ui/switch"
import {
  clearAllGymLibData,
  exportGymLibData,
  importGymLibData,
} from "@/lib/app-backup"
import { openAppleHealthSettings, requestAppleHealthAccess } from "@/lib/health"
import { triggerHaptic } from "@/lib/haptics"
import { isNative } from "@/lib/native"
import { cn } from "@/lib/utils"
import { useSettings, type SettingsPreferences } from "@/store/use-settings"

/** Every row in every section shares one box, so the dividers line up and a
 *  switch row is exactly as tall as the link row above it. */
const ROW =
  "flex min-h-16 w-full items-center gap-3 border-b border-border px-4 py-3 text-left last:border-b-0"

function SettingsSection({
  children,
  title,
}: {
  children: ReactNode
  title: string
}) {
  return (
    <section>
      <h2 className="mb-2 px-1 text-xs font-bold tracking-[0.16em] text-muted-foreground uppercase">
        {title}
      </h2>
      <div className="overflow-hidden rounded-[22px] border border-border bg-card shadow-sm shadow-black/10">
        {children}
      </div>
    </section>
  )
}

function RowIcon({ children }: { children: ReactNode }) {
  return (
    <span className="grid size-5 shrink-0 place-items-center text-primary [&_svg]:size-5">
      {children}
    </span>
  )
}

function RowLabel({
  description,
  title,
}: {
  description?: string
  title: string
}) {
  return (
    <div className="min-w-0 flex-1">
      <p className="text-base leading-snug font-semibold">{title}</p>
      {description ? (
        <p className="mt-0.5 text-sm leading-snug text-muted-foreground">
          {description}
        </p>
      ) : null}
    </div>
  )
}

function SettingsRow({
  children,
  description,
  icon,
  title,
}: {
  children?: ReactNode
  description?: string
  icon: ReactNode
  title: string
}) {
  return (
    <div className={ROW}>
      <RowIcon>{icon}</RowIcon>
      <RowLabel description={description} title={title} />
      {children}
    </div>
  )
}

function SettingsAction({
  description,
  icon,
  onClick,
  title,
  tone = "default",
}: {
  description?: string
  icon: ReactNode
  onClick: () => void
  title: string
  tone?: "default" | "destructive"
}) {
  return (
    <button
      className={cn(
        ROW,
        "transition-colors duration-150 active:bg-muted",
        tone === "destructive" && "text-primary"
      )}
      data-haptics="off"
      onClick={onClick}
      type="button"
    >
      <RowIcon>{icon}</RowIcon>
      <RowLabel description={description} title={title} />
      <ChevronRight
        className={cn(
          "size-5 shrink-0",
          tone === "destructive" ? "text-primary" : "text-muted-foreground"
        )}
      />
    </button>
  )
}

export function SettingsPage({
  onBack,
  onDataCleared,
}: {
  onBack: () => void
  onDataCleared: () => void
}) {
  const settings = useSettings()
  const setPreference = settings.setPreference
  const fileInputRef = useRef<HTMLInputElement>(null)
  const [clearOpen, setClearOpen] = useState(false)
  const [healthBusy, setHealthBusy] = useState(false)
  const [notice, setNotice] = useState("")
  const [appVersion, setAppVersion] = useState(packageJson.version)

  useEffect(() => {
    if (!isNative()) return
    void CapacitorApp.getInfo().then((info) => {
      setAppVersion(`${info.version} (${info.build})`)
    })
  }, [])

  const update = <Key extends keyof SettingsPreferences>(
    key: Key,
    value: SettingsPreferences[Key]
  ) => {
    triggerHaptic("selection")
    setPreference(key, value)
  }

  const toggleAppleHealth = async (enabled: boolean) => {
    if (!enabled) {
      update("appleHealthEnabled", false)
      return
    }

    setHealthBusy(true)
    setNotice("")
    try {
      const result = await requestAppleHealthAccess()
      const connected = result.status === "connected"
      setPreference("appleHealthEnabled", connected)
      setPreference("healthStatus", connected ? "connected" : "unavailable")
      setPreference("healthBodyWeightKg", result.bodyWeightKg)
      setPreference(
        "healthLastConnectedAt",
        connected ? new Date().toISOString() : null
      )
      setNotice(
        connected
          ? result.bodyWeightKg
            ? `Apple Health connected. Using ${result.bodyWeightKg} kg for energy estimates.`
            : "Apple Health connected. Weight access is optional; energy uses a standard estimate."
          : "Apple Health is available in the iPhone app."
      )
      triggerHaptic(connected ? "success" : "warning")
    } catch {
      setPreference("appleHealthEnabled", false)
      setPreference("healthStatus", "error")
      setNotice("Health access was not granted. You can try again.")
      triggerHaptic("warning")
    } finally {
      setHealthBusy(false)
    }
  }

  const importFile = async (event: ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0]
    event.target.value = ""
    if (!file) return
    try {
      importGymLibData(await file.text())
      setNotice("Backup restored successfully.")
      triggerHaptic("success")
    } catch (error) {
      setNotice(error instanceof Error ? error.message : "Import failed.")
      triggerHaptic("warning")
    }
  }

  return (
    <>
      <header className="shrink-0 border-b border-white/[0.05] bg-background/80 px-5 pt-4 pb-4 backdrop-blur-xl">
        <div className="mb-3 flex items-center gap-2">
          <Button
            aria-label="Back"
            className="shrink-0 rounded-full"
            onClick={onBack}
            size="icon"
            variant="secondary"
          >
            <ChevronLeft />
          </Button>
        </div>
        <h1 className="text-[26px] font-black tracking-[-0.03em]">Settings</h1>
      </header>

      <div className="min-h-0 flex-1 space-y-6 overflow-y-auto px-5 pt-5 pb-[calc(2rem+env(safe-area-inset-bottom))]">
        <SettingsSection title="Apple Health">
          <SettingsRow
            description={
              settings.healthStatus === "connected"
                ? settings.healthBodyWeightKg
                  ? `Connected · ${settings.healthBodyWeightKg} kg from Health`
                  : "Connected · workout write access granted"
                : "Save completed strength workouts to Health"
            }
            icon={<Apple />}
            title="Apple Health"
          >
            {healthBusy ? (
              <MatrixLoader
                label="Connecting to Apple Health"
                variant="pulse"
              />
            ) : null}
            <Switch
              aria-label="Apple Health integration"
              checked={settings.appleHealthEnabled}
              data-haptics="off"
              disabled={healthBusy}
              onCheckedChange={toggleAppleHealth}
            />
          </SettingsRow>
          <SettingsRow
            description="Includes workout duration automatically"
            icon={<HeartPulse />}
            title="Sync completed workouts"
          >
            <Switch
              aria-label="Sync completed workouts"
              checked={settings.autoSyncWorkouts}
              data-haptics="off"
              disabled={!settings.appleHealthEnabled}
              onCheckedChange={(checked) => update("autoSyncWorkouts", checked)}
            />
          </SettingsRow>
          <SettingsRow
            description="MET estimate using your latest Health weight when allowed"
            icon={<Activity />}
            title="Active calories"
          >
            <Switch
              aria-label="Sync active calories"
              checked={settings.syncActiveCalories}
              data-haptics="off"
              disabled={
                !settings.appleHealthEnabled || !settings.autoSyncWorkouts
              }
              onCheckedChange={(checked) =>
                update("syncActiveCalories", checked)
              }
            />
          </SettingsRow>
          {settings.healthStatus === "connected" ? (
            <SettingsAction
              icon={<HeartPulse />}
              onClick={() => {
                triggerHaptic("light")
                void openAppleHealthSettings()
              }}
              title="Manage Health permissions"
            />
          ) : null}
        </SettingsSection>

        <SettingsSection title="Workout & Gym">
          <SettingsRow icon={<Vibrate />} title="Haptic feedback">
            <Switch
              aria-label="Haptic feedback"
              checked={settings.hapticsEnabled}
              data-haptics="off"
              onCheckedChange={(checked) => update("hapticsEnabled", checked)}
            />
          </SettingsRow>
          <SettingsRow
            description="Play a short cue for completed actions"
            icon={<BellRing />}
            title="Sound chimes"
          >
            <Switch
              aria-label="Sound chimes"
              checked={settings.soundChimesEnabled}
              data-haptics="off"
              onCheckedChange={(checked) =>
                update("soundChimesEnabled", checked)
              }
            />
          </SettingsRow>
          <SettingsRow
            description="Prevents auto-lock during an active workout"
            icon={<Smartphone />}
            title="Keep screen awake"
          >
            <Switch
              aria-label="Keep screen awake"
              checked={settings.keepAwake}
              data-haptics="off"
              onCheckedChange={(checked) => update("keepAwake", checked)}
            />
          </SettingsRow>
        </SettingsSection>

        <SettingsSection title="Data & Storage">
          <SettingsAction
            description="Save a JSON backup of everything"
            icon={<Download />}
            onClick={() => {
              triggerHaptic("light")
              void exportGymLibData()
                .then(() => {
                  setNotice("Backup ready to save or share.")
                  triggerHaptic("success")
                })
                .catch(() => setNotice("Could not export your data."))
            }}
            title="Export data"
          />
          <SettingsAction
            description="Restore from a Gym Lib backup file"
            icon={<FileUp />}
            onClick={() => {
              triggerHaptic("light")
              fileInputRef.current?.click()
            }}
            title="Import data"
          />
          <SettingsAction
            icon={<Trash2 />}
            onClick={() => {
              triggerHaptic("warning")
              setClearOpen(true)
            }}
            title="Clear all data"
            tone="destructive"
          />
        </SettingsSection>

        {/* Outside the card: a hidden child would still count as the section's
            last row and leave the row above it with a dangling divider. */}
        <input
          accept="application/json,.json"
          className="hidden"
          onChange={importFile}
          ref={fileInputRef}
          type="file"
        />

        <SettingsSection title="About">
          <SettingsRow icon={<Info />} title="App version">
            <span className="text-sm font-medium text-muted-foreground tabular-nums">
              {appVersion}
            </span>
          </SettingsRow>
        </SettingsSection>

        {notice ? (
          <p
            aria-live="polite"
            className="px-2 text-center text-sm text-muted-foreground"
          >
            {notice}
          </p>
        ) : null}
      </div>

      <ClearDataConfirmation
        onConfirm={() => {
          clearAllGymLibData()
          onDataCleared()
        }}
        onOpenChange={setClearOpen}
        open={clearOpen}
      />
    </>
  )
}
