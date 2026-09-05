import { writeFileSync } from "node:fs"
import { arch, cpus, platform } from "node:os"
import { exampleRequest } from "./generate-training-program"
import {
  adaptTrainingProgram,
  analyzeTrainingState,
  createExerciseIndex,
  DEFAULT_POLICY,
  generateTrainingProgram,
  validateTrainingProgram,
} from "../src/training"
import type { CompletedSession } from "../src/training"
const r = structuredClone(exampleRequest)
r.schedule.durationWeeks = 4
r.history = {
  coverage: "complete",
  coverageStart: "2026-01-01T00:00:00.000Z",
  sessions: Array.from({ length: 120 }, (_, i): CompletedSession => {
    const completedAt = new Date(
      Date.parse(r.now) - (120 - i) * 86400000
    ).toISOString()
    return {
      id: `h-${i}`,
      startedAt: new Date(Date.parse(completedAt) - 3600000).toISOString(),
      completedAt,
      status: "completed",
      exercises: ["0025", "0027", "0032", "0043"].map((exerciseId) => ({
        exerciseId,
        sets: Array.from({ length: 3 }, (_, j) => ({
          id: `${i}/${exerciseId}/${j}`,
          reps: 8,
          rir: 2,
          resistance: {
            type: "external_load",
            kg: 50,
            stationId: exerciseId,
            basis: "total",
          },
          completed: true,
          setType: "working",
          side: "both",
        })),
      })),
    }
  }),
}
const index = createExerciseIndex(r.exercises)
const generated = generateTrainingProgram(r)
if (!("program" in generated)) throw new Error(JSON.stringify(generated))
const future = {
  ...r,
  now: "2026-09-13T12:00:00.000Z",
  schedule: {
    ...r.schedule,
    weekStart: "2026-10-05T00:00:00.000Z",
    durationWeeks: 1,
  },
}
const runs = 7
function benchmark(name: string, fn: () => unknown) {
  fn()
  const samples = Array.from({ length: runs }, () => {
    const start = performance.now()
    fn()
    return performance.now() - start
  }).sort((a, b) => a - b)
  return {
    name,
    medianMs: Number(samples[Math.floor(runs / 2)].toFixed(2)),
    p95Ms: Number(samples.at(-1)!.toFixed(2)),
  }
}
const rows = [
  benchmark("index build (1,324 records)", () =>
    createExerciseIndex(r.exercises)
  ),
  benchmark("indexed muscle query (10,000 lookups)", () => {
    let count = 0
    for (let i = 0; i < 10000; i++)
      count += index.byMuscle.get("chest")?.length ?? 0
    return count
  }),
  benchmark("state (120 sessions / 1,440 sets)", () =>
    analyzeTrainingState(r, index)
  ),
  benchmark("generate (4 weeks, full data, history)", () =>
    generateTrainingProgram(r)
  ),
  benchmark("adapt next week", () =>
    adaptTrainingProgram({
      previousProgram: generated.program,
      request: future,
      mode: "next_week",
    })
  ),
  benchmark("independent validation (4 weeks)", () =>
    validateTrainingProgram(generated.program, r, index)
  ),
]
const widths = [1, 3, 8].map((beamWidth) => {
  const request = {
    ...r,
    policy: { ...structuredClone(DEFAULT_POLICY), beamWidth },
  }
  const timing = benchmark(`beam width ${beamWidth}`, () =>
    generateTrainingProgram(request)
  )
  const result = generateTrainingProgram(request)
  return {
    ...timing,
    score: "program" in result ? result.program.diagnostics.score.total : null,
  }
})
const results = {
  environment: {
    runtime: `Bun ${process.versions.bun ?? "unknown"} (Node compatibility ${process.version})`,
    platform: platform(),
    architecture: arch(),
    cpu: cpus()[0].model,
    runs,
  },
  rows,
  widths,
}
writeFileSync(
  "docs/training-engine/benchmark-results.json",
  JSON.stringify(results, null, 2) + "\n"
)
writeFileSync(
  "docs/training-engine/PERFORMANCE.md",
  `# Performance\n\nRun \`bun scripts/benchmark-training-engine.ts\`. Measured on ${results.environment.cpu}, ${platform()} ${arch()}, runtime ${results.environment.runtime}. One warmup plus ${runs} timed repetitions per operation. The reported p95 is the maximum of this small sample; it is not a precise tail-latency estimate. Input: full 1,324-record dataset, four-week program, 3 × 45-minute sessions/week, 120 historical sessions and 1,440 completed sets. Wall-clock measurements remain outside deterministic core results.\n\n| Operation | Median ms | Sample p95 ms |\n|---|---:|---:|\n${rows.map((r) => `| ${r.name} | ${r.medianMs} | ${r.p95Ms} |`).join("\n")}\n\n## Beam width comparison\n\n| Width | Median ms | Score |\n|---|---:|---:|\n${widths.map((w) => `| ${w.name} | ${w.medianMs} | ${w.score?.toFixed(4)} |`).join("\n")}\n\nScores are optimizer utility, not predicted fitness outcomes. One representative case does not establish global optimality. Default width 3 bounds latency; widening is configurable.\n\n## Profiling and limits\n\nAn initial cold-start run took about 2,097 ms. Bun CPU profiling showed repeated muscle-volume aggregation inside candidate scoring as the dominant sampled stack. Computing one scoring context per partial session and iterating only known set roles reduced that same cold-start run to about 508 ms. This is an algorithmic change with invariant/scenario regression tests. No native code or optimization dependency was needed. Indexes are reusable for analytics, validation and queries. Generation currently builds its own index once per request.\n\nThese are desktop development measurements, not iPhone benchmarks or a latency SLA. Several-thousand-exercise inputs and very long histories should be profiled on target hardware before UI integration. The pure synchronous API can be called from a future Web Worker without redesigning the domain. Persisted programs include a policy snapshot; payload size trades off against reproducibility.\n`
)
console.log(JSON.stringify(results, null, 2))
