#!/usr/bin/env node
/**
 * Minimal App Store Connect API client for the release script.
 *
 * Authenticates with an API key (ES256 JWT). Reads credentials from
 * ASC_KEY_ID / ASC_ISSUER / ASC_KEY_PATH.
 *
 * Commands:
 *   app-id <bundleId>              prints the App Store Connect app id
 *   next-build <appId>             prints highest existing build number + 1
 *   build-state <appId> <version>  prints "<processingState> <internalState>"
 */
import crypto from "node:crypto"
import fs from "node:fs"

const KEY_ID = process.env.ASC_KEY_ID
const ISSUER = process.env.ASC_ISSUER
const KEY_PATH =
  process.env.ASC_KEY_PATH ??
  `${process.env.HOME}/.appstoreconnect/private_keys/AuthKey_${KEY_ID}.p8`

if (!KEY_ID || !ISSUER) {
  console.error("asc-api: ASC_KEY_ID and ASC_ISSUER must be set")
  process.exit(2)
}
if (!fs.existsSync(KEY_PATH)) {
  console.error(`asc-api: private key not found at ${KEY_PATH}`)
  process.exit(2)
}

const b64 = (value) =>
  Buffer.from(typeof value === "string" ? value : JSON.stringify(value)).toString(
    "base64url"
  )

function token() {
  const now = Math.floor(Date.now() / 1000)
  const signing = `${b64({ alg: "ES256", kid: KEY_ID, typ: "JWT" })}.${b64({
    iss: ISSUER,
    iat: now,
    exp: now + 900,
    aud: "appstoreconnect-v1",
  })}`
  // ES256 wants the raw R||S pair, not the DER wrapper OpenSSL emits.
  const signature = crypto.sign(null, Buffer.from(signing), {
    key: crypto.createPrivateKey(fs.readFileSync(KEY_PATH)),
    dsaEncoding: "ieee-p1363",
  })
  return `${signing}.${signature.toString("base64url")}`
}

async function get(path) {
  const response = await fetch(`https://api.appstoreconnect.apple.com${path}`, {
    headers: { Authorization: `Bearer ${token()}` },
  })
  const body = await response.json().catch(() => ({}))
  if (!response.ok) {
    const detail = body?.errors?.[0]?.detail ?? response.statusText
    console.error(`asc-api: HTTP ${response.status} — ${detail}`)
    process.exit(1)
  }
  return body
}

const [command, ...args] = process.argv.slice(2)

if (command === "app-id") {
  const bundleId = args[0]
  const { data } = await get("/v1/apps?limit=200")
  const app = data.find((entry) => entry.attributes.bundleId === bundleId)
  if (!app) {
    console.error(`asc-api: no App Store Connect app for ${bundleId}`)
    process.exit(1)
  }
  console.log(app.id)
} else if (command === "next-build") {
  const { data } = await get(`/v1/builds?filter[app]=${args[0]}&limit=200`)
  const numbers = data
    .map((build) => Number(build.attributes.version))
    .filter(Number.isInteger)
  console.log(numbers.length ? Math.max(...numbers) + 1 : 1)
} else if (command === "build-state") {
  const [appId, version] = args
  const body = await get(
    `/v1/builds?filter[app]=${appId}&limit=50&include=buildBetaDetail`
  )
  const build = body.data.find(
    (entry) => entry.attributes.version === String(version)
  )
  if (!build) {
    console.log("PENDING -")
    process.exit(0)
  }
  const details = Object.fromEntries(
    (body.included ?? [])
      .filter((entry) => entry.type === "buildBetaDetails")
      .map((entry) => [entry.id, entry.attributes])
  )
  const detailId = build.relationships?.buildBetaDetail?.data?.id
  console.log(
    `${build.attributes.processingState} ${
      details[detailId]?.internalBuildState ?? "-"
    }`
  )
} else {
  console.error("asc-api: unknown command")
  process.exit(2)
}
