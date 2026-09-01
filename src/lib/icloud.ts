import { registerPlugin, type PluginListenerHandle } from "@capacitor/core"

import { isNative } from "@/lib/native"

export type ICloudBackupRecord = {
  data: string
  updatedAt: string
}

type ICloudBackupPlugin = {
  status: () => Promise<{ available: boolean }>
  read: () => Promise<Partial<ICloudBackupRecord>>
  write: (record: ICloudBackupRecord) => Promise<void>
  addListener: (
    eventName: "backupChanged",
    listener: (record: Partial<ICloudBackupRecord>) => void
  ) => Promise<PluginListenerHandle>
}

const plugin = registerPlugin<ICloudBackupPlugin>("ICloudBackup")

/** Thin, failure-safe boundary around the native iCloud KVS plugin. */
export const iCloudBackup = {
  status: async () => {
    if (!isNative()) return { available: false }
    return plugin.status()
  },
  read: async () => {
    if (!isNative()) return null
    const record = await plugin.read()
    return typeof record.data === "string" &&
      typeof record.updatedAt === "string"
      ? { data: record.data, updatedAt: record.updatedAt }
      : null
  },
  write: async (record: ICloudBackupRecord) => {
    if (!isNative()) return
    await plugin.write(record)
  },
  addChangeListener: async (listener: (record: ICloudBackupRecord) => void) => {
    if (!isNative()) return null
    return plugin.addListener("backupChanged", (record) => {
      if (
        typeof record.data === "string" &&
        typeof record.updatedAt === "string"
      ) {
        listener({ data: record.data, updatedAt: record.updatedAt })
      }
    })
  },
}
