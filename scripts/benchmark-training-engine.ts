import { writeFileSync } from "node:fs"
import { arch, cpus, platform } from "node:os"
import { exampleRequest } from "./generate-training-program"
import {
  adaptTrainingProgram,
  analyzeTrainingState,
  createExerciseIndex,
  DEFAULT_POLICY,
  findExerciseSubstitutions,
  generateTrainingProgram,
  validateTrainingProgram,
} from "../src/training"
import type {
  CompletedSession,
  ProgramGenerationRequest,
} from "../src/training"
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
const scenarioRuns = 3
function benchmark(name: string, fn: () => unknown, repetitions = runs) {
  fn()
  const samples = Array.from({ length: repetitions }, () => {
    const start = performance.now()
    fn()
    return performance.now() - start
  }).sort((a, b) => a - b)
  return {
    name,
    medianMs: Number(samples[Math.floor(samples.length / 2)].toFixed(2)),
    p95Ms: Number(samples.at(-1)!.toFixed(2)),
  }
}
const median = (values: number[]) => {
  if (!values.length) return null
  const sorted = [...values].sort((a, b) => a - b)
  return sorted[Math.floor(sorted.length / 2)]
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
  benchmark("substitution search", () =>
    findExerciseSubstitutions("0025", r, 10)
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
function scenario(
  name: string,
  configure: (request: ProgramGenerationRequest) => void
) {
  const request = structuredClone(exampleRequest)
  request.schedule.durationWeeks = 1
  configure(request)
  return { name, request }
}
const scenarioRequests = [
  scenario("beginner 2-day", (request) => {
    request.profile.trainingExperience = "beginner"
    request.preferences.goal = "general_fitness"
    request.schedule.days = [0, 3]
  }),
  scenario("beginner 3-day", (request) => {
    request.profile.trainingExperience = "beginner"
    request.preferences.goal = "general_fitness"
    request.schedule.days = [0, 2, 4]
  }),
  scenario("hypertrophy 4-day", (request) => {
    request.profile.trainingExperience = "intermediate"
    request.preferences.goal = "hypertrophy"
    request.preferences.maxSessionDurationMinutes = 60
    request.schedule.days = [0, 1, 3, 4]
  }),
  scenario("strength 4-day", (request) => {
    request.profile.trainingExperience = "intermediate"
    request.preferences.goal = "strength"
    request.preferences.strengthExerciseIds = ["0025", "0032"]
    request.preferences.maxSessionDurationMinutes = 60
    request.schedule.days = [0, 1, 3, 5]
  }),
  scenario("strength 5-day", (request) => {
    request.profile.trainingExperience = "advanced"
    request.preferences.goal = "strength"
    request.preferences.strengthExerciseIds = ["0025", "0032"]
    request.preferences.maxSessionDurationMinutes = 60
    request.schedule.days = [0, 1, 2, 4, 5]
  }),
  scenario("equipment-limited", (request) => {
    request.profile.trainingExperience = "intermediate"
    request.preferences.goal = "hypertrophy"
    request.preferences.availableEquipment = ["body weight", "dumbbell", "bench"]
    request.schedule.days = [0, 2, 4]
  }),
  scenario("time-limited", (request) => {
    request.profile.trainingExperience = "intermediate"
    request.preferences.goal = "general_fitness"
    request.preferences.preferredSessionDurationMinutes = 25
    request.preferences.maxSessionDurationMinutes = 25
    request.schedule.days = [0, 2, 4]
  }),
  scenario("priority muscle", (request) => {
    request.profile.trainingExperience = "intermediate"
    request.preferences.goal = "hypertrophy"
    request.preferences.priorityMuscles = [
      { muscleId: "chest", level: "specialization" },
    ]
    request.preferences.maxSessionDurationMinutes = 55
    request.schedule.days = [0, 1, 3, 5]
  }),
  {
    name: "dense history",
    request: {
      ...structuredClone(r),
      schedule: { ...structuredClone(r.schedule), durationWeeks: 1 },
    },
  },
]
const scenarioMatrix = scenarioRequests.flatMap(({ name, request }) =>
  [1, 3, 8].map((beamWidth) => {
    const benchmarkRequest = {
      ...structuredClone(request),
      policy: { ...structuredClone(DEFAULT_POLICY), beamWidth },
    }
    const timing = benchmark(
      `${name} / beam ${beamWidth}`,
      () => generateTrainingProgram(benchmarkRequest),
      scenarioRuns
    )
    const result = generateTrainingProgram(benchmarkRequest)
    if (!("program" in result))
      return {
        scenario: name,
        beamWidth,
        medianMs: timing.medianMs,
        p95Ms: timing.p95Ms,
        status: result.status,
        hardFeasible: false,
        score: null,
        issueCodes: result.issues.map((issue) => issue.code),
      }
    const validation = validateTrainingProgram(
      result.program,
      benchmarkRequest,
      createExerciseIndex(benchmarkRequest.exercises)
    )
    return {
      scenario: name,
      beamWidth,
      medianMs: timing.medianMs,
      p95Ms: timing.p95Ms,
      status: result.status,
      hardFeasible: validation.valid,
      score: result.program.diagnostics.score.total,
      issueCodes: validation.issues.map((issue) => issue.code),
    }
  })
)
const widthSummary = [1, 3, 8].map((beamWidth) => {
  const rows = scenarioMatrix.filter((row) => row.beamWidth === beamWidth)
  const scores = rows.flatMap((row) => (row.score === null ? [] : [row.score]))
  return {
    beamWidth,
    hardFeasibleScenarios: rows.filter((row) => row.hardFeasible).length,
    scenarioCount: rows.length,
    medianLatencyMs: Number((median(rows.map((row) => row.medianMs)) ?? 0).toFixed(2)),
    medianScore:
      scores.length > 0 ? Number((median(scores) ?? 0).toFixed(4)) : null,
  }
})
const results = {
  environment: {
    runtime: `Bun ${process.versions.bun ?? "unknown"} (Node compatibility ${process.version})`,
    platform: platform(),
    architecture: arch(),
    cpu: cpus()[0].model,
    runs,
    scenarioRuns,
  },
  rows,
  widths,
  scenarioMatrix,
  widthSummary,
}
writeFileSync(
  "docs/training-engine/benchmark-results.json",
  JSON.stringify(results, null, 2) + "\n"
)
writeFileSync(
  "docs/training-engine/PERFORMANCE.md",
  `# Performance\n\nRun \`bun scripts/benchmark-training-engine.ts\`. Measured on ${results.environment.cpu}, ${platform()} ${arch()}, runtime ${results.environment.runtime}. Core operations use one warmup plus ${runs} timed repetitions. Scenario-matrix generation uses one warmup plus ${scenarioRuns} timed repetitions per scenario/beam combination. The reported p95 is the maximum of each small sample; it is not a precise tail-latency estimate. Wall-clock measurements remain outside deterministic core results.\n\n| Operation | Median ms | Sample p95 ms |\n|---|---:|---:|\n${rows.map((r) => `| ${r.name} | ${r.medianMs} | ${r.p95Ms} |`).join("\n")}\n\n## Representative beam-width comparison\n\n| Width | Median ms | Score |\n|---|---:|---:|\n${widths.map((w) => `| ${w.name} | ${w.medianMs} | ${w.score?.toFixed(4)} |`).join("\n")}\n\n## Scenario matrix\n\n| Scenario | Beam | Median ms | Score | Hard-feasible | Status |\n|---|---:|---:|---:|:---:|---|\n${scenarioMatrix.map((row) => `| ${row.scenario} | ${row.beamWidth} | ${row.medianMs} | ${row.score === null ? "—" : row.score.toFixed(4)} | ${row.hardFeasible ? "yes" : "no"} | ${row.status} |`).join("\n")}\n\n| Beam | Feasible scenarios | Median scenario latency ms | Median score |\n|---|---:|---:|---:|\n${widthSummary.map((row) => `| ${row.beamWidth} | ${row.hardFeasibleScenarios}/${row.scenarioCount} | ${row.medianLatencyMs} | ${row.medianScore?.toFixed(4) ?? "—"} |`).join("\n")}\n\nScores are optimizer utility, not predicted fitness outcomes. The default beam width remains 3 unless the matrix shows a repeatable quality improvement that justifies additional latency; one case alone is not used to change policy.\n\n## Profiling and limits\n\nAn initial cold-start run took about 2,097 ms. Bun CPU profiling showed repeated muscle-volume aggregation inside candidate scoring as the dominant sampled stack. Computing one scoring context per partial session and iterating only known set roles reduced that same cold-start run to about 508 ms. This is an algorithmic change with invariant/scenario regression tests. No native code or optimization dependency was needed. Indexes are reusable for analytics, validation and queries. Generation currently builds its own index once per request.\n\nThese are desktop development measurements, not iPhone benchmarks or a latency SLA. Several-thousand-exercise inputs and very long histories should be profiled on target hardware before UI integration. The pure synchronous API can be called from a future Web Worker without redesigning the domain. Persisted programs include a policy snapshot; payload size trades off against reproducibility.\n`
)
console.log(JSON.stringify(results, null, 2))
