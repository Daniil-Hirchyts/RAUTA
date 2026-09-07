import { useEffect, useRef, useState, type ChangeEvent } from "react"
import { App as CapacitorApp } from "@capacitor/app"
import {
  Activity,
  Apple,
  BellRing,
  ChevronLeft,
  Cloud,
  Download,
  Dumbbell,
  FileUp,
  HeartPulse,
  Info,
  PersonStanding,
  RefreshCw,
  ShieldCheck,
  Smartphone,
  Target,
  Trash2,
  User,
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
import {
  SettingsAction,
  SettingsRow,
  SettingsSection,
} from "@/components/settings-rows"
import { Button } from "@/components/ui/button"
import { MatrixLoader } from "@/components/ui/matrix-loader"
import { Switch } from "@/components/ui/switch"
import { exportGymLibData, importGymLibData } from "@/lib/app-backup"
import { openAppleHealthSettings, requestAppleHealthAccess } from "@/lib/health"
import { triggerHaptic } from "@/lib/haptics"
import { syncICloudNow, useICloudSync } from "@/lib/icloud-sync"
import { isNative } from "@/lib/native"
import { countLabel } from "@/lib/text"
import { experienceLabel, goalLabel } from "@/lib/training-profile"
import type { ProfilePage } from "@/store/app-navigation"
import { useFilters } from "@/store/use-filters"
import { useSettings, type SettingsPreferences } from "@/store/use-settings"
import { useTrainingProfile } from "@/store/use-training-profile"

export function SettingsPage({
  onBack,
  onClearData,
  onOpenProfilePage,
}: {
  onBack: () => void
  onClearData: () => void
  /** Everything the profile holds is edited on a page of its own, grouped the
   *  way the section above it is grouped: several questions at once rather
   *  than a screen — or a dialog — per answer. */
  onOpenProfilePage: (page: ProfilePage["type"]) => void
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
  const profile = useTrainingProfile((state) => state.profile)
  const gymEquipment = useFilters((state) => state.gymEquipment)

  const openProfilePage = (page: ProfilePage["type"]) => {
    triggerHaptic("light")
    onOpenProfilePage(page)
  }

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
      setNotice(
        "Apple Health did not grant access. Allow it in Settings › Health › Data Access & Devices › RAUTA, then turn this back on."
      )
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
      setNotice(
        "Backup restored. Your workouts, favorites and presets are back."
      )
      triggerHaptic("success")
    } catch (error) {
      setNotice(
        error instanceof Error
          ? error.message
          : "That file is not a RAUTA backup. Pick the .json file this app exported."
      )
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
          className="app-scroll-region min-h-0 flex-1 space-y-6 overflow-y-auto px-(--app-content-inset) pt-5 pb-6"
          ref={scrollRef}
          tabIndex={-1}
        >
          <SettingsSection title="Training profile">
            {/* Two rows open a group of questions and summarise the answers
                underneath; two open one question each. Nothing that stands on
                its own is folded into a group to make the list shorter. */}
            <SettingsAction
              description={`${profile.age} · ${experienceLabel(
                profile.trainingExperience
              )}`}
              icon={<User />}
              onClick={() => openProfilePage("profile-basics")}
              title="Profile"
              value={profile.name || "Not set"}
            />
            <SettingsAction
              description={`${goalLabel(profile.goal)} · ${
                profile.preferredSessionDurationMinutes
              } min`}
              icon={<Target />}
              onClick={() => openProfilePage("profile-training")}
              title="Training"
            />
            <SettingsAction
              icon={<PersonStanding />}
              onClick={() => openProfilePage("profile-priorities")}
              title="Priority muscles"
              value={
                profile.priorityMuscles.length > 0
                  ? countLabel(profile.priorityMuscles.length, "muscle")
                  : "None"
              }
            />
            <SettingsAction
              icon={<ShieldCheck />}
              onClick={() => openProfilePage("profile-health")}
              title="Health & eligibility"
              value={
                profile.health.status === "healthy"
                  ? "Ready to train"
                  : "Manual only"
              }
            />
          </SettingsSection>

          <SettingsSection title="Apple Health">
            <SettingsRow
              description={
                settings.healthStatus === "connected"
                  ? settings.healthBodyWeightKg
                    ? `Connected · ${settings.healthBodyWeightKg} kg from Health`
                    : "Connected · finished workouts are saved to Health"
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
              description="Estimated from how long you trained, and your Health weight when you allow it"
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
            <SettingsAction
              description="What an automatic plan may use"
              icon={<Dumbbell />}
              onClick={() => openProfilePage("profile-equipment")}
              title="Available equipment"
              value={
                gymEquipment.length > 0
                  ? countLabel(gymEquipment.length, "item")
                  : "Not set"
              }
            />
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
              description="Save one file holding every workout, favorite and preset"
              icon={<Download />}
              onClick={() => {
                triggerHaptic("light")
                void exportGymLibData()
                  .then(() => {
                    setNotice("Backup ready to save or share.")
                    triggerHaptic("success")
                  })
                  .catch(() =>
                    // Naming the likely cause and the other way to keep this
                    // data — the iCloud row directly above — beats reporting
                    // that it did not work and stopping there.
                    setNotice(
                      "The backup could not be written. Check the space left on this device, or leave iCloud backup on instead."
                    )
                  )
              }}
              title="Export data"
            />
            <SettingsAction
              description="Restore from a RAUTA backup file"
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
