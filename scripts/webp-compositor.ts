export type Rgba = [number, number, number, number]

export type AnimationFrame = {
  width: number
  height: number
  hasAlpha: boolean
  x: number
  y: number
  disposeToBackground: boolean
  blendWithPrevious: boolean
}

export type AnimationInfo = {
  width: number
  height: number
  background: Rgba
  frames: AnimationFrame[]
}

export function parseAnimationInfo(
  info: string,
  source = "WebP animation"
): AnimationInfo {
  const canvas = info.match(/Canvas size:\s*(\d+) x (\d+)/)
  if (!canvas) throw new Error(`Missing animation canvas metadata: ${source}`)
  const backgroundHex =
    info.match(/Background color\s*:\s*0x([0-9a-f]{8})/i)?.[1] ?? "00000000"
  const value = Number.parseInt(backgroundHex, 16)
  const background: Rgba = [
    (value >>> 16) & 0xff,
    (value >>> 8) & 0xff,
    value & 0xff,
    (value >>> 24) & 0xff,
  ]
  const frames = info
    .split("\n")
    .map((line) =>
      line.match(
        /^\s*\d+:\s+(\d+)\s+(\d+)\s+(yes|no)\s+(\d+)\s+(\d+)\s+\d+\s+(background|none)\s+(yes|no)\b/
      )
    )
    .filter((match): match is RegExpMatchArray => Boolean(match))
    .map((match) => ({
      width: Number(match[1]),
      height: Number(match[2]),
      hasAlpha: match[3] === "yes",
      x: Number(match[4]),
      y: Number(match[5]),
      disposeToBackground: match[6] === "background",
      blendWithPrevious: match[7] === "yes",
    }))
  if (!frames.length) throw new Error(`Missing animation frame metadata: ${source}`)
  return {
    width: Number(canvas[1]),
    height: Number(canvas[2]),
    background,
    frames,
  }
}

export function createAnimationCanvas(
  width: number,
  height: number,
  background: Rgba
): Uint8Array {
  const canvas = new Uint8Array(width * height * 4)
  for (let offset = 0; offset < canvas.length; offset += 4) {
    canvas[offset] = background[0]
    canvas[offset + 1] = background[1]
    canvas[offset + 2] = background[2]
    canvas[offset + 3] = background[3]
  }
  return canvas
}

export function sourceOver(
  canvas: Uint8Array,
  targetOffset: number,
  source: Uint8Array,
  sourceOffset: number
) {
  const sourceAlpha = source[sourceOffset + 3] / 255
  const destinationAlpha = canvas[targetOffset + 3] / 255
  const outputAlpha = sourceAlpha + destinationAlpha * (1 - sourceAlpha)
  if (outputAlpha === 0) {
    canvas.fill(0, targetOffset, targetOffset + 4)
    return
  }
  for (let channel = 0; channel < 3; channel++)
    canvas[targetOffset + channel] = Math.round(
      (source[sourceOffset + channel] * sourceAlpha +
        canvas[targetOffset + channel] * destinationAlpha * (1 - sourceAlpha)) /
        outputAlpha
    )
  canvas[targetOffset + 3] = Math.round(outputAlpha * 255)
}

export function compositeAnimationFrame(
  canvas: Uint8Array,
  canvasWidth: number,
  canvasHeight: number,
  frame: AnimationFrame,
  source: Uint8Array
) {
  if (frame.x < 0 || frame.y < 0 || frame.x + frame.width > canvasWidth || frame.y + frame.height > canvasHeight)
    throw new Error("Animation frame extends outside the canvas")
  if (source.length !== frame.width * frame.height * 4)
    throw new Error("Animation frame pixel payload has unexpected dimensions")
  for (let y = 0; y < frame.height; y++)
    for (let x = 0; x < frame.width; x++) {
      const targetOffset = ((frame.y + y) * canvasWidth + frame.x + x) * 4
      const sourceOffset = (y * frame.width + x) * 4
      if (frame.blendWithPrevious)
        sourceOver(canvas, targetOffset, source, sourceOffset)
      else canvas.set(source.subarray(sourceOffset, sourceOffset + 4), targetOffset)
    }
}

export function disposeAnimationFrame(
  canvas: Uint8Array,
  canvasWidth: number,
  frame: AnimationFrame,
  background: Rgba
) {
  if (!frame.disposeToBackground) return
  for (let y = 0; y < frame.height; y++)
    for (let x = 0; x < frame.width; x++) {
      const offset = ((frame.y + y) * canvasWidth + frame.x + x) * 4
      canvas[offset] = background[0]
      canvas[offset + 1] = background[1]
      canvas[offset + 2] = background[2]
      canvas[offset + 3] = background[3]
    }
}

export function flattenAnimationCanvas(
  canvas: Uint8Array,
  background: Rgba
): Uint8Array {
  const rgb = new Uint8Array((canvas.length / 4) * 3)
  const backgroundAlpha = background[3] / 255
  for (
    let sourceOffset = 0, targetOffset = 0;
    sourceOffset < canvas.length;
    sourceOffset += 4, targetOffset += 3
  ) {
    const alpha = canvas[sourceOffset + 3] / 255
    const flattenedAlpha = alpha + backgroundAlpha * (1 - alpha)
    for (let channel = 0; channel < 3; channel++) {
      const value =
        flattenedAlpha === 0
          ? 0
          : (canvas[sourceOffset + channel] * alpha +
              background[channel] * backgroundAlpha * (1 - alpha)) /
            flattenedAlpha
      rgb[targetOffset + channel] = Math.round(value)
    }
  }
  return rgb
}
