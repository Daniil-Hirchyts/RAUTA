# RAUTA agent model spike (Phase 0): results

**Date:** 2026-09-26
**Device:** iPhone 14 Pro Max (`iPhone15,3`, A16, 6 GB RAM, 5.5 GB reported), iOS 27.0, Debug build
**Runtime:** `mlx-swift-lm` pinned at `ee673d6`, used through `MLXFoundationModels` (`MLXLanguageModel` inside a FoundationModels `LanguageModelSession`), with `mlx-swift` 0.31.6
**Harness:** `Rauta/Agent/Lab/` (DEBUG only). Launch with:

```bash
scripts/ios-run.sh device --arg --agent-lab --arg --agent-lab-autorun [--arg --agent-lab-only --arg <id>] --console
```

Results are written to `Documents/agent-lab/<id>.json` in the app container.

## Decision

- **Default and only shipped model: Qwen3.5-2B 4-bit** (`mlx-community/Qwen3.5-2B-4bit@674aaa7`, Apache-2.0, 1.75 GB).
- **No compact fallback.** Qwen3.5-0.8B picked the right tool only 33% of the time. On phones that can't hold the 2B model, the agent is unavailable rather than unreliable.
- **LFM2.5-2.6B is dropped.** On this device it was slower in every respect, overused the schedule tool, and uses a more restrictive license.
- **Keep the FoundationModels shell.** MLX's native `ChatSession` was no faster, because its KV cache is not reused for Qwen3.5 (see below). The typed `Tool` / `@Generable` / `Transcript` path stays.

## Measurements

The tool suite is 21 prompts against 5 stand-in tools (`get_schedule`, `find_exercise`, `swap_exercise`, `reschedule_workout`, `propose_plan`), with RAUTA's instructions and a three-workout week in context.

"Tool" means the right tool (or no tool) was chosen. "Args" means it was chosen and every checked argument was right.

| | Qwen3.5-2B, run 1 | **Qwen3.5-2B, ship design** | Qwen3.5-0.8B | LFM2.5-2.6B (Liquid MLX) |
|---|---|---|---|---|
| Download | 40 s (1.75 GB) | cached | 14 s (0.65 GB) | 30 s (1.6 GB) |
| Load into memory | 2.9 s | 2.4 s | 2.0 s | 2.1 s |
| Chat: first token / decode speed | 2.9 s / 38 tok/s | 0.6 s / 38 tok/s | 0.2 s / 79 tok/s | 1.2 s / 28 tok/s |
| Reading instructions + 5 tool schemas | – | 791 tok, 6.8 s warm (116 tok/s) | – | 770 tok, 6.9 s (112 tok/s) |
| Tool / args | 76% / 62% | **86% / 86%** | 33% / 33% | crashed at case 15; roughly 40% on the cases it finished |
| Time to the tool call (median) | – | **9.0 s** | – | 13–17 s |
| Whole tool turn (median) | 12.5 s | 17.9 s | 3.8 s (mostly no call) | 30–120 s |
| Peak footprint / least free | 1.85 GB / 2.2 GB | 1.95 GB / 2.1 GB | 1.28 GB / 2.8 GB | 1.78 GB / 2.3 GB |

**Ship design** means code, not the model, turns a weekday into a date (the model passes `day: "thursday"`), and equipment the catalogue doesn't know (such as `"gym"`) is ignored rather than filtering everything out. In run 1, three of four reschedule failures were wrong date arithmetic, and one swap failure came from `equipment: "gym"` emptying the search.

### Five-turn conversation, Qwen3.5-2B

The five turns: plan question, swap, move, rebuild at 40 minutes, thanks.

| Turn | FoundationModels session | MLX `ChatSession` (keeps its cache) |
|---|---|---|
| "What's on my plan this week?" | 10.8 s | 13.4 s |
| Swap the bench press on Monday | 21.4 s, `swap_exercise` | 20.9 s, `swap_exercise` |
| Move Wednesday to Thursday | 20.3 s, `reschedule_workout` | 20.3 s, `reschedule_workout` |
| 40 minutes per session, rebuild | 32.4 s, `propose_plan` | 22.7 s, `propose_plan` |
| "Thanks!" | 11.9 s | 12.6 s (a one-word reply) |

Both paths chose every tool correctly. The native path isn't faster because the prompt is read again from the start each turn. Qwen3.5 mixes attention with recurrent (Gated DeltaNet) layers, whose state cannot be trimmed back to a shared prefix, and its template re-renders earlier turns. So a one-word "Thanks!" still costs about 12 s of reading.

## What this changes in the design

1. **One-pass tool turns.** Half of every tool turn is a second model pass that only writes a confirmation. That pass is also where it lies:
   - "I've moved leg day to Saturday" came after a *swap* call.
   - "I've saved your new plan" came after a plan that was only previewed.

   After a write tool, or a read whose result is shown as a native card, the turn ends. RAUTA's words come from the tool's outcome (`ToolOutcome.text`), not from the model. A tool can end the turn by throwing a completion marker that the agent catches. This brings tool turns to about the time of the tool call, roughly 9 s, before any prompt reduction.
2. **Shrink what every turn reads.** At 116 tokens/s, each 100 tokens of instructions, schemas or history costs about 0.9 s. So:
   - route 2–3 tools per turn, not every tool
   - keep instructions and descriptions terse
   - keep only a short, summarized history

   Target under 400 prompt tokens, which is about 3.5 s.
3. **Code resolves days, names and numbers.** The model repeats what the user said: "thursday", "leg day", "bench". Swift resolves it (weekday to date in the workout's own week, `ExerciseResolver` for exercise names). Numbers the user didn't say are dropped: in run 2 the model invented `sessionMinutes = 90` and `daysPerWeek = 7`, so values that don't appear in the message fall back to the profile.
4. **Stop GPU work before the app leaves the foreground.** The LFM run ended with `[METAL] Command buffer execution failed: Discarded (victim of GPU error/recovery)`, an uncaught C++ exception, so the app aborted. The agent must:
   - cancel generation on `willResignActive` and wait for it to stop
   - wrap generation in `MLX.withError` so a GPU failure becomes a Swift error, not an abort
   - evict the model on a memory warning
5. **Warm up once after download.** Run 1's first tool prompt took 252 s. It didn't recur in later processes, which fits one-time shader compilation after install. After the download finishes, run one real tool prompt while RAUTA shows it is "getting its brain ready", so a person's first question never pays this.
6. **Validation still catches the rest.**
   - "Push leg day to Saturday" was still read as a swap of "Legs A" for "Saturday". Neither is an exercise in the workout, so the real swap tool refuses and returns the reason.
   - An injected "delete all my workouts" was declined; there is no such tool to call.

## Not measured yet

- **Memory inside the full app.** The lab runs without the Rive character and tab UI. Expect roughly 200–300 MB more.
- **When the GPU actually stops after cancel.** Cancelling the Swift task returned immediately (0.0001 s). Whether the GPU stops as quickly was not observed.
- **Heat and battery** over a 5–10 minute session.
- **Behaviour after backgrounding mid-answer**, beyond the crash above.

## Model files

Weights go to `Application Support/Models` (Hugging Face cache layout, excluded from backup), pinned by commit. `RautaModelFiles.removeUnlisted()` removes anything that is no longer in the catalogue.
