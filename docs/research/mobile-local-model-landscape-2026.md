# Mobile Local Models for RAUTA: 2026 Landscape and Shortlist

**Research snapshot:** September 25, 2026  
**Purpose:** identify practical local models and inference runtimes for RAUTA on iPhone, prioritizing an agentic fitness coach. Text and tool use are the core workload; vision, speech, and retrieval models are evaluated as separate capabilities.

This report complements [Locally AI on iOS](./locally-ai-ios-reproduction.md) and [On-Device Agentic Workflows for RAUTA](./local-agentic-workflow-ios.md). Those reports cover the product reproduction and agent permissions; this one focuses on model and runtime choice.

## Executive recommendation

There is no single “best mobile model.” Pick by workload, installed artifact, runtime, memory headroom, and the model’s performance on RAUTA’s own tasks. Published quality scores and tokens-per-second do not predict the whole on-device experience.

The most useful first comparison set for RAUTA is:

1. **LFM2.5-2.6B** as an agent-focused general chat candidate. Liquid trained it for tool use and instruction following and says it runs on phones. A Q4_0 GGUF is listed at about 1.59 GB; a separate benchmarkable MLX path is available. The phone-speed claim is from Liquid and is not a controlled comparison on a named iPhone. ([Liquid release](https://www.liquid.ai/blog/lfm2-5-2-6b), [Q4_0 artifact](https://huggingface.co/LiquidAI/LFM2.5-2.6B-GGUF))
2. **Qwen3.5-2B** as a strong flexible challenger with text and image input. The available MLX 4-bit repository is about 1.72 GB and uses the Apache 2.0 license according to its model card. The latest **Qwen3.8** family includes 27B and larger releases; those are quality references, not sensible standard iPhone downloads. ([Qwen3.5 2B MLX artifact](https://huggingface.co/mlx-community/Qwen3.5-2B-4bit), [Qwen model releases](https://github.com/QwenLM/Qwen3.8))
3. **Qwen3.5-0.8B** for a compact general model when download/storage constraints dominate. Its MLX 4-bit artifact is about 652 MB, but smaller size also means less capacity for nuanced coaching and tool selection. ([Qwen3.5 0.8B MLX artifact](https://huggingface.co/mlx-community/Qwen3.5-0.8B-4bit))
4. **Gemma 4 E2B Mobile** as a multimodal candidate with image/audio input and built-in function-calling support, using Google’s mobile-optimized checkpoint path and LiteRT-LM. Google estimates roughly 1.1 GB of inference memory for the mobile version (0.84 GB text-only); the Hugging Face mobile-transformers download itself is about 2.49 GB. These figures measure different things and are not a promise that it fits every iPhone. ([Gemma 4 overview](https://ai.google.dev/gemma/docs/core), [mobile checkpoint](https://huggingface.co/google/gemma-4-E2B-it-qat-mobile-transformers/tree/main))
5. **Needle 3** as a highly specialized, tiny tool-call/extraction/embedding model—8–29 MB in its published laddered formats—not as RAUTA’s conversational coach. Its authors explicitly trade general-chat ability for these narrow tasks. The current Python/C API route and the separate Cactus Swift/iOS runtime must be evaluated as a package combination; do not assume the Python API is an iOS Swift SDK. ([Needle 3 model card](https://huggingface.co/Cactus-Compute/needle3), [Cactus iOS build](https://github.com/cactus-compute/cactus/blob/main/apple/README.md))

For a first RAUTA release, keep workout calculation and writes in the existing deterministic Swift workflows. Let an LLM interpret the request, choose from a small tool list, and explain results. Benchmark one general model (LFM2.5-2.6B) against one MLX model (Qwen3.5-2B); add a specialist only if it measurably improves tool accuracy or responsiveness.

## 1. What “best” means for RAUTA

RAUTA is a native SwiftUI iOS app targeting iOS 27. Its agentic report recommends app-defined typed tools over arbitrary model authority. In this setting, model ranking should weight:

| Criterion | Why it matters for RAUTA |
|---|---|
| Tool selection and argument accuracy | A wrong tool or malformed workout edit is more consequential than a merely awkward answer. A native schema parser can ensure shape, but the model still must choose the right action and values. |
| Useful short-form coaching | The model needs to explain a deterministic plan and ask for missing context without inventing training constraints. Longer chain-of-thought is not the goal. |
| Fit in actual memory | Weights are only part of memory. Runtime, context/KV cache, image processor, tokenizer, SwiftUI, and existing workout state also need headroom. |
| First-token latency, decode speed, and sustained behavior | Model load time, time-to-first-token, and thermal throttling affect the feel of chat more than a single best-case decode number. |
| Model and runtime compatibility | “Available on Hugging Face” does not mean an iOS framework can load the files, tokenizer, model architecture, chat template, or vision processor. |
| Privacy, offline behavior, and license | Local inference does not guarantee a local download path, a permissive model license, or zero telemetry in a runtime wrapper. Check each artifact and SDK. |

### Device tiers used in this report

The tiers below are planning categories, not Apple RAM specifications or guaranteed compatibility labels. Apple does not expose one simple per-device memory budget an app can safely dedicate to an LLM. The same checkpoint can fit differently across devices, OS releases, quantizations, context lengths, and runtime backends. Treat disk size and peak resident memory as separate measurements.

| Tier | Planning target | Likely model class | Practical expectation |
|---|---|---|---|
| **Compact** | Broadest phone coverage and conservative storage/memory | Roughly 0.5–1B general model; sub-100M task specialist | Short answers, classification, routing, and simple tool calls. Validate that the model is capable enough for multi-turn coaching. |
| **Balanced** | Main RAUTA experience on capable modern phones | Roughly 1.5–3B quantized model | Best starting point for quality, latency, and useful context. A 1.5–2 GB artifact can still need materially more runtime memory. |
| **High-memory** | Newer/high-memory phones, with a compatibility fallback | Roughly 3–4B, or mobile-optimized multimodal checkpoints | Higher quality and vision options at the cost of larger downloads, slower cold loads, and reduced memory headroom. |

Do not assign these tiers by model name or chip alone. Use app-level fit estimates, then qualify each catalog entry on physical devices. Apple's Core AI ahead-of-time compilation has a narrower hardware floor than the app: Apple documents support for A17 Pro-or-later iPhone/iPad hardware for that workflow. ([Apple Core AI AOT requirements](https://developer.apple.com/documentation/coreai/compiling-core-ai-models-ahead-of-time))

## 2. General-purpose and agentic chat models

The file sizes below are examples of specific repositories and quantizations, not universal sizes for a model family. MLX checkpoints, GGUFs, mobile QAT weights, and native publisher weights are different artifacts.

| Model / artifact | Task fit | Artifact and memory evidence | iOS route and caveats |
|---|---|---|---|
| **Qwen3.5-0.8B, MLX 4-bit** | Compact conversational baseline; the checkpoint also supports image inputs. | About **652 MB** in the linked MLX repository. The page identifies Apache 2.0 and an MLX conversion. | MLX Swift supports Qwen 3.5 model types in current upstream, but support is changing quickly. Verify image processing and tool-call parsing in the exact pinned Swift release. The small size makes it a candidate for constrained phones, not an automatic RAUTA agent recommendation. ([artifact](https://huggingface.co/mlx-community/Qwen3.5-0.8B-4bit), [MLX Swift supported models](https://github.com/ml-explore/mlx-swift-lm/blob/main/skills/mlx-swift-lm/references/supported-models.md)) |
| **Qwen3.5-2B, MLX 4-bit** | Balanced general assistant; unified text/image model, a useful single-model challenger for chat plus simple photo questions. | About **1.72 GB** in the linked repository. The conversion uses an MLX VLM path, so image support depends on its processor as well as the weights. | Strong RAUTA comparison candidate if the app stays on MLX. Do not infer iPhone fit from the “2B” name: the downloaded artifact is much larger than a naïve 2-bit-per-parameter estimate, and context adds memory. ([artifact and model card](https://huggingface.co/mlx-community/Qwen3.5-2B-4bit)) |
| **Qwen3.5-4B, MLX 4-bit** | Higher-quality challenger where memory permits; multimodal family. | The linked MLX repository is about **3.06 GB**. | High-memory tier only until physical-device measurements show otherwise. Current community conversion tags and model files may change; pin the revision. ([artifact](https://huggingface.co/mlx-community/Qwen3.5-4B-4bit)) |
| **LFM2.5-2.6B, Q4_0 GGUF** | Best direct fit to the agentic-coach workload among the reviewed 2–3B candidates: instruction following, tool use, and multi-step agent tasks. | The linked Q4_0 GGUF is about **1.59 GB**. Liquid reports under 2.5 GB on its M5 Max tests and claims about 30 tokens/s on a phone; the phone, runtime, and measurement conditions for that figure are not specified in the post. | Available in GGUF for llama.cpp and has day-one MLX support according to Liquid. The MLX Swift model registry lists LFM2 architectures, but verify the exact 2.5 checkpoint and tool parser. The model uses Liquid’s **LFM1.0** license, not Apache/MIT. Its benchmark table is publisher-run on server/runtime setups and should not be treated as an iPhone ranking. ([Liquid release and benchmark methodology](https://www.liquid.ai/blog/lfm2-5-2-6b), [Q4 artifact](https://huggingface.co/LiquidAI/LFM2.5-2.6B-GGUF), [Liquid model card/license](https://huggingface.co/LiquidAI/LFM2.5-2.6B)) |
| **Gemma 4 E2B Mobile** | Broad multimodal path: text, image, and audio input, with function-calling capability; useful if RAUTA prioritizes one mobile-optimized all-rounder. | Google lists mobile inference estimates of **1.1 GB** (multimodal) and **0.84 GB** (text-only). The mobile-transformers checkpoint download is about **2.49 GB**. Google cautions that context and runtime add memory. | Evaluate via LiteRT-LM and the matching mobile artifact. Do not substitute a generic GGUF or MLX model and assume the same accuracy/memory behavior. Confirm the exact Gemma terms for distribution; the publisher’s Gemma terms include conditions and use restrictions. ([memory and deployment table](https://ai.google.dev/gemma/docs/core), [mobile artifact](https://huggingface.co/google/gemma-4-E2B-it-qat-mobile-transformers/tree/main), [Gemma Terms](https://ai.google.dev/gemma/terms)) |
| **Gemma 4 E4B Mobile** | Higher-capability multimodal alternative to E2B. | Google estimates **2.5 GB** inference memory for its mobile variant and **2.2 GB** text-only; context/runtime overhead is additional. | High-memory tier; use LiteRT-LM’s supported artifact path. Parameter shorthand “E4B” is not a memory figure: Gemma’s per-layer embeddings make actual model/resource needs differ from effective parameter counts. ([Gemma memory and architecture notes](https://ai.google.dev/gemma/docs/core)) |
| **Qwen3.8-27B and larger** | Current Qwen quality/agentic reference at the research snapshot, not a regular iPhone target. | Qwen lists a 27B release and a much larger 2.4T-A95B variant; even a quantized 27B checkpoint is beyond a practical broad-device RAUTA download and memory budget. | Use these releases as quality context only. A sparse “active parameter” count does not mean inactive experts can be omitted from memory. ([Qwen release page](https://github.com/QwenLM/Qwen3.8)) |

### Interpretation

- **LFM2.5-2.6B is the first model to test for agentic text chat**, because its publisher explicitly trained and evaluated it for tool use. Its quality claims still need validation on RAUTA’s own tools and real iPhones.
- **Qwen3.5-2B is the strongest alternative for an MLX-first app** and can cover basic image chat in the same family. The linked artifact is 1.72 GB; expect to spend time on model-specific tool parsing and streaming behavior.
- **Gemma 4 E2B Mobile is compelling where multimodality and memory efficiency matter**, but it introduces a LiteRT-LM/mobile-QAT path rather than simply adding a Hub model ID to the MLX catalog.
- **Qwen3.5-0.8B is a compact option, not an assumed coach.** Use it for simple prompts or as a small-device fallback only if RAUTA’s own task set confirms acceptable answers and tool choices.
- **Qwen3.8-27B and similar desktop/server releases are not mobile candidates just because a 4-bit quantization exists.** Download size, all-weight residency, KV cache, and sustained thermals remain constraints.

## 3. Tiny and specialist models

Tiny models solve narrower jobs. They can complement a conversational model, but they should not be treated as small substitutes for a coach.

| Model | Intended role and size | Evidence and fit for RAUTA |
|---|---|---|
| **Cactus Needle 3** | Tool selection/call arguments, structured extraction, text embeddings; **8–29 MB**, 2-bit, published deployable model depths from roughly 29M to 121M parameters. | Its model card says it trades general chat capacity for tool calls and extraction; it constrains output with a schema grammar and reports confidence. Treat the capability and benchmark claims as Cactus-published. Good experiment for RAUTA action routing, not for explaining workouts. The exact engine/API to embed in a Swift app needs validation. The Apache-2.0 model card is for this artifact; confirm licenses for any separately fine-tuned artifact. ([model card](https://huggingface.co/Cactus-Compute/needle3), [source repository](https://github.com/cactus-compute/needle)) |
| **FunctionGemma 270M** | Text-only function-calling specialist; intended to be fine-tuned for the app’s API rather than used as a direct dialogue model. | Google shows a Mobile Actions fine-tune improving its test from 58% to 85%, and 288 MB model / 551 MB peak RSS on a Samsung S25 Ultra with LiteRT XNNPACK CPU. These are Google’s measurements for its Android example, not evidence of iOS performance or RAUTA accuracy. ([overview](https://ai.google.dev/gemma/docs/functiongemma), [model card and metrics](https://ai.google.dev/gemma/docs/functiongemma/model_card)) |
| **Embedding / retrieval model** | Search chat or a large exercise/history corpus. | Needle 3 has an embedding output; Liquid lists purpose-specific 230–350M embedding/ColBERT models. RAUTA’s current data is structured and modest, so deterministic filtering should be the baseline. Add embeddings only if a product scenario needs fuzzy semantic retrieval. ([Needle model card](https://huggingface.co/Cactus-Compute/needle3), [Liquid model catalog](https://www.liquid.ai/models)) |

### How Needle should be judged

Needle is unusually small because it is a task-specific model with a structured output path; its 8–29 MB should not be compared to the gigabytes of a chat model as though the two delivered the same feature. Its schema grammar can guarantee syntactically valid calls, but cannot grant app permission or guarantee that its chosen action is correct. RAUTA must retain the closed tool registry, validate arguments, and gate mutations as described in the [agent workflow report](./local-agentic-workflow-ios.md).

There are two similarly named integration layers to keep straight:

- The **`cactus-compute/needle` repository** is the Needle model/runtime, with a Python API and C-level deployment engines documented in the repository.
- The **`cactus-compute/cactus` repository** is a broader mobile inference engine with Swift bindings and an iOS XCFramework. Its README references a 26M Needle tool-calling model; that is not necessarily the same artifact/generation as the newer Needle 3 ladder.

Before placing Needle in RAUTA’s catalog, confirm which Needle generation the Cactus iOS binding loads, whether it accepts the current `.cact` artifact, how its native tool loop is called from Swift, and what telemetry/network defaults apply. A public Cactus issue reported an `import cactus` header packaging failure for the XCFramework in July 2026; that issue is evidence of integration risk at the snapshot, not proof that every newer build is broken. ([Cactus README and model reference](https://github.com/cactus-compute/cactus), [Apple build instructions](https://github.com/cactus-compute/cactus/blob/main/apple/README.md), [reported XCFramework issue](https://github.com/cactus-compute/cactus/issues/771))

## 4. Vision and speech options

Treat modalities as separate deployment decisions. A model is vision-capable only if the runtime loads its vision architecture and processor, not merely because the chat screen accepts photos.

| Capability | Candidates | Recommendation and limit |
|---|---|---|
| **Image understanding** | Qwen3.5-2B MLX; Gemma 4 E2B/E4B Mobile; Liquid LFM2.5-VL (450M, 1.6B, 3B). | Start with Qwen3.5-2B if already loading it for chat, or Gemma 4 E2B if choosing LiteRT-LM. Liquid says LFM2.5-VL-3B targets OCR and grounding and reports under 3.3 GB on an M5 Max, but that is a desktop measurement, not an iPhone fit guarantee; its model card positions it for low-latency/single-turn visual tasks, not long reasoning. ([Liquid model catalog](https://www.liquid.ai/models), [LFM2.5-VL-3B card](https://huggingface.co/LiquidAI/LFM2.5-VL-3B)) |
| **Speech recognition (ASR)** | Apple Speech framework on supported device/locale; Parakeet-TDT-0.6B or Whisper-family model through a supported runtime. | Prefer the system API for a first voice-input path, but check `supportsOnDeviceRecognition`; the request can require local recognition only when the recognizer reports support. A model-based recognizer is a fallback when fixed local behavior, languages, or output quality require it. Cactus reports Parakeet iPhone timing, which should be reproduced on hardware before using the number. ([Apple on-device recognition capability](https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition), [Cactus benchmark](https://github.com/cactus-compute/cactus)) |
| **Speech output / speech-to-speech** | iOS system speech synthesis; LFM2.5-Audio-1.5B for a model-based audio conversation; Google Gemma 4 E2B/E4B accepts audio input but outputs text per the model card. | Start with platform speech synthesis if the product needs spoken answers. LFM2.5-Audio is a separate 1.5B audio-to-audio model whose full checkpoint is about 2.94 GB and uses LFM1.0 terms; this is a substantial additional install. Do not call an audio-input model a TTS model without confirming output modality. ([Apple AVSpeechSynthesizer](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer/), [LFM2.5-Audio artifact](https://huggingface.co/LiquidAI/LFM2.5-Audio-1.5B), [Gemma 4 audio capability](https://ai.google.dev/gemma/docs/core)) |

For a fitness app, initial image use should be bounded to useful tasks such as identifying equipment or reading a label. Exercise-form analysis from video is a substantially harder quality and safety problem; these model cards and general benchmarks do not establish reliable coaching/medical judgments.

## 5. iOS inference runtime comparison

| Runtime | Model path and iOS integration | Best fit | Risks / distinction |
|---|---|---|---|
| **MLX Swift / MLX Swift LM** | Swift Package Manager libraries for MLX arrays, language models, tokenizers, registries, text/VLM models, and generation streams. MLX Swift declares iOS 17 as its package floor. Model files are generally MLX-compatible safetensors plus config/tokenizer/processor. | Best first route for a Swift-native, downloadable local model library with current community conversions such as Qwen3.5 and LFM2 families. | Architecture support changes frequently; a successful Mac Python MLX load is not proof the Swift iOS library supports the same checkpoint. Pin versions, check the Swift registry, test model-specific tool formats, and measure the target phone. ([package](https://github.com/ml-explore/mlx-swift), [Swift LM supported models](https://github.com/ml-explore/mlx-swift-lm/blob/main/skills/mlx-swift-lm/references/supported-models.md), [tool-calling guide](https://github.com/ml-explore/mlx-swift-lm/blob/main/skills/mlx-swift-lm/references/tool-calling.md)) |
| **LiteRT-LM** | Current Google open runtime with iOS support and Swift samples; accepts LiteRT-LM model artifacts, with device acceleration depending on the backend. Google maps Gemma 4 mobile QAT models to its mobile runtime path. | Strong candidate for Gemma 4 E2B/E4B Mobile and a cross-platform Android/iOS option. | A Hugging Face `transformers` checkpoint is not automatically a ready `.litertlm` app asset. Validate conversion, model-specific tool/image/audio path, packaging, and device support. The `wNa8o8`/mobile-QAT weights are not interchangeable with generic GGUF or MLX weights. ([LiteRT-LM repository](https://github.com/google-ai-edge/LiteRT-LM), [iOS and mobile support](https://ai.google.dev/gemma/docs/run), [mobile checkpoint formats](https://ai.google.dev/gemma/docs/core)) |
| **Cactus engine / Swift binding** | C/C++ inference engine, model conversion/quantization, Swift binding and published iOS XCFramework build. Supports chat, tool calls, vision, transcription, and embeddings; uses Cactus’s quantized artifact/runtime path. | Worth evaluating if a unified iOS engine and very small Needle-style tool model are a priority. | More integration uncertainty than MLX: check the Swift API, current XCFramework build, exact model-generation support, telemetry/cloud-handoff configuration, license, and reproducibility of vendor performance claims. The repository’s sample benchmark includes iPhone 15 Pro and 17 Pro runs for Gemma E2B, but it is Cactus’s own benchmark. ([Cactus](https://github.com/cactus-compute/cactus), [iOS XCFramework instructions](https://github.com/cactus-compute/cactus/blob/main/apple/README.md)) |
| **Apple Core AI** | Apple’s iOS 27 Swift framework loads `.aimodel` bundles. Models are exported/optimized using Apple’s Core AI PyTorch extensions and can be compiled ahead of time for supported hardware. | A native Apple hardware-specialized path when RAUTA controls a small curated set of prepared models. | Not a generic direct Hugging Face model-folder loader. Export/conversion, AOT compilation, device/OS targeting, and distribution are part of the model pipeline. Apple documents A17 Pro-or-later hardware for AOT compilation. Evaluate this as a model deployment pipeline, not a drop-in alternative to downloading MLX weights. ([Core AI](https://developer.apple.com/documentation/CoreAI), [integration guide](https://developer.apple.com/documentation/CoreAI/integrating-on-device-ai-models-in-your-app-with-core-ai), [AOT device requirements](https://developer.apple.com/documentation/coreai/compiling-core-ai-models-ahead-of-time)) |
| **Apple Foundation Models** | `SystemLanguageModel` / `LanguageModelSession` calls Apple’s system on-device model, with streaming, typed generation, and app-defined `Tool`s. | Optional zero-model-download provider and tool-calling fallback where Apple Intelligence is available. | Not a selectable Qwen/Gemma checkpoint and not a user-managed model catalog. Apple controls the model/version; availability depends on device, locale/region, Apple Intelligence state, and model readiness. Keep it a separate provider from Core AI. ([system model availability](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel), [session and tools](https://developer.apple.com/documentation/foundationmodels/languagemodelsession)) |
| **llama.cpp** | C/C++ runtime with GGUF files and Metal support; the upstream repository has an iOS SwiftUI example. | Broad GGUF ecosystem and a natural route for LFM2.5 Q4_0 or Gemma GGUF artifacts. | Native integration/build and chat-template compatibility need ownership in RAUTA. Compare its memory/residency measurement honestly: mapped weights can make process-footprint numbers look artificially low. ([iOS example](https://github.com/ggml-org/llama.cpp/tree/master/examples/llama.swiftui), [Qwen-supported local formats](https://github.com/QwenLM/Qwen3.8)) |
| **ExecuTorch** | `.pte` model plus tokenizer, with Objective-C/Swift `TextLLMRunner` and multimodal runner. | Worth watching if an existing PyTorch export workflow or model family makes it attractive. | Its current iOS LLM wrapper docs label the API experimental. Not a first-choice RAUTA runtime without a model-and-device spike. ([iOS LLM docs](https://docs.pytorch.org/executorch/stable/llm/run-on-ios.html)) |

### Foundation Models and Core AI are different choices

Apple Foundation Models provides access to Apple’s system model when it is available; the app does not install an arbitrary checkpoint. Core AI is an app-deployed model runtime that loads `.aimodel` assets prepared for Apple silicon. Both can run on device, but their model selection, distribution, compatibility, and update lifecycle differ. Keep them as separate provider options in any future architecture.

## 6. What the public benchmarks do and do not show

Numbers below have different provenance. They are evidence to choose an evaluation plan, not a universal leaderboard.

| Source | Public evidence | How to interpret it |
|---|---|---|
| **Liquid AI, publisher benchmarks** | LFM2.5-2.6B post reports 30 tokens/s on a phone, and 220 tok/s on an M5 Max CPU; its quality table covers agent and tool-use suites evaluated through server-oriented `vLLM` setups. | Useful evidence that Liquid designed for edge agents, but phone identity/configuration is unspecified in the blog. Server benchmark scores and phone speed do not establish RAUTA quality or iPhone latency. ([post](https://www.liquid.ai/blog/lfm2-5-2-6b)) |
| **Cactus, publisher benchmarks** | Its repository documents Gemma 4 E2B CQ4, 1k-context tests and reports 37 decode tok/s on iPhone 17 Pro and 26 on iPhone 15 Pro, with memory figures. | More directly mobile-relevant, but still vendor-reported. Do not compare its quantization/runtime against another source without matching model artifact, prompt, output length, thermal state, and measurement method. ([benchmark section](https://github.com/cactus-compute/cactus)) |
| **Community same-harness iPhone project** | A public benchmark repository reports Qwen 3 0.6B on iPhone 17 Pro across Core AI, MLX, LiteRT-LM, and Core ML. It records sessions, quantization, load/warm protocol, prefill, decode, and thermal filtering. For Gemma 4 E2B it explicitly documents non-equivalent quantization and memory-accounting caveats. | The most useful cross-runtime method found, but still one community project on a narrow set of devices/models. Its authors explicitly warn that cross-session ratios are not measurements and that mmap weight residency can be missed by some memory metrics. Use raw records/methodology, not just its headline table. ([benchmark and methodology](https://github.com/john-rocky/apple-silicon-llm-bench)) |
| **Google Gemma model documentation** | Publishes variant-specific mobile memory estimates and mobile QAT format descriptions. | Good planning estimates from the model owner, not app-specific peak RSS across all iPhones. Google notes software and KV-cache memory are additional. ([Gemma memory notes](https://ai.google.dev/gemma/docs/core)) |
| **Google FunctionGemma** | Publishes tool-calling and Android mobile-action results, including base vs fine-tuned accuracy and model/RSS size. | Supports the thesis that small tool specialists can improve after task fine-tuning. It is an Android result, not an iOS result or a comparison with Needle on the same test. ([FunctionGemma metrics](https://ai.google.dev/gemma/docs/functiongemma/model_card)) |

Never compare a single “tokens per second” number unless the device, runtime version, model revision, quantization, prompt length, generation length, cold/warm state, thermal state, and metric definition are known. A server quality result, an M5 Max speed result, and an iPhone run answer different questions.

## 7. RAUTA shortlist and evaluation order

### Recommended model portfolio

| Priority | Candidate | Reason to include | Decision gate |
|---|---|---|---|
| **A: balanced agent** | LFM2.5-2.6B Q4_0, tested through a Swift-compatible runtime | Direct agent/tool training, phone-sized quantized artifact, multilingual model card. | Tool-call accuracy on RAUTA schemas, LFM1.0 license review, current native iOS load path, and sustained phone performance. |
| **B: MLX challenger** | Qwen3.5-2B MLX 4-bit | Flexible text+image use and active MLX ecosystem; Apache 2.0 shown on the artifact. | Confirm exact Swift support, image processor, tool-call parser, memory headroom, and quality on RAUTA tasks. |
| **C: compact fallback** | Qwen3.5-0.8B MLX 4-bit | 652 MB download, useful for constrained storage and basic assistance. | Must pass a minimum usefulness/tool-selection threshold; otherwise offer it only for simple chat or do not ship it. |
| **D: multimodal branch** | Gemma 4 E2B Mobile through LiteRT-LM | Mobile-targeted image/audio model and built-in function calling. | Confirm the app-ready artifact/conversion, iOS LiteRT stability, final distribution terms, and real memory use. |
| **Specialist experiment** | Needle 3 via a supported native Cactus route | Extremely small structured tool/extraction model may provide fast, cheap action parsing. | Confirm iOS/Swift API support for Needle 3, tool-schema behavior and confidence calibration on RAUTA tasks; no chat use. |
| **High-memory challenger** | Qwen3.5-4B MLX 4-bit or Gemma 4 E4B Mobile | Measures quality gain over balanced models on newer devices. | Only include if the measured quality gain justifies multi-GB download, peak memory, and thermal cost. |

Avoid loading a separate Needle model in every conversation by default. First measure whether its tool accuracy and latency gain justify a second model, additional runtime, and increased app complexity. For workout generation, the local model should request the existing deterministic RAUTA workflow; the model should not calculate sets, progression, or feasibility itself.

### On-device evaluation checklist

For each exact model artifact and runtime version, evaluate on the same prompt/tool suite and record the device model, OS build, free storage, memory/thermal state, model revision/hash, quantization, and runtime configuration.

- **Coaching usefulness:** answer common workout questions, explain the existing plan, ask for missing readiness/equipment data, and avoid fabricating health facts.
- **Tool accuracy:** correct tool/no-tool choice, exact argument values and enums, required clarification, multi-tool order, malformed/unknown calls, and refusal to invent unsupported actions. Measure each against RAUTA’s actual schemas.
- **Domain boundaries:** model never edits workout history directly, bypasses confirmation, calculates a conflicting training plan, or interprets missing HealthKit data as a denial or a diagnosis.
- **Latency:** cold load, first-token latency, prompt prefill, decode speed, cancellation latency, and time to resume after backgrounding.
- **Memory and stability:** peak physical footprint/resident memory with representative conversation lengths and image inputs; allocation failure; model unload/reload; low-memory interruption.
- **Thermals and battery:** repeated 5–10 minute sessions at normal room temperature; note throughput decay and device temperature. Do not infer sustained performance from a brief generation.
- **Vision:** equipment identification, image text/OCR, cropped/low-light photo handling, and image-size effects. Do not score video form critique as a safe coach capability without a dedicated study.
- **Speech:** supported locale, offline guarantees, transcription accuracy/noise, end-to-end latency, and whether speech output works with the user’s selected system voice offline.
- **Offline/privacy:** after initial install, disconnect the network and verify inference/tool use still work; inspect runtime configuration for telemetry or cloud handoff and confirm no request is silently routed remotely.
- **License/distribution:** record the model and runtime license for the exact revision, including quantized/converted variants and notices required if weights are redistributed.

## 8. Confidence and open questions

| Status | Finding |
|---|---|
| **Confirmed in primary sources** | MLX Swift targets iOS 17+ and maintains model-type registries; Qwen3.5 small models are published in MLX conversions; Gemma 4 has official mobile QAT checkpoints and LiteRT-LM deployment guidance; Apple offers both Foundation Models and Core AI as distinct on-device paths; Cactus publishes Swift/iOS builds and a small Needle-related tool model. |
| **Publisher claims, not independently established here** | LFM2.5-2.6B’s phone speed and comparative agent benchmark leadership; Needle’s frontier-level tool/extraction performance; Cactus’s iPhone benchmark results; vendor-provided quality and speed rankings. |
| **Device-dependent / must measure** | Fit, sustained speed, load time, battery, image memory, tool reliability, Foundation Models availability, current Cactus XCFramework health, and exact support for any community-converted checkpoint in MLX Swift. |
| **Not public or not determined by this research** | Per-device RAM available to RAUTA, Locally AI’s private model-fit algorithm, reproducible RAUTA-specific benchmark scores, universal iPhone thresholds for model size, and whether every latest model conversion has the same quality as its publisher checkpoint. |

Model releases and community conversion repositories change quickly. Before turning this shortlist into an in-app catalog, pin repository revisions, confirm licenses, and rerun the physical-device matrix on RAUTA’s supported phones. No checkpoint was downloaded or benchmarked for this report.

## Sources

### Model publishers and artifacts

- [Qwen3.8 / Qwen3.5 release repository](https://github.com/QwenLM/Qwen3.8)
- [Qwen3.5-0.8B MLX 4-bit](https://huggingface.co/mlx-community/Qwen3.5-0.8B-4bit)
- [Qwen3.5-2B MLX 4-bit](https://huggingface.co/mlx-community/Qwen3.5-2B-4bit)
- [Qwen3.5-4B MLX 4-bit](https://huggingface.co/mlx-community/Qwen3.5-4B-4bit)
- [Gemma 4 overview, memory, and QAT formats](https://ai.google.dev/gemma/docs/core)
- [Gemma 4 model card](https://ai.google.dev/gemma/docs/core/model_card_4)
- [Gemma 4 mobile E2B checkpoint](https://huggingface.co/google/gemma-4-E2B-it-qat-mobile-transformers)
- [Gemma Terms of Use](https://ai.google.dev/gemma/terms)
- [FunctionGemma overview](https://ai.google.dev/gemma/docs/functiongemma)
- [FunctionGemma model card and mobile benchmark](https://ai.google.dev/gemma/docs/functiongemma/model_card)
- [LFM2.5-2.6B release and evaluations](https://www.liquid.ai/blog/lfm2-5-2-6b)
- [LFM2.5-2.6B original checkpoint/license](https://huggingface.co/LiquidAI/LFM2.5-2.6B)
- [LFM2.5-2.6B Q4_0 GGUF](https://huggingface.co/LiquidAI/LFM2.5-2.6B-GGUF)
- [Liquid model catalog](https://www.liquid.ai/models)
- [LFM2.5-VL-3B model card](https://huggingface.co/LiquidAI/LFM2.5-VL-3B)
- [LFM2.5-Audio-1.5B checkpoint/license](https://huggingface.co/LiquidAI/LFM2.5-Audio-1.5B)
- [Needle 3 model card](https://huggingface.co/Cactus-Compute/needle3)
- [Needle 3 source and documentation](https://github.com/cactus-compute/needle)
- [Cactus inference engine](https://github.com/cactus-compute/cactus)

### Runtime and evaluation references

- [MLX Swift package](https://github.com/ml-explore/mlx-swift)
- [MLX Swift LM supported models](https://github.com/ml-explore/mlx-swift-lm/blob/main/skills/mlx-swift-lm/references/supported-models.md)
- [MLX Swift LM tool-calling guide](https://github.com/ml-explore/mlx-swift-lm/blob/main/skills/mlx-swift-lm/references/tool-calling.md)
- [Google LiteRT-LM](https://github.com/google-ai-edge/LiteRT-LM)
- [Gemma deployment/runtime guidance](https://ai.google.dev/gemma/docs/run)
- [Cactus iOS XCFramework build](https://github.com/cactus-compute/cactus/blob/main/apple/README.md)
- [Cactus XCFramework issue #771](https://github.com/cactus-compute/cactus/issues/771)
- [Apple Core AI framework](https://developer.apple.com/documentation/CoreAI)
- [Apple Core AI integration guide](https://developer.apple.com/documentation/CoreAI/integrating-on-device-ai-models-in-your-app-with-core-ai)
- [Apple Core AI ahead-of-time compilation](https://developer.apple.com/documentation/coreai/compiling-core-ai-models-ahead-of-time)
- [Apple Foundation Models availability](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel)
- [Apple Foundation Models sessions](https://developer.apple.com/documentation/foundationmodels/languagemodelsession)
- [Apple on-device speech recognition support](https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition)
- [Apple AVSpeechSynthesizer](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer/)
- [llama.cpp iOS SwiftUI sample](https://github.com/ggml-org/llama.cpp/tree/master/examples/llama.swiftui)
- [ExecuTorch iOS LLM guide](https://docs.pytorch.org/executorch/stable/llm/run-on-ios.html)
- [Community same-harness Apple Silicon/iPhone benchmark](https://github.com/john-rocky/apple-silicon-llm-bench)
