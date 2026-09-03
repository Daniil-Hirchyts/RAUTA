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
  Cloud,
  Download,
  FileUp,
  HeartPulse,
  Info,
  RefreshCw,
  Smartphone,
  Trash2,
  Vibrate,
} from "lucide-react"

import packageJson from "../../package.json"
import {
  AppHeaderButton,
  AppScreen,
  AppShellHeader,
  AppSurface,
} from "@/components/app-shell"
import { ConfirmModal } from "@/components/confirm-modal"
import { Button } from "@/components/ui/button"
import { MatrixLoader } from "@/components/ui/matrix-loader"
import { Switch } from "@/components/ui/switch"
import { exportGymLibData, importGymLibData } from "@/lib/app-backup"
import { openAppleHealthSettings, requestAppleHealthAccess } from "@/lib/health"
import { triggerHaptic } from "@/lib/haptics"
import { syncICloudNow, useICloudSync } from "@/lib/icloud-sync"
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
      <div className="overflow-hidden rounded-3xl border border-border bg-card shadow-sm shadow-black/10">
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
        "interactive-spring active:bg-muted/80",
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
  onClearData,
}: {
  onBack: () => void
  onClearData: () => void
}) {
  const scrollRef = useRef<HTMLDivElement>(null)
  const settings = useSettings()
  const iCloud = useICloudSync()
  const setPreference = settings.setPreference
  const fileInputRef = useRef<HTMLInputElement>(null)
  const [healthBusy, setHealthBusy] = useState(false)
  const [notice, setNotice] = useState("")
  const [appVersion, setAppVersion] = useState(packageJson.version)
  const [clearing, setClearing] = useState(false)

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

  const iCloudDescription = (() => {
    if (!isNative()) return "Automatic backup is available in the iPhone app"
    if (iCloud.status === "checking") return "Checking your iCloud account…"
    if (iCloud.status === "syncing") return "Saving workouts and settings…"
    if (iCloud.status === "unavailable")
      return "Sign in to iCloud to enable backup"
    if (iCloud.status === "error")
      return iCloud.error ?? "The last backup could not be saved"
    if (!iCloud.lastSyncedAt) return "Your data is backed up automatically"
    return `Saved automatically · ${new Intl.DateTimeFormat(undefined, {
      hour: "numeric",
      minute: "2-digit",
    }).format(new Date(iCloud.lastSyncedAt))}`
  })()

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
    <AppScreen>
      <AppSurface>
        <AppShellHeader
          left={
            <AppHeaderButton aria-label="Back" onClick={onBack}>
              <ChevronLeft />
            </AppHeaderButton>
          }
          scrollRef={scrollRef}
          title="Settings"
        />

        <div
          className="app-scroll-region min-h-0 flex-1 space-y-6 overflow-y-auto px-4 pt-5 pb-6"
          ref={scrollRef}
          tabIndex={-1}
        >
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
                onCheckedChange={(checked) =>
                  update("autoSyncWorkouts", checked)
                }
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
            <SettingsRow
              description={iCloudDescription}
              icon={<Cloud />}
              title="iCloud backup"
            >
              {iCloud.status === "checking" || iCloud.status === "syncing" ? (
                <MatrixLoader label="Syncing iCloud backup" variant="pulse" />
              ) : isNative() && iCloud.status !== "unavailable" ? (
                <Button
                  aria-label="Sync iCloud backup now"
                  className="shrink-0 rounded-full"
                  onClick={() => {
                    triggerHaptic("light")
                    void syncICloudNow().then((synced) => {
                      if (synced) triggerHaptic("success")
                    })
                  }}
                  size="icon"
                  variant="ghost"
                >
                  <RefreshCw className="size-4.5" />
                </Button>
              ) : null}
            </SettingsRow>
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
                setClearing(true)
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
      </AppSurface>

      <ConfirmModal
        kind={clearing ? "clear-data" : null}
        onCancel={() => setClearing(false)}
        onConfirm={() => {
          setClearing(false)
          onClearData()
        }}
      />
    </AppScreen>
  )
}
