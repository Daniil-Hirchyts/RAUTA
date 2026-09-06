import { create } from "zustand"
import { App as CapacitorApp } from "@capacitor/app"

import {
  createGymLibBackup,
  hasMeaningfulGymLibData,
  importGymLibData,
} from "@/lib/app-backup"
import { iCloudBackup, type ICloudBackupRecord } from "@/lib/icloud"
import { isNative } from "@/lib/native"
import { isRecord } from "@/store/persistence"
import { useFavorites } from "@/store/use-favorites"
import { useFilters } from "@/store/use-filters"
import { useSettings } from "@/store/use-settings"
import { useTrainingProfile } from "@/store/use-training-profile"
import { useWorkouts } from "@/store/use-workouts"

const SYNC_META_KEY = "gym-lib-icloud-sync"
const UPLOAD_DELAY_MS = 900

type SyncMeta = {
  localChangedAt: string | null
  cloudUpdatedAt: string | null
}

export type ICloudSyncState = {
  status: "checking" | "syncing" | "synced" | "unavailable" | "error"
  lastSyncedAt: string | null
  error: string | null
}

export const useICloudSync = create<ICloudSyncState>(() => ({
  status: isNative() ? "checking" : "unavailable",
  lastSyncedAt: null,
  error: null,
}))

let startPromise: Promise<void> | null = null
let uploadTimer: number | null = null
let applyingCloudBackup = false
let available = false
let lastIssuedTimestamp = 0

function readMeta(): SyncMeta {
  try {
    const value: unknown = JSON.parse(
      localStorage.getItem(SYNC_META_KEY) ?? "null"
    )
    if (!isRecord(value)) throw new Error("Invalid sync metadata")
    return {
      localChangedAt:
        typeof value.localChangedAt === "string" ? value.localChangedAt : null,
      cloudUpdatedAt:
        typeof value.cloudUpdatedAt === "string" ? value.cloudUpdatedAt : null,
    }
  } catch {
    return { localChangedAt: null, cloudUpdatedAt: null }
  }
}

function writeMeta(meta: SyncMeta) {
  localStorage.setItem(SYNC_META_KEY, JSON.stringify(meta))
}

function nextTimestamp() {
  lastIssuedTimestamp = Math.max(Date.now(), lastIssuedTimestamp + 1)
  return new Date(lastIssuedTimestamp).toISOString()
}

function reportError(error: unknown) {
  useICloudSync.setState({
    status: "error",
    error:
      error instanceof Error
        ? error.message
        : "Could not save this backup to iCloud.",
  })
}

async function uploadLocalData() {
  if (!available) return false
  if (uploadTimer !== null) {
    window.clearTimeout(uploadTimer)
    uploadTimer = null
  }

  useICloudSync.setState({ status: "syncing", error: null })
  const updatedAt = nextTimestamp()
  try {
    await iCloudBackup.write({
      data: createGymLibBackup(updatedAt, false),
      updatedAt,
    })
    writeMeta({ localChangedAt: updatedAt, cloudUpdatedAt: updatedAt })
    useICloudSync.setState({
      status: "synced",
      lastSyncedAt: updatedAt,
      error: null,
    })
    return true
  } catch (error) {
    reportError(error)
    return false
  }
}

function restoreCloudData(record: ICloudBackupRecord) {
  applyingCloudBackup = true
  try {
    importGymLibData(record.data)
    writeMeta({
      localChangedAt: record.updatedAt,
      cloudUpdatedAt: record.updatedAt,
    })
    useICloudSync.setState({
      status: "synced",
      lastSyncedAt: record.updatedAt,
      error: null,
    })
  } finally {
    applyingCloudBackup = false
  }
}

async function acceptExternalChange(record: ICloudBackupRecord) {
  const meta = readMeta()
  if (meta.localChangedAt !== null && record.updatedAt <= meta.localChangedAt) {
    return
  }

  try {
    restoreCloudData(record)
  } catch (error) {
    reportError(error)
  }
}

function scheduleUpload() {
  if (!available || applyingCloudBackup) return
  const changedAt = nextTimestamp()
  const meta = readMeta()
  writeMeta({ ...meta, localChangedAt: changedAt })
  useICloudSync.setState({ status: "syncing", error: null })
  if (uploadTimer !== null) window.clearTimeout(uploadTimer)
  uploadTimer = window.setTimeout(() => {
    uploadTimer = null
    void uploadLocalData()
  }, UPLOAD_DELAY_MS)
}

function subscribeToLocalData() {
  useFavorites.subscribe(scheduleUpload)
  useFilters.subscribe(scheduleUpload)
  useSettings.subscribe(scheduleUpload)
  useTrainingProfile.subscribe(scheduleUpload)
  useWorkouts.subscribe(scheduleUpload)
}

async function initialize() {
  if (!isNative()) {
    useICloudSync.setState({ status: "unavailable" })
    return
  }

  try {
    const status = await iCloudBackup.status()
    available = status.available
    if (!available) {
      useICloudSync.setState({ status: "unavailable", error: null })
      return
    }

    const [remote] = await Promise.all([
      iCloudBackup.read(),
      iCloudBackup.addChangeListener((record) => {
        void acceptExternalChange(record)
      }),
    ])
    const meta = readMeta()
    const localChangedAt = meta.localChangedAt

    if (
      remote &&
      (!hasMeaningfulGymLibData() ||
        (localChangedAt !== null && remote.updatedAt > localChangedAt))
    ) {
      restoreCloudData(remote)
    } else if (
      hasMeaningfulGymLibData() &&
      (!remote || localChangedAt === null || localChangedAt > remote.updatedAt)
    ) {
      await uploadLocalData()
    } else {
      useICloudSync.setState({
        status: "synced",
        lastSyncedAt: remote?.updatedAt ?? meta.cloudUpdatedAt,
        error: null,
      })
    }

    subscribeToLocalData()
    void CapacitorApp.addListener("appStateChange", ({ isActive }) => {
      // Do not depend on a debounce surviving suspension. Backgrounding is
      // the last guaranteed opportunity to persist a just-made change.
      const meta = readMeta()
      if (!isActive && meta.localChangedAt !== meta.cloudUpdatedAt) {
        void uploadLocalData()
      }
    })
  } catch (error) {
    reportError(error)
  }
}

/** Restores before first paint, then mirrors later data changes automatically. */
export function startICloudSync() {
  startPromise ??= initialize()
  return startPromise
}

/** Used by Settings for an explicit retry and immediately after data clearing. */
export async function syncICloudNow() {
  await startICloudSync()
  return uploadLocalData()
}
